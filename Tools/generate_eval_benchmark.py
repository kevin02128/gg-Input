#!/usr/bin/env python3
"""
Generate gold-standard 500-sentence evaluation benchmark for gg (榦注音).
Strictly partitions 500 sentences into:
- 250 Development Set ('dev')
- 250 Holdout Test Set ('test')
Across 3 categories:
1. homophone / ambiguous (100 sentences: 50 dev, 50 test)
2. colloquial / daily conversation (200 sentences: 100 dev, 100 test)
3. official / news / administrative (200 sentences: 100 dev, 100 test)
"""

import json
import os
import re

REPO_ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
DATA_TXT = os.path.join(REPO_ROOT, "Source/Data/data.txt")
MODEL_DIR = os.environ.get("GG_MODEL_DIR", os.path.expanduser("~/development/gg_model"))
BENCHMARK_100 = os.path.join(MODEL_DIR, "data/benchmark_100.json")
DEV_JSONL = os.path.join(MODEL_DIR, "data/dev.jsonl")
OUTPUT_JSONL = os.path.join(REPO_ROOT, "TestingData/eval_benchmark.jsonl")

# 1. Load data.txt to build multi-char word and single-char dictionary
print("[INFO] Loading data.txt dictionary...")
word_to_reading = {}
char_to_reading = {}

with open(DATA_TXT, "r", encoding="utf-8") as f:
    for line in f:
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        parts = line.split()
        if len(parts) >= 3:
            reading, val, score = parts[0], parts[1], float(parts[2])
            if reading.startswith("_"):
                continue
            if len(val) == 1:
                # Prefer highest unigram score for single char default reading
                if val not in char_to_reading or score > char_to_reading[val][1]:
                    char_to_reading[val] = (reading, score)
            else:
                if val not in word_to_reading or score > word_to_reading[val][1]:
                    word_to_reading[val] = (reading, score)

print(f"[INFO] Loaded {len(word_to_reading):,} words and {len(char_to_reading):,} single characters.")

def sentence_to_readings(text):
    """
    Max-match greedy segmentation using data.txt vocabulary.
    Returns list of bopomofo readings, or None if any character cannot be resolved.
    """
    i = 0
    readings = []
    while i < len(text):
        matched = False
        # Try words of length 4, 3, 2
        for l in range(min(4, len(text) - i), 1, -1):
            chunk = text[i:i+l]
            if chunk in word_to_reading:
                r_str, _ = word_to_reading[chunk]
                sub_readings = r_str.split("-")
                if len(sub_readings) == l:
                    readings.extend(sub_readings)
                    i += l
                    matched = True
                    break
        if not matched:
            char = text[i]
            if char in char_to_reading:
                readings.append(char_to_reading[char][0])
                i += 1
            else:
                return None
    return readings

# 2. Curate Category 1: Homophone & Common Ambiguity Sentences (100 sentences)
print("[INFO] Curating Category 1: Homophone sentences...")
cat1_candidates = []

# Core reported cases first
core_reported = [
    "帶一把雨傘",
    "下雨天要穿雨衣",
    "救救我",
    "借我看一下",
    "借我筆記看一下",
    "出門記得帶一把雨傘",
    "外面下大雨要穿雨衣",
    "下雨天出門要穿雨衣",
    "等一下借我看一下",
    "救救我好不好",
]

for s in core_reported:
    r = sentence_to_readings(s)
    if r:
        cat1_candidates.append(s)

if os.path.exists(BENCHMARK_100):
    with open(BENCHMARK_100, "r", encoding="utf-8") as f:
        b100 = json.load(f)
    for item in b100:
        target = item.get("target", "").strip()
        # Clean clauses
        clauses = re.split(r"[，。！？；、\s]+", target)
        for clause in clauses:
            clause = clause.strip()
            if 4 <= len(clause) <= 20 and re.fullmatch(r"[\u4e00-\u9fff]+", clause):
                r = sentence_to_readings(clause)
                if r and clause not in cat1_candidates:
                    cat1_candidates.append(clause)
                if len(cat1_candidates) >= 100:
                    break
        if len(cat1_candidates) >= 100:
            break

