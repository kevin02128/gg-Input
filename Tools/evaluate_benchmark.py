#!/usr/bin/env python3
"""
Evaluation reporting script for gg (榦注音).
Reads TestingData/benchmark_results_swiftengine.json and prints detailed breakdown.
Also identifies sentences that failed for targeted CoreML sampling analysis.
"""

import json
import os
import sys

REPO_ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
RESULTS_JSON = os.path.join(REPO_ROOT, "TestingData/benchmark_results_swiftengine.json")

if not os.path.exists(RESULTS_JSON):
    print(f"[ERROR] Results file not found: {RESULTS_JSON}")
    sys.exit(1)

with open(RESULTS_JSON, "r", encoding="utf-8") as f:
    records = json.load(f)

total = len(records)
exact = sum(1 for r in records if r["exact"])
exact_pct = exact / total * 100.0
mean_cer = sum(r["cer"] for r in records) / total * 100.0
mean_lat = sum(r["latencyMs"] for r in records) / total

dev_records = [r for r in records if r["split"] == "dev"]
dev_exact = sum(1 for r in dev_records if r["exact"])
dev_pct = dev_exact / len(dev_records) * 100.0 if dev_records else 0.0

test_records = [r for r in records if r["split"] == "test"]
test_exact = sum(1 for r in test_records if r["exact"])
test_pct = test_exact / len(test_records) * 100.0 if test_records else 0.0

categories = {}
for r in records:
    cat = r["category"]
    if cat not in categories:
        categories[cat] = {"total": 0, "exact": 0, "failures": []}
    categories[cat]["total"] += 1
    if r["exact"]:
        categories[cat]["exact"] += 1
    else:
        categories[cat]["failures"].append(r)

print("\n" + "=" * 80)
print("             gg (榦注音) SWIFTENGINE 基線評測成果報表 (500 句)")
print("=" * 80)
print(f"總全句正確率 (Exact Match):   {exact} / {total} ({exact_pct:.2f}%)")
print(f"平均字錯率 (Mean CER):        {mean_cer:.2f}%")
print(f"平均解碼延遲 (Mean Latency):  {mean_lat:.3f} ms")
print("-" * 80)
print(f"開發集 (Dev Set, 250 句):     {dev_exact} / {len(dev_records)} ({dev_pct:.2f}%)")
print(f"留出測試集 (Holdout, 250 句):  {test_exact} / {len(test_records)} ({test_pct:.2f}%)")
print("-" * 80)
print("分項類別正確率：")
for cat, data in categories.items():
    pct = data["exact"] / data["total"] * 100.0
    print(f"  • {cat:22s}: {data['exact']:3d} / {data['total']:3d} ({pct:.2f}%) [失敗 {len(data['failures'])} 句]")
print("=" * 80 + "\n")

# Print failure overview
failed_records = [r for r in records if not r["exact"]]
print(f"[INFO] 總失敗句數: {len(failed_records)} 句。")
for i, item in enumerate(failed_records[:10], 1):
    print(f"  [{i:2d}] 目標: {item['target']} | 預測: {item['predicted']} | 類別: {item['category']}")

