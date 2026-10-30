import os
import sys
import json
import torch
import torch.nn as nn
from transformers import AutoModelForMaskedLM, AutoConfig

def _is_dualtask_checkpoint(path: str) -> bool:
    """判斷指定路徑是否為已微調之 DualTaskCSCModel checkpoint"""
    if not os.path.isdir(path):
        return False
    if os.path.exists(os.path.join(path, "detection_head.pt")):
        return True
    cfg_path = os.path.join(path, "config.json")
    if os.path.exists(cfg_path):
        try:
            with open(cfg_path, encoding="utf-8") as f:
                archs = json.load(f).get("architectures") or []
            if "DualTaskCSCModel" in archs:
                return True
        except Exception:
            pass
    # 檢查 safetensors 是否包含 detection_head 前綴
    safe_path = os.path.join(path, "model.safetensors")
    if os.path.exists(safe_path):
        try:
            from safetensors import safe_open
            with safe_open(safe_path, framework="pt") as f:
                if any(k.startswith("detection_head.") for k in f.keys()):
                    return True
        except Exception:
            pass
    # 檢查 pytorch_model.bin 是否包含 detection_head 前綴
    bin_path = os.path.join(path, "pytorch_model.bin")
    if os.path.exists(bin_path):
        try:
            sd = torch.load(bin_path, map_location="cpu", weights_only=True)
            if any(k.startswith("detection_head.") for k in sd.keys()):
                return True
        except Exception:
            pass
    return False

def _load_head_from_ckpt(model, path: str) -> bool:
    """從 model.safetensors 或 pytorch_model.bin 抽取 detection_head 權重載入"""
    prefix = "detection_head."
    sd = None
    st = os.path.join(path, "model.safetensors")
    bn = os.path.join(path, "pytorch_model.bin")
    if os.path.exists(st):
        try:
            from safetensors.torch import load_file
            sd = load_file(st)
        except Exception:
            pass
    elif os.path.exists(bn):
        try:
            sd = torch.load(bn, map_location="cpu", weights_only=True)
        except Exception:
            pass

    if sd is None:
        return False

    head = {k[len(prefix):]: v for k, v in sd.items() if k.startswith(prefix)}
    if not head:
        return False
    model.detection_head.load_state_dict(head)
    return True

class DualTaskCSCModel(nn.Module):
    def __init__(self, model_name="ckiplab/bert-base-chinese"):
        super().__init__()
        self.mlm_model = AutoModelForMaskedLM.from_pretrained(model_name)
        self.config = self.mlm_model.config
        self.detection_head = nn.Linear(self.config.hidden_size, 2)

    def forward(
        self,
        input_ids,
        attention_mask=None,
        token_type_ids=None,
        detection_labels=None,
        correction_labels=None,
    ):
        bert_outputs = self.mlm_model.bert(
            input_ids=input_ids,
            attention_mask=attention_mask,
            token_type_ids=token_type_ids,
            return_dict=True,
        )
        last_hidden_state = bert_outputs.last_hidden_state

        det_logits = self.detection_head(last_hidden_state)
        cor_logits = self.mlm_model.cls(last_hidden_state)

        total_loss = None
        if detection_labels is not None and correction_labels is not None:
            loss_fct = nn.CrossEntropyLoss(ignore_index=-100, reduction="none")
            
            # [batch_size, seq_len]
            loss_det_raw = loss_fct(det_logits.view(-1, 2), detection_labels.view(-1)).view(input_ids.size(0), -1)
            loss_cor_raw = loss_fct(cor_logits.view(-1, self.config.vocab_size), correction_labels.view(-1)).view(input_ids.size(0), -1)

            # Compute adjacent innocent neighbor 5x penalty weights
            valid_mask = (detection_labels != -100).float()
            diff_mask = (detection_labels == 1)
            
            left_diff = torch.zeros_like(diff_mask)
            left_diff[:, 1:] = diff_mask[:, :-1]
            right_diff = torch.zeros_like(diff_mask)
            right_diff[:, :-1] = diff_mask[:, 1:]
            
            neighbor_mask = (left_diff | right_diff) & (~diff_mask) & (valid_mask.bool())
            
            weights = valid_mask.clone()
            weights[neighbor_mask] = 5.0
            
            sum_weights = weights.sum().clamp(min=1e-8)
            loss_det = (loss_det_raw * weights).sum() / sum_weights
            loss_cor = (loss_cor_raw * weights).sum() / sum_weights
            
            total_loss = 0.3 * loss_det + 0.7 * loss_cor

        return {
            "loss": total_loss,
            "detection_logits": det_logits,
            "correction_logits": cor_logits,
        }

    def save_pretrained(self, save_directory):
        os.makedirs(save_directory, exist_ok=True)
        self.mlm_model.save_pretrained(save_directory)
        torch.save(self.detection_head.state_dict(), os.path.join(save_directory, "detection_head.pt"))
        cfg_path = os.path.join(save_directory, "config.json")
        if os.path.exists(cfg_path):
            try:
                with open(cfg_path, "r", encoding="utf-8") as f:
                    cfg = json.load(f)
                cfg["architectures"] = ["DualTaskCSCModel"]
                with open(cfg_path, "w", encoding="utf-8") as f:
                    json.dump(cfg, f, indent=2, ensure_ascii=False)
            except Exception:
                pass

    @classmethod
    def from_pretrained(cls, save_directory_or_name, *model_args, **kwargs):
        path = str(save_directory_or_name)
        model = cls(path)
        if _is_dualtask_checkpoint(path):
            pt_path = os.path.join(path, "detection_head.pt")
            if os.path.exists(pt_path):
                try:
                    state_dict = torch.load(pt_path, map_location="cpu", weights_only=True)
                except TypeError:
                    state_dict = torch.load(pt_path, map_location="cpu")
                model.detection_head.load_state_dict(state_dict)
            elif not _load_head_from_ckpt(model, path):
                raise RuntimeError(f"[FATAL] {path} 被判定為 DualTask checkpoint，但無法從 detection_head.pt / safetensors / bin 載入 detection_head 權重！")
        return model
