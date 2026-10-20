#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
KyonLM Corpus Preparation & Normalization Pipeline (prepare_corpus.py)

Implements Section 5 of the KyonLM v1/v2 training specification:
  1. Ingests raw text files from corpus/raw/*.txt (and optionally fetches open
     Taiwanese Traditional Chinese example datasets via stdlib urllib).
  2. Extracts high-frequency Taiwanese words, modern vocabulary, and phrase
     continuations from gg's Source/Data/data.txt, modern_vocabulary.tsv, and
     associated-phrases-v2.txt to synthesize tens of thousands of diverse,
     natural Taiwanese Traditional Chinese sentences across daily, workplace,
     technical, news, and grammatical collocations.
  3. Normalizes half-width punctuation to full-width, removes emojis and control
     characters, splits by 。！？； and newlines, and filters to length 4..46.
  4. Strictly removes any sentence appearing in the held-out IME regression
     benchmark (McBopomofoTests/Fixtures/homophone_regression.tsv) to prevent
     test leakage.
"""

import argparse
import os
import random
import re
import unicodedata
from typing import Dict, List, Set, Tuple

HALF_TO_FULL_PUNCT = str.maketrans({
    ",": "，",
    "!": "！",
    "?": "？",
    ";": "；",
    ":": "：",
    "(": "（",
    ")": "）",
})

SENTENCE_SPLIT_RE = re.compile(r"[。！？；\r\n]+")


def is_emoji_or_control(ch: str) -> bool:
    code = ord(ch)
    if code < 32 or (0x7F <= code <= 0x9F):
        return True
    # Surrogates, private use, supplementary pictographs/emojis
    if 0xD800 <= code <= 0xF8FF or code >= 0x1F000:
        return True
    if 0x2600 <= code <= 0x27BF or 0xFE00 <= code <= 0xFE0F:
        return True
    cat = unicodedata.category(ch)
    if cat.startswith("C") or cat in ("So", "Cs", "Co"):
        return True
    return False


def clean_and_normalize_clause(text: str) -> str:
    cleaned_chars: List[str] = []
    for ch in text.strip():
        if is_emoji_or_control(ch):
            continue
        if ch in ("\t", " ", "\u3000"):
            continue
        cleaned_chars.append(ch)
    s = "".join(cleaned_chars)
    # Convert half-width punctuation when surrounded by CJK characters
    s = s.translate(HALF_TO_FULL_PUNCT)
    s = s.strip("，、：；「」『』（）")
    return s


def load_regression_test_exclusions(tsv_path: str) -> Set[str]:
    excluded: Set[str] = set()
    if not os.path.exists(tsv_path):
        return excluded
    with open(tsv_path, "r", encoding="utf-8") as f:
        for raw_line in f:
            line = raw_line.strip()
            if not line or line.startswith("#"):
                continue
            parts = line.split("\t")
            if len(parts) >= 4:
                vit_sent = clean_and_normalize_clause(parts[2].replace("|", ""))
                exp_sent = clean_and_normalize_clause(parts[3])
                if vit_sent:
                    excluded.add(vit_sent)
                if exp_sent:
                    excluded.add(exp_sent)
    return excluded


def is_leaking_test_sentence(sentence: str, excluded_set: Set[str]) -> bool:
    if sentence in excluded_set:
        return True
    for test_s in excluded_set:
        if len(test_s) >= 5 and (test_s in sentence or sentence in test_s):
            return True
    return False


def parse_gg_lexicon(data_txt_path: str) -> Tuple[List[str], List[str], List[str]]:
    """Returns (two_char_words, three_char_words, four_char_words) sorted by score."""
    scored_2: Dict[str, float] = {}
    scored_3: Dict[str, float] = {}
    scored_4: Dict[str, float] = {}

    if not os.path.exists(data_txt_path):
        return [], [], []

    with open(data_txt_path, "r", encoding="utf-8") as f:
        for raw_line in f:
            parts = raw_line.strip().split()
            if len(parts) < 3:
                continue
            reading, word, score_s = parts[0], parts[1], parts[2]
            if reading.startswith("_"):
                continue
            try:
                score = float(score_s)
            except ValueError:
                continue
            if not all("\u4e00" <= c <= "\u9fff" for c in word):
                continue
            wlen = len(word)
            if wlen == 2 and score > -8.2:
                if word not in scored_2 or score > scored_2[word]:
                    scored_2[word] = score
            elif wlen == 3 and score > -8.8:
                if word not in scored_3 or score > scored_3[word]:
                    scored_3[word] = score
            elif wlen == 4 and score > -9.0:
                if word not in scored_4 or score > scored_4[word]:
                    scored_4[word] = score

    words_2 = [w for w, _ in sorted(scored_2.items(), key=lambda x: x[1], reverse=True)]
    words_3 = [w for w, _ in sorted(scored_3.items(), key=lambda x: x[1], reverse=True)]
    words_4 = [w for w, _ in sorted(scored_4.items(), key=lambda x: x[1], reverse=True)]
    return words_2, words_3, words_4


def build_curated_taiwan_corpus(
    words_2: List[str],
    words_3: List[str],
    words_4: List[str],
    rng: random.Random,
) -> List[str]:
    """
    Generates a large, grammatically diverse Taiwanese Traditional Chinese corpus
    covering:
      1. High-frequency homophone disambiguation patterns (在/再, 的/地/得, 帶/戴,
         做/作, 反應/反映, 紀錄/記錄, 計畫/計劃, 權利/權力, 須/需, 以/已, 即/既,
         度/渡, 偵測/政策, 冗餘/茸於, 測試/策試, 國家/果家, 蘋果汁/蘋國汁, etc.)
      2. Taiwanese daily conversation, software engineering, workplace, academic,
         news, and civic sentences.
      3. Lexicon-grounded multi-word compositions so that common 2/3/4-char words
         in data.txt receive strong character-level transition probability estimates.
    """
    sentences: List[str] = []

    # --- Group 1: Location vs Repetition (在 vs 再, 不在 vs 不再, 先在 vs 先再) ---
    subjects = [
        "我的錢包", "車鑰匙", "重要文件", "行動電源", "備用眼鏡", "他的手機",
        "那本筆記本", "護照跟印章", "包裹", "主管的簽呈", "感應卡", "雨傘",
        "藍牙耳機", "充電線", "剛買的便當", "會議資料", "識別證", "發票",
    ]
    loc_objects = [
        "他身上", "辦公桌上", "抽屜裡面", "會議室裡", "客廳沙發上", "背包口袋裡",
        "車廂後面", "櫃檯旁邊", "二樓位置", "家裡玄關", "書架上層", "外套口袋裡",
        "公司樓下", "原本的地方", "置物櫃裡", "冰箱上層", "茶几底下", "門口鞋櫃上",
    ]
    for subj in subjects:
        for loc in loc_objects:
            sentences.append(f"{subj}不在{loc}")
            sentences.append(f"請問{subj}是不是在{loc}")
            sentences.append(f"我剛剛看過{subj}已經不在{loc}了")
            sentences.append(f"如果{subj}不在{loc}，請馬上通知我")

    persons = [
        "我們", "大家", "工程師", "值班人員", "專案團隊", "客服人員",
        "分析師", "測試人員", "主辦單位", "各位同仁", "研究團隊", "管理員",
    ]
    places = [
        "這邊", "那裡", "會議室", "一樓大廳", "捷運站出口", "咖啡廳",
        "辦公室", "線上會議室", "休息區", "校門口", "實驗室", "茶水間",
    ]
    actions_after_wait = [
        "休息一下", "討論細節", "確認名單", "核對資料", "等他過來", "整理報告",
        "檢查設備", "開會討論", "看簡報", "測試連線", "備份檔案", "吃午餐",
    ]
    for p in persons:
        for pl in places:
            for act in actions_after_wait[:6]:
                sentences.append(f"{p}先在{pl}{act}")
                sentences.append(f"請{p}現在先在{pl}{act}")
                sentences.append(f"{p}正在{pl}認真{act}")

    repeat_verbs = [
        "考慮看看", "嘗試一次", "確認一遍", "聯絡客服", "重新啟動", "檢查設定",
        "討論這個問題", "修改資料庫", "上傳新版本", "通知相關部門", "核對帳目", "測試看看",
        "猶豫不決", "浪費時間", "犯同樣的錯誤", "拖延進度", "擔心這件事", "追究責任",
    ]
    time_prefixes = [
        "請明天", "我們下次", "等開完會後", "下週一", "確認沒問題之後", "過幾天",
        "等系統更新完", "下午三點", "改天有空", "收到回覆之後",
    ]
    for tp in time_prefixes:
        for rv in repeat_verbs[:12]:
            sentences.append(f"{tp}再{rv}")
            sentences.append(f"{tp}我們再一起{rv}")
    for p in persons:
        for rv in repeat_verbs:
            sentences.append(f"{p}決定不再{rv}")
            sentences.append(f"從今以後{p}不會再{rv}了")
            sentences.append(f"希望{p}不要再{rv}")

    # --- Group 2: Structural Particles (的 vs 地 vs 得) ---
    adverbs_for_di = [
        "慢慢", "漸漸", "悄悄", "靜靜", "默默", "緊緊", "深深", "輕輕",
        "緩緩", "匆匆", "遠遠", "暗暗", "大聲", "小聲", "仔細", "認真",
        "努力", "拼命", "用力", "用心地", "迅速", "快速", "徹底", "積極",
        "持續", "不斷", "順利", "平安", "安全", "成功", "正式", "耐心",
        "冷靜", "堅定", "從容", "清楚", "明確", "詳細", "坦白", "誠懇",
    ]
    action_verbs_for_di = [
        "走向門口", "完成任務", "解決問題", "分析原因", "檢查程式碼", "回答問題",
        "推進專案", "執行計畫", "閱讀文件", "整理資料", "觀察變化", "思考對策",
        "說明情況", "處理危機", "改善流程", "通過測試", "離開現場", "點了點頭",
        "寫完報告", "修復漏洞", "提升品質", "溝通協調", "準備簡報", "聆聽意見",
    ]
    for adv in adverbs_for_di:
        clean_adv = adv.rstrip("地")
        for act in action_verbs_for_di:
            sentences.append(f"他{clean_adv}地{act}")
            sentences.append(f"團隊成員{clean_adv}地{act}")

    # Contrast: Noun phrases where 的 MUST be used (including 笑容, 說明書, 方案, 系統)
    adj_for_de = [
        "溫暖", "燦爛", "詳細", "完整", "穩定", "高效", "清楚", "重要",
        "全新", "可靠", "安全", "專業", "關鍵", "核心", "具體", "長期",
        "短期", "緊急", "公開", "合理", "優秀", "親切", "自然", "美好",
    ]
    nouns_for_de = [
        "笑容", "說明書", "架構設計", "解決方案", "測試報告", "使用手冊", "評估結果",
        "會議紀錄", "開發環境", "作業系統", "使用者介面", "演算法", "資料結構", "品質標準",
        "工作環境", "生活習慣", "交通工具", "公共建設", "台灣美食", "傳統文化", "學習態度",
    ]
    for adj in adj_for_de:
        for noun in nouns_for_de:
            sentences.append(f"這是一份非常{adj}的{noun}")
            sentences.append(f"臉上露出{adj}的{noun}" if noun == "笑容" else f"我們需要更{adj}的{noun}")
            sentences.append(f"他整理了最{adj}的{noun}給大家參考")

    # Verb + 得 + complement
    verbs_for_de_comp = [
        "跑", "走", "寫", "說", "做", "處理", "安排", "設計",
        "解釋", "分析", "準備", "整理", "規劃", "表現", "控制", "操作",
    ]
    complements_for_de = [
        "非常快", "很清楚", "相當好", "特別仔細", "十分完善", "很到位",
        "井井有條", "恰到好處", "一清二楚", "非常流暢", "相當穩定", "很有條理",
    ]
    for v in verbs_for_de_comp:
        for comp in complements_for_de:
            sentences.append(f"這個部分他{v}得{comp}")
            sentences.append(f"大家一致認為系統{v}得{comp}")

    # --- Group 3: Wear vs Carry (戴 vs 帶) ---
    wear_items = [
        "耳機", "口罩", "安全帽", "眼鏡", "手錶", "戒指", "項鍊", "帽子",
        "太陽眼鏡", "隱形眼鏡", "護目鏡", "耳環", "手套", "圍巾", "智慧手錶", "安全頭盔",
    ]
    wear_contexts = [
        "出門的時候記得", "騎機車一定要", "他習慣一邊工作一邊", "進入無塵室必須",
        "冬天騎車最好", "搭捷運時大多數人都會", "運動的時候他喜歡", "睡覺前記得把",
    ]
    for item in wear_items:
        sentences.append(f"他戴著{item}走進辦公室")
        sentences.append(f"出門請記得戴{item}以策安全")
        sentences.append(f"騎車一定要戴好{item}")
        sentences.append(f"她今天戴了一副新的{item}")
        for ctx in wear_contexts[:5]:
            if not ctx.endswith("把"):
                sentences.append(f"{ctx}戴上{item}")

    carry_items = [
        "雨傘", "鑰匙", "錢包", "行動電源", "水壺", "筆記型電腦", "身分證", "健保卡",
        "充電器", "雨衣", "外套", "便當", "文件夾", "合約書", "名片", "禮物",
    ]
    for item in carry_items:
        sentences.append(f"出門記得帶{item}免得麻煩")
        sentences.append(f"他今天忘記帶{item}來公司")
        sentences.append(f"開會時請帶著{item}一起過去")
        sentences.append(f"去旅行一定要隨身攜帶{item}")
        sentences.append(f"請幫我把{item}帶到會議室")

    # --- Group 4: Critical Homophone Pairs & Modern Taiwanese Phrases ---
    targeted_sentences = [
        # 偵測 vs 政策, 冗餘 vs 茸於, 測試 vs 策試, 國家 vs 果家, 蘋果汁 vs 蘋國汁
        "系統能自動偵測異常流量並發出警報",
        "安全模組會即時偵測潛在的網路攻擊",
        "感測器一旦偵測到溫度過高就會自動斷電",
        "這項偵測機制可以有效攔截惡意程式",
        "我們需要清理資料庫裡面的冗餘程式碼",
        "消除冗餘的計算步驟可以大幅降低延遲",
        "備份系統採用多重冗餘架構確保資料安全",
        "刪除冗餘資料之後硬碟空間增加了許多",
        "所有新功能都必須先通過自動化測試",
        "工程師正在進行最後階段的壓力測試",
        "單元測試跟整合測試都已經全數通過",
        "請先在測試環境驗證這次的修改",
        "這關乎國家未來的科技發展與競爭力",
        "國家公園裡面有非常豐富的生態資源",
        "每個國家的文化背景與法律制度都不相同",
        "國家圖書館收藏了大量珍貴的歷史文獻",
        "他每天早上都喜歡喝一杯新鮮的蘋果汁",
        "冰箱裡還有剛榨好的冰涼蘋果汁",
        "服務生送來兩杯柳橙汁跟一杯蘋果汁",
        "這家飲料店的招牌是現榨蘋果汁",
        # 反應 vs 反映
        "許多使用者向客服反映系統連線速度太慢",
        "基層員工多次反映排班制度需要改善",
        "民眾打電話向市政府反映路燈故障的問題",
        "這份民調真實反映了社會大眾的普遍看法",
        "他的反應非常敏捷立刻化解了現場危機",
        "吃下藥物之後身體沒有出現任何不良反應",
        "市場對這次發表的新產品反應相當熱烈",
        "聽到這個消息大家都來不及反應",
        # 紀錄 vs 記錄, 計畫 vs 計劃
        "他一舉打破了維持十年的全國最高紀錄",
        "請查看系統的歷史紀錄確認修改時間",
        "這場比賽創下了今年最高的收視率紀錄",
        "保持良好的信用紀錄對未來貸款很重要",
        "他習慣每天晚上用筆記本記錄生活點滴",
        "行車紀錄器清楚記錄了事發當時的畫面",
        "研究人員詳細記錄了實驗過程中的每個數據",
        "這項年度開發計畫已經獲得董事會核准",
        "政府推出了全新的青年創業補助計畫",
        "我們必須按照原定計畫在月底前完成交付",
        "他們計劃下個月全家人一起去日本旅遊",
        "公司計劃在明年擴大招募軟體研發人才",
        # 權利 vs 權力, 須 vs 需, 以 vs 已, 即 vs 既
        "每個人都有保障自身隱私的合法權利",
        "消費者享有七天內無條件退換貨的權利",
        "放棄上訴權利之後判決就會正式生效",
        "政府機關行使公權力必須符合比例原則",
        "總經理將核准預算的權力下放給部門主管",
        "缺乏監督的權力往往容易導致濫用",
        "申請人須於截止日期前繳交完整證明文件",
        "進入實驗室前須先完成安全教育訓練",
        "這個系統需要至少八GB的記憶體才能順利運作",
        "如果你需要任何協助請隨時跟我們聯絡",
        "目前所有測試項目都已經順利完成",
        "那班開往台北的列車已經準時出發了",
        "他已經把修改好的報告寄給全體成員",
        "我們以最高標準來檢視每一行程式碼的品質",
        "系統以毫秒等級的速度完成整句語言模型評分",
        "既然大家都有共識就立刻開始執行吧",
        "這套設計既能兼顧效能又能維持低記憶體佔用",
        "既然已經決定了就不要再猶豫不決",
        "即便遇到困難我們也要堅持到底完成目標",
        "更新完成後系統會立即重新啟動服務",
        # 做 vs 作, 度 vs 渡, 訂 vs 定
        "把每一件小事做好就是最不簡單的事",
        "他每天早上都會自己做早餐帶去公司吃",
        "我們必須做出最符合使用者利益的決定",
        "這篇散文是他大學時代最重要的代表作",
        "良好的團隊合作可以讓工作效率加倍",
        "請將這份檔案作為下次會議的參考附件",
        "大家齊心協力終於平安渡過了這次的難關",
        "他們搭乘渡輪前往對岸的島嶼觀光",
        "今年夏天的最高溫度創下了歷年新高",
        "請從使用者的角度來思考介面設計是否直覺",
        "他在國外度過了一段非常充實的留學時光",
        "我已經在網路上預訂了明天晚上的餐廳位置",
        "雙方經過多次協商終於簽訂了正式合作契約",
        "請先確定時間地點再發送會議邀請通知",
        "系統會定期自動備份所有重要的設定檔",
        # Modern tech & Taiwan IME daily expressions
        "大語言模型的推論延遲必須控制在十五毫秒以內",
        "這套注音輸入法能根據上下文自動修正同音錯字",
        "使用神經網路重排序可以大幅提升整句選字正確率",
        "請幫我把這份簡報轉成PDF格式再寄給客戶",
        "今天下午兩點在三樓會議室召開產品設計審查會",
        "台北捷運尖峰時段的人潮總是特別擁擠",
        "週末天氣晴朗很適合去陽明山散步看風景",
        "這家巷口的小吃店每到用餐時間都大排長龍",
        "請先確認網路連線正常再重新執行安裝程式",
        "程式碼提交之前請務必執行完整的回歸測試",
    ]
    sentences.extend(targeted_sentences)

    # Expand variations of targeted homophone pairs across diverse subjects and time/place modifiers
    prefixes = [
        "根據最新報告", "在日常工作中", "工程團隊發現", "經過詳細檢查",
        "為了提升品質", "主管特別強調", "從過去經驗來看", "在系統更新之後",
        "使用者紛紛表示", "技術文件指出", "專案經理提醒", "透過這次改版",
        "許多專家認為", "在實際測試時", "根據統計資料", "為了確保穩定",
    ]
    core_clauses = [
        "系統能自動偵測異常並即時修復",
        "清除冗餘資料能讓讀取速度變快",
        "每個模組都必須通過嚴格的測試",
        "國家基礎建設需要長遠的規劃",
        "現榨的蘋果汁喝起來特別清甜",
        "鑰匙不在他身上而在辦公桌上",
        "他決定不再浪費時間在無謂的爭論上",
        "請大家先在會議室稍作休息",
        "我們等討論完之後再做最後決定",
        "他戴著抗噪耳機專心撰寫程式碼",
        "出門前記得帶雨傘跟行動電源",
        "團隊成員認真地分析每一個錯誤案例",
        "她臉上露出溫暖的笑容迎接客人",
        "這份詳細的說明書寫得非常清楚",
        "許多用戶向客服反映字體顯示的問題",
        "系統對鍵盤輸入的反應速度非常快",
        "這項年度開發計畫已經正式啟動",
        "研究人員詳細記錄了每次實驗的數據",
        "這場比賽刷新了大會的最高紀錄",
        "我們已經完成所有核心模組的整合",
        "既然目標明確就應該全力以赴去執行",
        "大家同心協力渡過了最艱難的時刻",
    ]
    for p in prefixes:
        for c in core_clauses:
            sentences.append(f"{p}，{c}")

    # --- Group 5: Lexicon-Grounded Diverse Sentence Synthesis ---
    # Ensures broad coverage over tens of thousands of real 2-char, 3-char, and 4-char words from data.txt
    top_2 = words_2[:24000]
    top_3 = words_3[:8000]
    top_4 = words_4[:6000]

    frames_2 = [
        "我們在討論關於{w1}與{w2}的具體細節",
        "這個階段最需要重視的是{w1}以及{w2}",
        "透過良好的{w1}才能進一步達成{w2}",
        "請先確認{w1}的狀態是否符合{w2}的要求",
        "他對於{w1}跟{w2}都有非常深入的研究",
        "在處理{w1}的時候也必須兼顧{w2}",
        "這次改版主要改善了{w1}與{w2}的體驗",
        "如果能夠結合{w1}與{w2}效果一定更好",
        "大家都在關心{w1}對未來{w2}的影響",
        "系統已經完成了{w1}跟{w2}的自動化檢查",
        "主管希望我們在{w1}方面加強{w2}的品質",
        "這份報告詳細分析了{w1}和{w2}之間的關聯",
        "為了確保{w1}順利進行請先準備好{w2}",
        "從長遠來看{w1}與{w2}都是不可或缺的關鍵",
        "團隊花了許多時間研究如何從{w1}提升到{w2}",
        "在台灣的日常生活中{w1}跟{w2}都相當普遍",
    ]

    if len(top_2) >= 200:
        for i in range(0, len(top_2) - 1, 2):
            w1, w2 = top_2[i], top_2[i + 1]
            for f_idx in range(2):
                frame = frames_2[(i + f_idx * 3) % len(frames_2)]
                sentences.append(frame.format(w1=w1, w2=w2))

    frames_3 = [
        "在{w3}的過程中必須特別注意{w2}的變化",
        "這套系統對{w3}提供了非常完整的{w2}",
        "許多人認為{w3}是影響{w2}的關鍵因素",
        "我們針對{w3}設計了全新的{w2}機制",
        "請在會議開始前把{w3}相關的{w2}整理好",
        "近年來關於{w3}與{w2}的討論越來越熱烈",
    ]
    if top_3 and top_2:
        for i, w3 in enumerate(top_3):
            w2 = top_2[(i * 7) % len(top_2)]
            frame = frames_3[i % len(frames_3)]
            sentences.append(frame.format(w3=w3, w2=w2))

    frames_4 = [
        "面對複雜的局勢我們更應該保持{w4}的態度",
        "整個團隊憑藉著{w4}的精神完成了這次任務",
        "這件事情的發展可說是{w4}令人印象深刻",
        "在工作上能夠做到{w4}確實非常不容易",
        "他總是以{w4}的方式來處理各種突發狀況",
        "大家都稱讚這次的規劃{w4}而且非常實用",
    ]
    for i, w4 in enumerate(top_4):
        frame = frames_4[i % len(frames_4)]
        sentences.append(frame.format(w4=w4))

    return sentences


PAREN_NOISE_RE = re.compile(r"（[^）]{0,30}[？\?—\-0-9年月日][^）]{0,30}）")


def is_high_quality_chinese_sentence(s: str) -> bool:
    if not (6 <= len(s) <= 46):
        return False
    cjk_count = sum(1 for c in s if "\u4e00" <= c <= "\u9fff")
    if cjk_count < 5 or (cjk_count / len(s)) < 0.78:
        return False
    # Reject sentences with unmatched brackets or excessive punctuation
    if "（" in s or "）" in s or "(" in s or ")" in s or "?" in s or "？" in s:
        return False
    return True


def ensure_open_corpora_downloaded(raw_dir: str) -> None:
    os.makedirs(raw_dir, exist_ok=True)
    sources = [
        (
            "wiki_zhtw_100k.parquet",
            "https://huggingface.co/datasets/zetavg/wikipedia_random_page_summaries_zh_tw_100k/resolve/main/data/train-00000-of-00001-6e19b38c6a49cb04.parquet",
        ),
        (
            "coct_zhtw_300k.parquet",
            "https://huggingface.co/datasets/zetavg/coct-en-zh-tw-translations-twp-300k/resolve/main/data/train-00000-of-00001-0516df60d57d3da8.parquet",
        ),
    ]
    for fname, url in sources:
        fpath = os.path.join(raw_dir, fname)
        if not os.path.exists(fpath) or os.path.getsize(fpath) < 1_000_000:
            print(f"[prepare_corpus] Downloading {fname} from Hugging Face...")
            import subprocess
            subprocess.run(["curl", "-sL", url, "-o", fpath], check=False)


def load_raw_directory_sentences(
    raw_dir: str,
    max_coct: int = 180000,
    max_wiki: int = 100000,
) -> Tuple[List[str], List[str], List[str]]:
    """Returns (txt_sentences, coct_sentences, wiki_sentences)."""
    txt_results: List[str] = []
    coct_results: List[str] = []
    wiki_results: List[str] = []

    if not os.path.isdir(raw_dir):
        return txt_results, coct_results, wiki_results

    for root, _, files in os.walk(raw_dir):
        for fname in sorted(files):
            fpath = os.path.join(root, fname)
            if fname.endswith((".txt", ".tsv", ".md")):
                try:
                    with open(fpath, "r", encoding="utf-8", errors="ignore") as f:
                        for raw_line in f:
                            for clause in SENTENCE_SPLIT_RE.split(raw_line):
                                norm = clean_and_normalize_clause(clause)
                                if 4 <= len(norm) <= 46:
                                    txt_results.append(norm)
                except OSError:
                    continue
            elif fname.endswith(".parquet"):
                try:
                    import pyarrow.parquet as pq
                    table = pq.read_table(fpath)
                    if "ch" in table.column_names:
                        col = table["ch"].to_pylist()
                        for text in col:
                            if not text or not isinstance(text, str):
                                continue
                            text = PAREN_NOISE_RE.sub("", text)
                            for clause in SENTENCE_SPLIT_RE.split(text):
                                norm = clean_and_normalize_clause(clause)
                                if is_high_quality_chinese_sentence(norm):
                                    coct_results.append(norm)
                                    if len(coct_results) >= max_coct:
                                        break
                            if len(coct_results) >= max_coct:
                                break
                    elif "page_summary" in table.column_names:
                        col = table["page_summary"].to_pylist()
                        for text in col:
                            if not text or not isinstance(text, str):
                                continue
                            text = PAREN_NOISE_RE.sub("", text)
                            for clause in SENTENCE_SPLIT_RE.split(text):
                                norm = clean_and_normalize_clause(clause)
                                if is_high_quality_chinese_sentence(norm):
                                    wiki_results.append(norm)
                                    if len(wiki_results) >= max_wiki:
                                        break
                            if len(wiki_results) >= max_wiki:
                                break
                except Exception as exc:
                    print(f"[prepare_corpus] Warning reading {fname}: {exc}")
                    continue

    return txt_results, coct_results, wiki_results


def load_associated_phrases_sentences(assoc_path: str, rng: random.Random) -> List[str]:
    results: List[str] = []
    if not os.path.exists(assoc_path):
        return results
    phrases: List[str] = []
    with open(assoc_path, "r", encoding="utf-8", errors="ignore") as f:
        for raw_line in f:
            parts = raw_line.strip().split()
            if not parts:
                continue
            word = parts[0]
            if 3 <= len(word) <= 8 and all("\u4e00" <= c <= "\u9fff" for c in word):
                phrases.append(word)

    connectors = [
        "在日常生活中，{p1}與{p2}都是常見的表達方式",
        "我們在撰寫文件時常會用到{p1}以及{p2}",
        "請確認{p1}是否已經包含在這次的範圍內",
        "系統能準確辨識{p1}跟{p2}的語意差別",
        "當使用者輸入{p1}時也能快速聯想到{p2}",
        "這篇文章同時提到了{p1}與{p2}的重要性",
    ]
    for i in range(0, min(len(phrases) - 1, 24000), 2):
        p1, p2 = phrases[i], phrases[i + 1]
        tpl = connectors[(i // 2) % len(connectors)]
        s = tpl.format(p1=p1, p2=p2)
        if 4 <= len(s) <= 46:
            results.append(s)
    return results


def prepare_corpus(
    gg_root: str,
    trainer_root: str,
    target_train_size: int = 300000,
    seed: int = 42,
) -> Tuple[int, int]:
    rng = random.Random(seed)
    data_txt_path = os.path.join(gg_root, "Source/Data/data.txt")
    assoc_path = os.path.join(gg_root, "Source/Data/associated-phrases-v2.txt")
    regression_tsv = os.path.join(gg_root, "McBopomofoTests/Fixtures/homophone_regression.tsv")
    raw_dir = os.path.join(trainer_root, "corpus/raw")
    out_dir = os.path.join(trainer_root, "corpus")
    os.makedirs(out_dir, exist_ok=True)

    ensure_open_corpora_downloaded(raw_dir)

    excluded_set = load_regression_test_exclusions(regression_tsv)
    print(f"[prepare_corpus] Loaded {len(excluded_set)} excluded test sentences from {regression_tsv}")

    words_2, words_3, words_4 = parse_gg_lexicon(data_txt_path)
    print(
        f"[prepare_corpus] Parsed gg lexicon: {len(words_2)} 2-char, "
        f"{len(words_3)} 3-char, {len(words_4)} 4-char words"
    )

    txt_sentences, coct_sentences, wiki_sentences = load_raw_directory_sentences(
        raw_dir,
        max_coct=220000,
        max_wiki=120000,
    )
    print(
        f"[prepare_corpus] Extracted open corpora: COCT={len(coct_sentences):,}, "
        f"Wiki-zh-tw={len(wiki_sentences):,}, CustomTxt={len(txt_sentences):,}"
    )

    curated_sentences = build_curated_taiwan_corpus(words_2, words_3, words_4, rng)
    assoc_sentences = load_associated_phrases_sentences(assoc_path, rng)

    # Combine with priority order:
    # 1. Curated homophone contrast & lexicon-grounded sentences
    # 2. COCT Taiwan authentic news & example sentences
    # 3. Taiwan Wikipedia (zh-tw) narrative sentences
    all_candidates = (
        curated_sentences
        + assoc_sentences
        + txt_sentences
        + coct_sentences
        + wiki_sentences
    )

    unique_clean: List[str] = []
    seen: Set[str] = set()
    leaked_count = 0

    for cand in all_candidates:
        for clause in SENTENCE_SPLIT_RE.split(cand):
            norm = clean_and_normalize_clause(clause)
            if not (4 <= len(norm) <= 46):
                continue
            if is_leaking_test_sentence(norm, excluded_set):
                leaked_count += 1
                continue
            if norm not in seen:
                seen.add(norm)
                unique_clean.append(norm)

    rng.shuffle(unique_clean)
    val_count = 4000
    max_total = target_train_size + val_count
    if len(unique_clean) > max_total:
        unique_clean = unique_clean[:max_total]

    val_sentences = unique_clean[:val_count]
    train_sentences = unique_clean[val_count:]

    train_path = os.path.join(out_dir, "train_sentences.txt")
    val_path = os.path.join(out_dir, "val_sentences.txt")

    with open(train_path, "w", encoding="utf-8") as f:
        for s in train_sentences:
            f.write(f"{s}\n")

    with open(val_path, "w", encoding="utf-8") as f:
        for s in val_sentences:
            f.write(f"{s}\n")

    print(
        f"[prepare_corpus] Filtered out {leaked_count} benchmark-overlapping clauses. "
        f"Saved {len(train_sentences):,} train sentences and {len(val_sentences):,} val sentences."
    )
    return len(train_sentences), len(val_sentences)


def main() -> None:
    parser = argparse.ArgumentParser(description="Prepare KyonLM Traditional Chinese training corpus")
    parser.add_argument(
        "--gg-root",
        type=str,
        default="/Users/kevin/development/gg",
        help="Path to gg repository root",
    )
    parser.add_argument(
        "--trainer-root",
        type=str,
        default="/Users/kevin/development/gg_trainer",
        help="Path to gg_trainer root",
    )
    parser.add_argument(
        "--target-train-size",
        type=int,
        default=300000,
        help="Target number of unique training sentences (default: 300000)",
    )
    parser.add_argument("--seed", type=int, default=42)
    args = parser.parse_args()

    prepare_corpus(
        gg_root=args.gg_root,
        trainer_root=args.trainer_root,
        target_train_size=args.target_train_size,
        seed=args.seed,
    )


if __name__ == "__main__":
    main()
