import os
import sys

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
ROOT_DIR = os.path.abspath(os.path.join(SCRIPT_DIR, "..")) if os.path.basename(SCRIPT_DIR) == "scripts" else SCRIPT_DIR
if ROOT_DIR not in sys.path:
    sys.path.insert(0, ROOT_DIR)
SRC_DIR = os.path.join(ROOT_DIR, "src")
if SRC_DIR not in sys.path:
    sys.path.insert(0, SRC_DIR)

import time
import torch
from model import DualTaskCSCModel

if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8")

MODEL_DIR = os.path.join(ROOT_DIR, "saved_model") if os.path.exists(os.path.join(ROOT_DIR, "saved_model")) else "ckiplab/bert-base-chinese"
OUTPUT_COREML = os.path.join(ROOT_DIR, "ml.mlpackage")
MAX_SEQ_LEN = 128

class CoreMLWrapper(torch.nn.Module):
    def __init__(self, model):
        super().__init__()
        self.model = model

    def forward(self, input_ids, attention_mask):
        outputs = self.model(input_ids=input_ids, attention_mask=attention_mask)
        det_probs = torch.softmax(outputs["detection_logits"], dim=-1)
        cor_probs = torch.softmax(outputs["correction_logits"], dim=-1)
        return det_probs, cor_probs

def main():
    try:
        import coremltools as ct
    except ImportError:
        print("[ERROR] 尚未安裝 coremltools。請在 Mac 終端機執行: pip install coremltools")
        sys.exit(1)

    print("=" * 70)
    print(f"[INFO] 正在載入模型權重: {MODEL_DIR}...")
    model = DualTaskCSCModel.from_pretrained(MODEL_DIR)
    model.eval()

    wrapper = CoreMLWrapper(model)
    dummy_input_ids = torch.zeros((1, MAX_SEQ_LEN), dtype=torch.int32)
    dummy_mask = torch.ones((1, MAX_SEQ_LEN), dtype=torch.int32)

    print("[INFO] 正在追蹤 (Trace) PyTorch 計算圖...")
    with torch.no_grad():
        traced_model = torch.jit.trace(wrapper, (dummy_input_ids, dummy_mask))

    print("[INFO] 正在轉換為 CoreML FP16 半精度格式 (ANE 最佳化規格)...")
    mlmodel = ct.convert(
        traced_model,
        inputs=[
            ct.TensorType(name="input_ids", shape=(1, MAX_SEQ_LEN), dtype=int),
            ct.TensorType(name="attention_mask", shape=(1, MAX_SEQ_LEN), dtype=int),
        ],
        outputs=[
            ct.TensorType(name="detection_probs"),
            ct.TensorType(name="correction_probs"),
        ],
        compute_precision=ct.precision.FLOAT16,
        compute_units=ct.ComputeUnit.ALL,
    )

    mlmodel.save(OUTPUT_COREML)
    print(f"[SUCCESS] 成功導出 CoreML 模型至: {OUTPUT_COREML}")

    # Verify directly on macOS ANE
    if sys.platform == "darwin":
        import numpy as np
        print("\n[INFO] 偵測到 macOS 系統，正在啟動 ANE 硬體延遲實測...")
        try:
            ane_model = ct.models.MLModel(OUTPUT_COREML)
            d_ids = np.zeros((1, MAX_SEQ_LEN), dtype=np.int32)
            d_mask = np.ones((1, MAX_SEQ_LEN), dtype=np.int32)
            for _ in range(5):
                _ = ane_model.predict({"input_ids": d_ids, "attention_mask": d_mask})
            t0 = time.time()
            iters = 50
            for _ in range(iters):
                _ = ane_model.predict({"input_ids": d_ids, "attention_mask": d_mask})
            t1 = time.time()
            latency = (t1 - t0) / iters * 1000
            print(f"[SUCCESS] ANE 硬體驗證完成！平均單句推論耗時: {latency:.2f} ms")
        except Exception as e:
            print(f"[WARNING] ANE 推論測試失敗: {e}")
    else:
        print("[NOTICE] 當前非 macOS 系統，跳過 ANE 硬體即時預測（請在 Mac 上執行以測量速度）。")
    print("=" * 70)

if __name__ == "__main__":
    main()