print(f"[INFO] Category 1 collected: {len(cat1_candidates)} sentences.")

# 3. Curate Category 2: Everyday Colloquial Sentences (200 sentences)
print("[INFO] Curating Category 2: Colloquial sentences...")
colloquial_seeds = [
    "借我看一下", "幫我看一下", "等一下再走", "今天天氣真好", "我們去散步吧",
    "你在幹嘛呢", "怎麼還沒回家", "這件事交給我處理", "沒問題包在我身上", "明天一起吃午餐",
    "大家辛苦了", "祝你生日快樂", "週末有空出去玩嗎", "我想喝一杯咖啡", "下午要不要喝飲料",
    "這家餐廳很好吃", "下班後一起去運動", "可以幫我拿一下外套嗎", "我們等一下在門口集合", "你現在在哪裡",
    "好不好我們就這樣決定", "我想買新的手機", "電影幾點開始播放", "捷運站就在前面不遠處", "今天晚上吃火鍋",
    "出門記得關燈和關門", "路上小心開車注意安全", "早點休息不要熬夜", "這個問題有點複雜", "請稍等我一下馬上好",
    "借我用一下剪刀", "這本書借我帶回家看", "下雨天記得隨身帶雨傘", "天氣轉涼出門多穿一件衣服", "我昨天晚上睡得很好",
    "你聽我把話說完", "不要騙我實話實說", "幫我拍一張照片好嗎", "他走得太快我跟不上", "外面風好大快進來",
    "等一下在咖啡廳碰面", "我們明天早上九點出發", "這份資料幫我印兩份", "今天的工作終於完成了", "我肚子好餓想吃宵夜",
    "請問這附近有便利商店嗎", "公車大概還要等多久", "這件衣服穿起來很適合你", "週末我們去看展覽吧", "這件事大家都很清楚",
    "可以幫我看一下這行程式碼嗎", "我剛剛寄了一封信給你", "收到請回覆一下謝謝", "這週末我們去爬山好不好", "下班後記得去超市買牛奶",
    "今天路上車子很多有點塞車", "現在幾點了我們是不是該出發了", "借我筆記參考一下好嗎", "你最近工作過得怎麼樣", "放假大家想去哪裡放鬆",
    "這道菜的味道真不錯", "幫我開一下客廳的電燈", "外面開始下起毛毛雨了", "天氣預報說明天會降溫", "下週一早上要開例行會議",
    "這個週末天氣好像很不錯", "我們買一些水果回家吃吧", "你看這張風景照片很漂亮", "記得帶鑰匙千萬別忘了", "我們待會兒電話聯絡",
    "幫我看一下這個字怎麼唸", "這杯珍珠奶茶不會太甜剛剛好", "你有看到我的眼鏡在哪裡嗎", "放在桌上的水記得喝掉", "大家一起加油把專案做好",
    "這款輸入法打字非常順暢", "希望大家都能用得很開心", "寫程式最重要的是邏輯清楚", "按鍵反應速度要越快越好", "組字候選字要精準不跳字",
    "借我看一下這份合約內容", "幫我拿一本記事本過來", "我們等一下在捷運出口集合", "今天晚上的聚餐不要遲到", "這家咖啡店的環境很安靜",
    "可以借我一支筆寫字嗎", "下雨天記得要穿防水的鞋子", "明天放假可以好好睡個飽", "出發前再檢查一次行李", "有任何問題隨時跟我說",
    "幫我想想看有什麼好方法", "這件事你覺得怎麼樣比較好", "我們一步一步慢慢解決問題", "今天學到了很多實用的技巧", "謝謝你的熱心幫忙與協助"
]

cat2_candidates = []
for s in colloquial_seeds:
    r = sentence_to_readings(s)
    if r and s not in cat1_candidates and s not in cat2_candidates:
        cat2_candidates.append(s)

