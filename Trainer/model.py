#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
KyonLM Character-Level Causal Language Model (model.py)

Implements the KyonLM v1/v2 specification:
  - Unidirectional (left-to-right) Transformer Decoder-only architecture
  - 10 layers, d_model=640, n_heads=10, d_ff=2560 (~55.5M parameters)
  - Pre-LayerNorm and tied input/output token embeddings
  - Fixed sequence length 48, fixed Core ML batch size 8
  - Inputs:
      input_ids      Int32   [8, 48]
      target_ids     Int32   [8, 48]
      attention_mask Float16 [8, 48]
  - Output:
      token_logprob  Float16 [8, 48] (log P(target_ids[b, t] | input_ids[b, <=t]) * mask[b, t])
"""

import math
from typing import Tuple

import torch
import torch.nn as nn
import torch.nn.functional as F


class CausalSelfAttention(nn.Module):
    """
    ANE-compatible causal multi-head self-attention.
    Uses explicit matmul + static upper-triangular bias (-1e4) so Float16 execution
    on Apple Neural Engine never overflows to -inf/NaN.
    """

    def __init__(
        self,
        d_model: int = 640,
        n_heads: int = 10,
        max_len: int = 48,
        dropout: float = 0.1,
    ) -> None:
        super().__init__()
        if d_model % n_heads != 0:
            raise ValueError(f"d_model ({d_model}) must be divisible by n_heads ({n_heads})")
        self.d_model = d_model
        self.n_heads = n_heads
        self.max_len = max_len
        self.head_dim = d_model // n_heads
        self.scale = 1.0 / math.sqrt(float(self.head_dim))

        self.q_proj = nn.Linear(d_model, d_model)
        self.k_proj = nn.Linear(d_model, d_model)
        self.v_proj = nn.Linear(d_model, d_model)
        self.out_proj = nn.Linear(d_model, d_model)
        self.attn_drop = nn.Dropout(dropout)
        self.resid_drop = nn.Dropout(dropout)

        # Static causal mask: 0.0 on and below diagonal, -1e4 strictly above diagonal
        causal = torch.triu(torch.full((max_len, max_len), -1e4, dtype=torch.float32), diagonal=1)
        self.register_buffer("causal_bias", causal.view(1, 1, max_len, max_len), persistent=False)

    def forward(self, x: torch.Tensor) -> torch.Tensor:
        q = self.q_proj(x).view(-1, self.max_len, self.n_heads, self.head_dim).transpose(1, 2)
        k = self.k_proj(x).view(-1, self.max_len, self.n_heads, self.head_dim).transpose(1, 2)
        v = self.v_proj(x).view(-1, self.max_len, self.n_heads, self.head_dim).transpose(1, 2)

        scores = torch.matmul(q, k.transpose(-2, -1)) * self.scale
        scores = scores + self.causal_bias.to(scores.dtype)
        probs = F.softmax(scores, dim=-1)
        probs = self.attn_drop(probs)

        ctx = torch.matmul(probs, v)
        ctx = ctx.transpose(1, 2).contiguous().view(-1, self.max_len, self.d_model)
        return self.resid_drop(self.out_proj(ctx))


class DecoderBlock(nn.Module):
    """Pre-LayerNorm Transformer Decoder block."""

    def __init__(
        self,
        d_model: int = 640,
        n_heads: int = 10,
        d_ff: int = 2560,
        max_len: int = 48,
        dropout: float = 0.1,
    ) -> None:
        super().__init__()
        self.ln1 = nn.LayerNorm(d_model, eps=1e-5)
        self.attn = CausalSelfAttention(
            d_model=d_model,
            n_heads=n_heads,
            max_len=max_len,
            dropout=dropout,
        )
        self.ln2 = nn.LayerNorm(d_model, eps=1e-5)
        self.ffn = nn.Sequential(
            nn.Linear(d_model, d_ff),
            nn.GELU(),
            nn.Dropout(dropout),
            nn.Linear(d_ff, d_model),
            nn.Dropout(dropout),
        )

    def forward(self, x: torch.Tensor) -> torch.Tensor:
        x = x + self.attn(self.ln1(x))
        x = x + self.ffn(self.ln2(x))
        return x


class KyonCausalLM(nn.Module):
    """
    KyonLM Character-Level Causal Language Model.
    Directly outputs target token log-probabilities [B, 48] rather than full vocab logits.
    """

    def __init__(
        self,
        vocab_size: int = 10500,
        d_model: int = 640,
        n_layers: int = 10,
        n_heads: int = 10,
        d_ff: int = 2560,
        max_len: int = 48,
        dropout: float = 0.1,
    ) -> None:
        super().__init__()
        self.vocab_size = vocab_size
        self.d_model = d_model
        self.n_layers = n_layers
        self.n_heads = n_heads
        self.d_ff = d_ff
        self.max_len = max_len

        self.tok_emb = nn.Embedding(vocab_size, d_model)
        self.pos_emb = nn.Embedding(max_len, d_model)
        self.emb_drop = nn.Dropout(dropout)

        self.blocks = nn.ModuleList(
            [
                DecoderBlock(
                    d_model=d_model,
                    n_heads=n_heads,
                    d_ff=d_ff,
                    max_len=max_len,
                    dropout=dropout,
                )
                for _ in range(n_layers)
            ]
        )
        self.ln_f = nn.LayerNorm(d_model, eps=1e-5)
        self.lm_head = nn.Linear(d_model, vocab_size, bias=False)

        # Weight tying between input token embedding and output projection
        self.lm_head.weight = self.tok_emb.weight

        pos_indices = torch.arange(max_len, dtype=torch.long).unsqueeze(0)
        self.register_buffer("pos_indices", pos_indices, persistent=False)

        self._init_weights()

    def _init_weights(self) -> None:
        for module in self.modules():
            if isinstance(module, nn.Linear):
                nn.init.normal_(module.weight, mean=0.0, std=0.02)
                if module.bias is not None:
                    nn.init.zeros_(module.bias)
            elif isinstance(module, nn.Embedding):
                nn.init.normal_(module.weight, mean=0.0, std=0.02)
            elif isinstance(module, nn.LayerNorm):
                nn.init.ones_(module.weight)
                nn.init.zeros_(module.bias)

    def count_parameters(self) -> int:
        return sum(p.numel() for p in self.parameters() if p.requires_grad)

    def encode_log_probs(self, input_ids: torch.Tensor) -> torch.Tensor:
        """Returns full vocabulary log-probabilities [B, 48, V]."""
        safe_in = input_ids.long().clamp(min=0, max=self.vocab_size - 1)
        h = self.emb_drop(self.tok_emb(safe_in) + self.pos_emb(self.pos_indices))
        for block in self.blocks:
            h = block(h)
        h = self.ln_f(h)
        logits = self.lm_head(h)
        return F.log_softmax(logits, dim=-1)

    def forward_train(
        self,
        input_ids: torch.Tensor,
        target_ids: torch.Tensor,
        attention_mask: torch.Tensor,
    ) -> Tuple[torch.Tensor, torch.Tensor]:
        """
        Training forward pass returning:
          - token_logprob: [B, T] log P(target_ids | input_ids) * mask
          - mean_vocab_logprob: [B, T] mean_v log P(v | input_ids) * mask (for label smoothing)
        """
        log_probs = self.encode_log_probs(input_ids)
        safe_tgt = target_ids.long().clamp(min=0, max=self.vocab_size - 1)
        gathered = torch.gather(log_probs, dim=-1, index=safe_tgt.unsqueeze(-1)).squeeze(-1)
        mask_f = attention_mask.to(gathered.dtype)
        token_logprob = gathered * mask_f
        mean_vocab_lp = log_probs.mean(dim=-1) * mask_f
        return token_logprob, mean_vocab_lp

    def forward(
        self,
        input_ids: torch.Tensor,
        target_ids: torch.Tensor,
        attention_mask: torch.Tensor,
    ) -> torch.Tensor:
        """
        Core ML contract forward pass:
          Inputs:
            input_ids:      Int32   [8, 48]
            target_ids:     Int32   [8, 48]
            attention_mask: Float16 [8, 48]
          Output:
            token_logprob:  Float16 [8, 48]
        """
        log_probs = self.encode_log_probs(input_ids)
        safe_tgt = target_ids.long().clamp(min=0, max=self.vocab_size - 1)
        gathered = torch.gather(log_probs, dim=-1, index=safe_tgt.unsqueeze(-1)).squeeze(-1)
        token_logprob = gathered * attention_mask.to(gathered.dtype)
        return token_logprob


if __name__ == "__main__":
    m = KyonCausalLM(vocab_size=10500, d_model=640, n_layers=10, n_heads=10, d_ff=2560, max_len=48)
    print(f"[model] KyonCausalLM parameters: {m.count_parameters():,} ({m.count_parameters() / 1e6:.2f}M)")
    dummy_in = torch.zeros((8, 48), dtype=torch.int32)
    dummy_tgt = torch.zeros((8, 48), dtype=torch.int32)
    dummy_mask = torch.ones((8, 48), dtype=torch.float32)
    out = m(dummy_in, dummy_tgt, dummy_mask)
    print(f"[model] Output shape: {tuple(out.shape)}, dtype: {out.dtype}")
