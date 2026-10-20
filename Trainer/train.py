#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
KyonLM Training, Validation, and Core ML Export Pipeline (train.py)

Implements the complete KyonLM v1/v2 training specification:
  - Character-level unidirectional Transformer LM (~55.5M params: 10L, 640D, 10H, 2560FF)
  - Joint Language Modeling Cross-Entropy + Dynamic Homophone Margin Ranking loss
  - Real-time progress bar, ETA timer, Ctrl+C safe checkpointing
  - Section 6 & 7 validation:
      1. Synthetic homophone preference test on held-out validation sentences (>= 95% target)
      2. 7 diagnostic contrast pairs (鑰匙不在他身上 vs 鑰匙不再他身上, etc.)
      3. 50 homophone/lexicon/particle correction cases from homophone_regression.tsv
  - Core ML MLProgram Float16 export with fixed [8, 48] tensors and SHA-256 metadata
"""

import argparse
import json
import math
import os
import random
import shutil
import signal
import subprocess
import sys
import time
from typing import Dict, List, Optional, Tuple

import numpy as np
import torch
import torch.nn.functional as F
from torch.utils.data import DataLoader

from build_vocab import build_vocab, load_vocab
from dataset import HomophoneSampler, KyonContrastiveDataset, encode_sentence_tensors
from model import KyonCausalLM
from prepare_corpus import prepare_corpus

DIAGNOSTIC_PAIRS: List[Tuple[str, str]] = [
    ("鑰匙不在他身上", "鑰匙不再他身上"),
    ("他戴著耳機", "他帶著耳機"),
    ("慢慢地走向門口", "慢慢的走向門口"),
    ("請大家先在這裡等一下", "請大家先再這裡等一下"),
    ("系統能自動偵測異常流量", "系統能自動政策異常流量"),
    ("我們需要清理冗餘的資料", "我們需要清理茸於的資料"),
    ("他每天早上都喝一杯蘋果汁", "他每天早上都喝一杯蘋國汁"),
]


class GracefulStopper:
    def __init__(self) -> None:
        self.stop_requested = False
        signal.signal(signal.SIGINT, self._handler)
        signal.signal(signal.SIGTERM, self._handler)

    def _handler(self, signum: int, frame: object) -> None:
        if not self.stop_requested:
            print("\n[train] Interrupt signal received. Finishing current step and exporting best model...")
            self.stop_requested = True


def format_seconds(sec: float) -> str:
    sec = max(0, int(sec))
    h = sec // 3600
    m = (sec % 3600) // 60
    s = sec % 60
    return f"{h:02d}:{m:02d}:{s:02d}"


@torch.no_grad()
def score_sentence_batch(
    model: KyonCausalLM,
    sentences: List[str],
    token_to_id: Dict[str, int],
    device: torch.device,
    max_len: int = 48,
) -> List[float]:
    """
    Computes mean per-token log-probability for a list of sentences,
    matching KyonLMScorer.score(sentences:) in WTFNeuralReranker.swift.
    """
    model.eval()
    results: List[float] = []
    batch_size = 8

    for start in range(0, len(sentences), batch_size):
        chunk = sentences[start : start + batch_size]
        in_list: List[torch.Tensor] = []
        tgt_list: List[torch.Tensor] = []
        mask_list: List[torch.Tensor] = []

        for s in chunk:
            inp, tgt, msk = encode_sentence_tensors(s, token_to_id, max_len=max_len)
            in_list.append(inp)
            tgt_list.append(tgt)
            mask_list.append(msk)

        while len(in_list) < batch_size:
            in_list.append(torch.zeros((max_len,), dtype=torch.long))
            tgt_list.append(torch.zeros((max_len,), dtype=torch.long))
            mask_list.append(torch.zeros((max_len,), dtype=torch.float32))

        b_in = torch.stack(in_list, dim=0).to(device)
        b_tgt = torch.stack(tgt_list, dim=0).to(device)
        b_msk = torch.stack(mask_list, dim=0).to(device)

        tok_lp = model(b_in, b_tgt, b_msk)
        lengths = b_msk.sum(dim=-1).clamp(min=1.0)
        mean_lp = (tok_lp.sum(dim=-1) / lengths).cpu().tolist()

        for i in range(len(chunk)):
            results.append(float(mean_lp[i]))

    return results


@torch.no_grad()
def run_validation_suite(
    model: KyonCausalLM,
    val_sentences: List[str],
    sampler: HomophoneSampler,
    token_to_id: Dict[str, int],
    regression_tsv_path: str,
    device: torch.device,
    max_len: int = 48,
    max_val_pairs: int = 400,
) -> Dict[str, float]:
    model.eval()
    rng = random.Random(1001)

    # 1. Section 6.1: Synthetic Homophone Preference Test on held-out validation sentences
    eval_pos: List[str] = []
    eval_neg: List[str] = []
    for s in val_sentences:
        if len(eval_pos) >= max_val_pairs:
            break
        neg_s = sampler.corrupt_sentence(s, rng, max_replacements=1)
        if neg_s != s:
            eval_pos.append(s)
            eval_neg.append(neg_s)

    t0 = time.time()
    pos_scores = score_sentence_batch(model, eval_pos, token_to_id, device, max_len=max_len)
    neg_scores = score_sentence_batch(model, eval_neg, token_to_id, device, max_len=max_len)
    elapsed_ms = (time.time() - t0) * 1000.0
    num_batches = max(1, (len(eval_pos) + 7) // 8 * 2)
    ms_per_batch8 = elapsed_ms / num_batches

    wins = sum(1 for p, n in zip(pos_scores, neg_scores) if p > n)
    synth_acc = (wins / max(1, len(eval_pos))) * 100.0
    avg_pos_lp = sum(pos_scores) / max(1, len(pos_scores))
    avg_margin = sum(p - n for p, n in zip(pos_scores, neg_scores)) / max(1, len(pos_scores))

    # 2. Section 7: 7 Self-Check Diagnostic Pairs
    diag_pos = [p for p, _ in DIAGNOSTIC_PAIRS]
    diag_neg = [n for _, n in DIAGNOSTIC_PAIRS]
    d_pos_sc = score_sentence_batch(model, diag_pos, token_to_id, device, max_len=max_len)
    d_neg_sc = score_sentence_batch(model, diag_neg, token_to_id, device, max_len=max_len)
    diag_wins = sum(1 for p, n in zip(d_pos_sc, d_neg_sc) if p > n)

    # 3. Section 6.2: IME Regression Benchmark Correction Preference
    bench_pos: List[str] = []
    bench_neg: List[str] = []
    if os.path.exists(regression_tsv_path):
        with open(regression_tsv_path, "r", encoding="utf-8") as f:
            for line in f:
                line = line.strip()
                if not line or line.startswith("#"):
                    continue
                parts = line.split("\t")
                if len(parts) >= 4:
                    cat = parts[0]
                    vit = parts[2].replace("|", "")
                    exp = parts[3]
                    if cat != "control" and vit != exp:
                        bench_pos.append(exp)
                        bench_neg.append(vit)

    if bench_pos:
        b_pos_sc = score_sentence_batch(model, bench_pos, token_to_id, device, max_len=max_len)
        b_neg_sc = score_sentence_batch(model, bench_neg, token_to_id, device, max_len=max_len)
        bench_wins = sum(1 for p, n in zip(b_pos_sc, b_neg_sc) if p > n)
        bench_acc = (bench_wins / len(bench_pos)) * 100.0
    else:
        bench_acc = 100.0

    print("\n  [Validation Diagnostic Pairs (Section 7)]")
    for (p_str, n_str), p_sc, n_sc in zip(DIAGNOSTIC_PAIRS, d_pos_sc, d_neg_sc):
        status = "PASS" if p_sc > n_sc else "FAIL"
        print(
            f"    [{status}] {p_str} ({p_sc:.3f}) vs {n_str} ({n_sc:.3f}) | diff={p_sc - n_sc:+.3f}"
        )

    return {
        "synth_homophone_acc": synth_acc,
        "bench_preference_acc": bench_acc,
        "diagnostic_pass_rate": (diag_wins / len(DIAGNOSTIC_PAIRS)) * 100.0,
        "avg_pos_logprob": avg_pos_lp,
        "avg_margin": avg_margin,
        "ms_per_batch8": ms_per_batch8,
    }


def export_coreml_model(
    model: KyonCausalLM,
    vocab_path: str,
    vocab_sha256: str,
    export_dir: str,
    gg_model_dir: str,
    batch_size: int = 8,
    max_len: int = 48,
) -> bool:
    """
    Exports KyonLM.mlpackage (Float16, macOS 13+) with exact [8, 48] input/output
    tensors and userDefinedMetadata, compiles KyonLM.mlmodelc, and deploys both
    KyonLM.mlmodelc and vocab.txt to gg's Source/Resources/Model/ and Application Support.
    """
    try:
        import coremltools as ct
    except ImportError:
        print("[export] ERROR: coremltools is not installed.")
        return False

    os.makedirs(export_dir, exist_ok=True)
    cpu_model = KyonCausalLM(
        vocab_size=model.vocab_size,
        d_model=model.d_model,
        n_layers=model.n_layers,
        n_heads=model.n_heads,
        d_ff=model.d_ff,
        max_len=model.max_len,
        dropout=0.0,
    )
    cpu_model.load_state_dict(model.state_dict())
    cpu_model.eval()

    dummy_in = torch.zeros((batch_size, max_len), dtype=torch.int32)
    dummy_tgt = torch.zeros((batch_size, max_len), dtype=torch.int32)
    dummy_mask = torch.ones((batch_size, max_len), dtype=torch.float32)

    print("[export] Tracing KyonCausalLM with TorchScript...")
    with torch.no_grad():
        traced = torch.jit.trace(cpu_model, (dummy_in, dummy_tgt, dummy_mask))

    mlpackage_path = os.path.join(export_dir, "KyonLM.mlpackage")
    if os.path.exists(mlpackage_path):
        shutil.rmtree(mlpackage_path)

    print("[export] Converting to Core ML MLProgram (Float16, macOS 13+)...")
    mlmodel = ct.convert(
        traced,
        convert_to="mlprogram",
        minimum_deployment_target=ct.target.macOS13,
        compute_precision=ct.precision.FLOAT16,
        inputs=[
            ct.TensorType(name="input_ids", shape=(batch_size, max_len), dtype=np.int32),
            ct.TensorType(name="target_ids", shape=(batch_size, max_len), dtype=np.int32),
            ct.TensorType(name="attention_mask", shape=(batch_size, max_len), dtype=np.float16),
        ],
        outputs=[
            ct.TensorType(name="token_logprob", dtype=np.float16),
        ],
    )

    mlmodel.author = "wtf / KyonLM Trainer"
    mlmodel.short_description = (
        "KyonLM character-level unidirectional Traditional Chinese language model for IME N-Best reranking"
    )
    mlmodel.version = "2.0.0"
    mlmodel.user_defined_metadata["kyon.version"] = "2.0.0"
    mlmodel.user_defined_metadata["kyon.seq_len"] = str(max_len)
    mlmodel.user_defined_metadata["kyon.batch"] = str(batch_size)
    mlmodel.user_defined_metadata["kyon.vocab_sha256"] = vocab_sha256

    mlmodel.save(mlpackage_path)
    print(f"[export] Saved {mlpackage_path}")

    # Compile to .mlmodelc via xcrun coremlcompiler
    mlmodelc_path = os.path.join(export_dir, "KyonLM.mlmodelc")
    if os.path.exists(mlmodelc_path):
        shutil.rmtree(mlmodelc_path)

    subprocess.run(
        ["xcrun", "coremlcompiler", "compile", mlpackage_path, export_dir],
        check=True,
    )
    print(f"[export] Compiled {mlmodelc_path}")

    # Deploy to gg/Source/Resources/Model/ and ~/Library/Application Support/gg/Models/
    deploy_targets = [
        gg_model_dir,
        os.path.expanduser("~/Library/Application Support/gg/Models"),
    ]
    for target_dir in deploy_targets:
        if not target_dir:
            continue
        os.makedirs(target_dir, exist_ok=True)
        dst_modelc = os.path.join(target_dir, "KyonLM.mlmodelc")
        dst_vocab = os.path.join(target_dir, "vocab.txt")
        if os.path.exists(dst_modelc):
            shutil.rmtree(dst_modelc)
        shutil.copytree(mlmodelc_path, dst_modelc)
        shutil.copy2(vocab_path, dst_vocab)
        print(f"[export] Deployed KyonLM.mlmodelc and vocab.txt -> {target_dir}")

    # Also copy KyonLM.mlpackage to gg_model_dir for reference
    if gg_model_dir:
        dst_pkg = os.path.join(gg_model_dir, "KyonLM.mlpackage")
        if os.path.exists(dst_pkg):
            shutil.rmtree(dst_pkg)
        shutil.copytree(mlpackage_path, dst_pkg)

    return True


def main() -> None:
    parser = argparse.ArgumentParser(description="Train KyonLM Character-Level Causal Language Model")
    parser.add_argument("--gg-root", type=str, default="/Users/kevin/development/gg")
    parser.add_argument("--trainer-root", type=str, default="/Users/kevin/development/gg_trainer")
    parser.add_argument("--hours", type=float, default=9.5, help="Target training duration in hours")
    parser.add_argument("--max-epochs", type=int, default=200, help="Maximum epochs")
    parser.add_argument("--batch-size", type=int, default=16, help="Micro-batch size (pairs of pos+neg)")
    parser.add_argument("--grad-accum", type=int, default=2, help="Gradient accumulation steps")
    parser.add_argument("--lr", type=float, default=3e-4, help="Peak learning rate")
    parser.add_argument("--min-lr", type=float, default=1.5e-5, help="Minimum cosine learning rate")
    parser.add_argument("--margin", type=float, default=0.40, help="Log-probability margin between pos and neg")
    parser.add_argument("--rank-weight", type=float, default=2.5, help="Weight for pairwise ranking loss")
    parser.add_argument("--d-model", type=int, default=640, help="Transformer hidden dimension (spec: 640)")
    parser.add_argument("--n-layers", type=int, default=10, help="Transformer layers (spec: 10)")
    parser.add_argument("--n-heads", type=int, default=10, help="Attention heads (spec: 10)")
    parser.add_argument("--d-ff", type=int, default=2560, help="FFN hidden dimension (spec: 2560)")
    parser.add_argument("--max-vocab", type=int, default=10500, help="Maximum vocabulary size")
    parser.add_argument("--resume", action="store_true", help="Resume from checkpoints/latest.pt if available")
    parser.add_argument("--rebuild-data", action="store_true", help="Force rebuild of vocab.txt and corpus")
    parser.add_argument("--seed", type=int, default=42)
    args = parser.parse_args()

    random.seed(args.seed)
    np.random.seed(args.seed)
    torch.manual_seed(args.seed)

    lexicon_path = os.path.join(args.gg_root, "Source/Data/data.txt")
    regression_tsv = os.path.join(args.gg_root, "McBopomofoTests/Fixtures/homophone_regression.tsv")
    gg_model_dir = os.path.join(args.gg_root, "Source/Resources/Model")

    vocab_path = os.path.join(args.trainer_root, "data/vocab.txt")
    train_corpus_path = os.path.join(args.trainer_root, "corpus/train_sentences.txt")
    val_corpus_path = os.path.join(args.trainer_root, "corpus/val_sentences.txt")
    ckpt_dir = os.path.join(args.trainer_root, "checkpoints")
    export_dir = os.path.join(args.trainer_root, "export")
    os.makedirs(ckpt_dir, exist_ok=True)
    os.makedirs(export_dir, exist_ok=True)

    # 1. Build or load vocabulary
    if args.rebuild_data or not os.path.exists(vocab_path):
        build_vocab(lexicon_path=lexicon_path, output_path=vocab_path, max_vocab_size=args.max_vocab)
    token_to_id, id_to_token, vocab_sha256 = load_vocab(vocab_path)
    vocab_size = len(token_to_id)
    print(f"[train] Vocabulary loaded: {vocab_size:,} tokens (SHA-256: {vocab_sha256[:16]}...)")

    # 2. Prepare or load corpus
    if args.rebuild_data or not os.path.exists(train_corpus_path) or not os.path.exists(val_corpus_path):
        prepare_corpus(gg_root=args.gg_root, trainer_root=args.trainer_root, seed=args.seed)

    # 3. Initialize HomophoneSampler and Datasets
    print("[train] Indexing homophone groups from Source/Data/data.txt...")
    sampler = HomophoneSampler(lexicon_path=lexicon_path)
    train_dataset = KyonContrastiveDataset(
        sentences_path=train_corpus_path,
        token_to_id=token_to_id,
        sampler=sampler,
        max_len=48,
        is_train=True,
        seed=args.seed,
    )
    with open(val_corpus_path, "r", encoding="utf-8") as f:
        val_sentences = [line.strip() for line in f if 4 <= len(line.strip()) <= 46]

    train_loader = DataLoader(
        train_dataset,
        batch_size=args.batch_size,
        shuffle=True,
        num_workers=0,
        drop_last=True,
    )

    # 4. Select device (Apple Silicon MPS preferred)
    if torch.backends.mps.is_available():
        device = torch.device("mps")
    elif torch.cuda.is_available():
        device = torch.device("cuda")
    else:
        device = torch.device("cpu")

    model = KyonCausalLM(
        vocab_size=vocab_size,
        d_model=args.d_model,
        n_layers=args.n_layers,
        n_heads=args.n_heads,
        d_ff=args.d_ff,
        max_len=48,
        dropout=0.1,
    ).to(device)

    param_count = model.count_parameters()
    print("=" * 76)
    print("  KyonLM v2 Character-Level Unidirectional Transformer Trainer")
    print(f"  Device           : {device}")
    print(f"  Architecture     : {args.n_layers}L, d_model={args.d_model}, heads={args.n_heads}, d_ff={args.d_ff}")
    print(f"  Parameters       : {param_count:,} ({param_count / 1e6:.2f}M)")
    print(f"  Train Sentences  : {len(train_dataset):,} (+ dynamic on-the-fly homophone negatives)")
    print(f"  Val Sentences    : {len(val_sentences):,}")
    print(f"  Target Duration  : {args.hours:.2f} hours ({format_seconds(args.hours * 3600)})")
    print("=" * 76)

    optimizer = torch.optim.AdamW(
        model.parameters(),
        lr=args.lr,
        betas=(0.9, 0.98),
        eps=1e-8,
        weight_decay=0.01,
    )

    start_epoch = 0
    global_step = 0
    best_composite_score = -1e9
    latest_ckpt = os.path.join(ckpt_dir, "latest.pt")
    best_ckpt = os.path.join(ckpt_dir, "best.pt")

    if args.resume and os.path.exists(latest_ckpt):
        ckpt = torch.load(latest_ckpt, map_location=device)
        if ckpt.get("vocab_size") == vocab_size and ckpt.get("d_model") == args.d_model:
            model.load_state_dict(ckpt["model_state_dict"])
            optimizer.load_state_dict(ckpt["optimizer_state_dict"])
            start_epoch = int(ckpt.get("epoch", 0))
            global_step = int(ckpt.get("global_step", 0))
            best_composite_score = float(ckpt.get("best_composite_score", -1e9))
            print(f"[train] Resumed from {latest_ckpt} (epoch={start_epoch}, step={global_step})")

    stopper = GracefulStopper()
    start_time = time.time()
    time_budget_sec = max(10.0, args.hours * 3600.0)
    warmup_steps = 150

    def evaluate_and_checkpoint(ep_num: int) -> None:
        nonlocal best_composite_score
        val_metrics = run_validation_suite(
            model=model,
            val_sentences=val_sentences,
            sampler=sampler,
            token_to_id=token_to_id,
            regression_tsv_path=regression_tsv,
            device=device,
            max_len=48,
        )
        synth_acc = val_metrics["synth_homophone_acc"]
        bench_acc = val_metrics["bench_preference_acc"]
        diag_acc = val_metrics["diagnostic_pass_rate"]
        avg_margin = val_metrics["avg_margin"]
        ms_batch8 = val_metrics["ms_per_batch8"]

        composite = 0.45 * synth_acc + 0.35 * bench_acc + 0.20 * diag_acc + min(5.0, avg_margin * 2.0)
        print(
            f"  [Val Summary] SynthHomophoneAcc: {synth_acc:.2f}% (target >=95%) | "
            f"BenchPrefAcc: {bench_acc:.2f}% | "
            f"DiagPairs: {diag_acc:.1f}% | "
            f"Margin: {avg_margin:+.3f} | "
            f"Batch8 Latency: {ms_batch8:.2f}ms"
        )

        ckpt_payload = {
            "epoch": ep_num,
            "global_step": global_step,
            "vocab_size": vocab_size,
            "vocab_sha256": vocab_sha256,
            "d_model": args.d_model,
            "n_layers": args.n_layers,
            "n_heads": args.n_heads,
            "d_ff": args.d_ff,
            "best_composite_score": max(best_composite_score, composite),
            "val_metrics": val_metrics,
            "model_state_dict": model.state_dict(),
            "optimizer_state_dict": optimizer.state_dict(),
        }
        torch.save(ckpt_payload, latest_ckpt)

        if composite >= best_composite_score:
            best_composite_score = composite
            torch.save(ckpt_payload, best_ckpt)
            with open(os.path.join(ckpt_dir, "best_metrics.json"), "w", encoding="utf-8") as mf:
                json.dump(val_metrics, mf, indent=2, ensure_ascii=False)
            print(f"  [Checkpoint] New best model saved -> {best_ckpt} (score={composite:.2f})")

        if device.type == "mps":
            torch.mps.empty_cache()
        model.train()

    for epoch in range(start_epoch, args.max_epochs):
        if stopper.stop_requested or (time.time() - start_time) >= time_budget_sec:
            break

        model.train()
        train_dataset.rng.seed(args.seed + epoch * 997)
        optimizer.zero_grad()

        running_ce = 0.0
        running_rank = 0.0
        running_acc = 0.0
        steps_in_epoch = 0
        total_batches = max(1, len(train_loader))

        for b_idx, (pos_in, pos_tgt, pos_mask, neg_in, neg_tgt, neg_mask) in enumerate(train_loader):
            elapsed = time.time() - start_time
            if stopper.stop_requested or elapsed >= time_budget_sec:
                break

            # Cosine LR schedule based on time progress
            time_progress = min(1.0, elapsed / time_budget_sec)
            if global_step < warmup_steps:
                cur_lr = args.lr * float(global_step + 1) / float(warmup_steps)
            else:
                cosine_factor = 0.5 * (1.0 + math.cos(math.pi * time_progress))
                cur_lr = args.min_lr + (args.lr - args.min_lr) * cosine_factor
            for pg in optimizer.param_groups:
                pg["lr"] = cur_lr

            bsz = pos_in.size(0)
            cat_in = torch.cat([pos_in, neg_in], dim=0).to(device)
            cat_tgt = torch.cat([pos_tgt, neg_tgt], dim=0).to(device)
            cat_mask = torch.cat([pos_mask, neg_mask], dim=0).to(device)

            tok_lp, mean_vocab_lp = model.forward_train(cat_in, cat_tgt, cat_mask)
            pos_tok_lp = tok_lp[:bsz]
            neg_tok_lp = tok_lp[bsz:]
            pos_vocab_lp = mean_vocab_lp[:bsz]

            pos_len = cat_mask[:bsz].sum(dim=-1).clamp(min=1.0)
            neg_len = cat_mask[bsz:].sum(dim=-1).clamp(min=1.0)

            pos_sent_lp = pos_tok_lp.sum(dim=-1) / pos_len
            neg_sent_lp = neg_tok_lp.sum(dim=-1) / neg_len

            # 1. Cross-Entropy Loss on positive sentences with 0.02 label smoothing
            ce_loss = -0.98 * pos_sent_lp.mean() - 0.02 * (pos_vocab_lp.sum(dim=-1) / pos_len).mean()

            # 2. Margin Ranking Loss between positive and same-reading negative sentences
            diff = pos_sent_lp - neg_sent_lp
            hinge = F.relu(args.margin - diff)
            smooth_rank = F.softplus((args.margin - diff) / 0.15) * 0.15
            rank_loss = (hinge + 0.5 * smooth_rank).mean()

            loss = (ce_loss + args.rank_weight * rank_loss) / float(args.grad_accum)
            loss.backward()

            if (b_idx + 1) % args.grad_accum == 0 or (b_idx + 1) == total_batches:
                torch.nn.utils.clip_grad_norm_(model.parameters(), max_norm=1.0)
                optimizer.step()
                optimizer.zero_grad()
                global_step += 1

            batch_win = (diff > 0).float().mean().item()
            running_ce += ce_loss.item()
            running_rank += rank_loss.item()
            running_acc += batch_win
            steps_in_epoch += 1

            if (b_idx + 1) % 25 == 0 or (b_idx + 1) == total_batches:
                rem_sec = max(0.0, time_budget_sec - elapsed)
                pct = min(100.0, (elapsed / time_budget_sec) * 100.0)
                sys.stdout.write(
                    f"\r  [Epoch {epoch + 1:03d} | {b_idx + 1:05d}/{total_batches:05d}] "
                    f"CE: {running_ce / steps_in_epoch:.3f} | "
                    f"Rank: {running_rank / steps_in_epoch:.4f} | "
                    f"PairAcc: {(running_acc / steps_in_epoch) * 100.0:5.1f}% | "
                    f"LR: {cur_lr:.2e} | "
                    f"Time: {format_seconds(elapsed)} / {format_seconds(time_budget_sec)} ({pct:4.1f}%, ETA {format_seconds(rem_sec)})"
                )
                sys.stdout.flush()

            # Periodic validation & checkpointing every 2500 batches (~25 min on M1)
            if (b_idx + 1) % 2500 == 0 and (b_idx + 1) < total_batches:
                print()
                evaluate_and_checkpoint(epoch + 1)

        print()
        evaluate_and_checkpoint(epoch + 1)

    # Load best checkpoint before final Core ML export
    if os.path.exists(best_ckpt):
        print(f"\n[train] Loading best checkpoint from {best_ckpt} for Core ML export...")
        best_data = torch.load(best_ckpt, map_location=device)
        model.load_state_dict(best_data["model_state_dict"])

    exported = export_coreml_model(
        model=model,
        vocab_path=vocab_path,
        vocab_sha256=vocab_sha256,
        export_dir=export_dir,
        gg_model_dir=gg_model_dir,
        batch_size=8,
        max_len=48,
    )

    # Run reviewer threshold calibration script if present
    calib_script = os.path.join(args.gg_root, "Source/Data/scripts/calibrate_reviewer.py")
    if exported and os.path.exists(calib_script):
        print("[train] Running reviewer threshold calibration (calibrate_reviewer.py)...")
        subprocess.run([sys.executable, calib_script], check=False)

    total_elapsed = time.time() - start_time
    print(f"\n[train] Pipeline finished in {format_seconds(total_elapsed)}.")


if __name__ == "__main__":
    main()