# Fill rest of Category 2 from clean conversational clauses in dev.jsonl
if os.path.exists(DEV_JSONL):
    with open(DEV_JSONL, "r", encoding="utf-8") as f:
        for line in f:
            item = json.loads(line)
            target = item.get("target", "").strip()
            clauses = re.split(r"[，。！？；、\s]+", target)
            for clause in clauses:
                clause = clause.strip()
                if 5 <= len(clause) <= 16 and re.fullmatch(r"[\u4e00-\u9fff]+", clause):
                    # Check if conversational tone (contains colloquial keywords)
                    if any(kw in clause for kw in ["我", "你", "他", "我們", "大家", "好", "看", "想", "去", "吃", "買", "做", "在", "這", "那", "沒", "有", "要"]):
                        r = sentence_to_readings(clause)
                        if r and clause not in cat1_candidates and clause not in cat2_candidates:
                            cat2_candidates.append(clause)
                        if len(cat2_candidates) >= 200:
                            break
            if len(cat2_candidates) >= 200:
                break

print(f"[INFO] Category 2 collected: {len(cat2_candidates)} sentences.")

# 4. Curate Category 3: Public / Official / Administrative Sentences (200 sentences)
print("[INFO] Curating Category 3: Official sentences...")
cat3_candidates = []
if os.path.exists(DEV_JSONL):
    with open(DEV_JSONL, "r", encoding="utf-8") as f:
        for line in f:
            item = json.loads(line)
            target = item.get("target", "").strip()
            clauses = re.split(r"[，。！？；、\s]+", target)
            for clause in clauses:
                clause = clause.strip()
                if 6 <= len(clause) <= 22 and re.fullmatch(r"[\u4e00-\u9fff]+", clause):
                    # Check if official / administrative keywords
                    if any(kw in clause for kw in ["法", "條", "會", "局", "處", "府", "政", "經", "行", "定", "辦", "公", "理", "業", "計", "規", "施", "機", "關", "標", "準"]):
                        r = sentence_to_readings(clause)
                        if r and clause not in cat1_candidates and clause not in cat2_candidates and clause not in cat3_candidates:
                            cat3_candidates.append(clause)
                        if len(cat3_candidates) >= 200:
                            break
            if len(cat3_candidates) >= 200:
                break

print(f"[INFO] Category 3 collected: {len(cat3_candidates)} sentences.")

# 5. Assemble and split evenly into 250 Dev / 250 Test
print("[INFO] Assembling and splitting into Dev / Test...")

dataset = []
uid = 1

# Category 1: 50 dev, 50 test
for i, text in enumerate(cat1_candidates[:100]):
    split = "dev" if i % 2 == 0 else "test"
    dataset.append({
        "id": uid,
        "split": split,
        "category": "homophone_ambiguity",
        "target": text,
        "readings": sentence_to_readings(text)
    })
    uid += 1

# Category 2: 100 dev, 100 test
for i, text in enumerate(cat2_candidates[:200]):
    split = "dev" if i % 2 == 0 else "test"
    dataset.append({
        "id": uid,
        "split": split,
        "category": "colloquial",
        "target": text,
        "readings": sentence_to_readings(text)
    })
    uid += 1

# Category 3: 100 dev, 100 test
for i, text in enumerate(cat3_candidates[:200]):
    split = "dev" if i % 2 == 0 else "test"
    dataset.append({
        "id": uid,
        "split": split,
        "category": "official",
        "target": text,
        "readings": sentence_to_readings(text)
    })
    uid += 1

# Write to TestingData/eval_benchmark.jsonl
with open(OUTPUT_JSONL, "w", encoding="utf-8") as f:
    for row in dataset:
        f.write(json.dumps(row, ensure_ascii=False) + "\n")

dev_count = sum(1 for d in dataset if d["split"] == "dev")
test_count = sum(1 for d in dataset if d["split"] == "test")
print(f"[SUCCESS] Wrote {len(dataset)} items to {OUTPUT_JSONL} (Dev: {dev_count}, Test: {test_count})")
