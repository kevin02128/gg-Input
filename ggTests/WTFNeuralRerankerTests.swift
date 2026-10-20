// WTFNeuralRerankerTests.swift
// Copyright (c) 2026 and onwards The McBopomofo Authors.

import Testing
@testable import gg

@Suite("WTFNeuralReranker Semantic Candidate Re-Ranking Tests")
struct WTFNeuralRerankerTests {

    @Test("Test 戴 vs 帶 semantic context re-ranking")
    func testDaiWearVsCarry() {
        let reranker = WTFNeuralReranker.shared
        reranker.isEnabled = true

        // Case 1: 把口罩戴好 -> "戴" should be ranked #1
        let wearCandidates = [
            InputState.Candidate(reading: "ㄉㄞˋ", value: "帶", displayText: "帶", rawValue: "帶"),
            InputState.Candidate(reading: "ㄉㄞˋ", value: "戴", displayText: "戴", rawValue: "戴"),
        ]
        let rerankedWear = reranker.rerank(
            candidates: wearCandidates,
            composingBuffer: "把口罩好",
            cursorIndex: 3
        )
        print("DEBUG testDaiWearVsCarry: rerankedWear = \(rerankedWear.map { $0.value })")
        #expect(rerankedWear.first?.value == "戴")

        // Case 2: 伴手禮帶走 -> "帶" should be ranked #1
        let carryCandidates = [
            InputState.Candidate(reading: "ㄉㄞˋ", value: "戴", displayText: "戴", rawValue: "戴"),
            InputState.Candidate(reading: "ㄉㄞˋ", value: "帶", displayText: "帶", rawValue: "帶"),
        ]
        let rerankedCarry = reranker.rerank(
            candidates: carryCandidates,
            composingBuffer: "把伴手禮走",
            cursorIndex: 4
        )
        #expect(rerankedCarry.first?.value == "帶")
    }

    @Test("Test 反映 vs 反應 semantic context re-ranking")
    func testReflectVsReaction() {
        let reranker = WTFNeuralReranker.shared
        reranker.isEnabled = true

        // Case 1: 反映意見 -> "反映" should be #1
        let reflectCandidates = [
            InputState.Candidate(reading: "ㄈㄢˇ-ㄧㄥˋ", value: "反應", displayText: "反應", rawValue: "反應"),
            InputState.Candidate(reading: "ㄈㄢˇ-ㄧㄥˋ", value: "反映", displayText: "反映", rawValue: "反映"),
        ]
        let rerankedReflect = reranker.rerank(
            candidates: reflectCandidates,
            composingBuffer: "意見",
            cursorIndex: 0
        )
        #expect(rerankedReflect.first?.value == "反映")

        // Case 2: 化學反應 -> "反應" should be #1
        let reactionCandidates = [
            InputState.Candidate(reading: "ㄈㄢˇ-ㄧㄥˋ", value: "反映", displayText: "反映", rawValue: "反映"),
            InputState.Candidate(reading: "ㄈㄢˇ-ㄧㄥˋ", value: "反應", displayText: "反應", rawValue: "反應"),
        ]
        let rerankedReaction = reranker.rerank(
            candidates: reactionCandidates,
            composingBuffer: "引起化學",
            cursorIndex: 4
        )
        #expect(rerankedReaction.first?.value == "反應")
    }

    @Test("Test Pangu Chinese-English Auto-Spacing")
    func testPanguAutoSpacing() {
        let manager = WTFMixedInputManager.shared
        manager.resetCommittedContext()

        // 1. Internal mixed text spacing
        #expect(WTFMixedInputManager.formatInternalPanguSpacing("今天買了iPhone16Pro很開心") == "今天買了 iPhone16Pro 很開心")

        // 2. Consecutive commits: Chinese -> English -> Chinese
        let c1 = manager.applyPanguSpacing(to: "今天", isEnglishWord: false)
        #expect(c1 == "今天")
        let c2 = manager.applyPanguSpacing(to: "Apple", isEnglishWord: true)
        #expect(c2 == " Apple")
        let c3 = manager.applyPanguSpacing(to: "發表會", isEnglishWord: false)
        #expect(c3 == " 發表會")

        // 3. Consecutive English words via Tab completion: English -> English -> Chinese punctuation
        manager.resetCommittedContext()
        let e1 = manager.applyPanguSpacing(to: "Hello", isEnglishWord: true)
        #expect(e1 == "Hello")
        let e2 = manager.applyPanguSpacing(to: "World", isEnglishWord: true)
        #expect(e2 == " World")
        let p1 = manager.applyPanguSpacing(to: "！", isEnglishWord: false)
        #expect(p1 == "！")
    }

    @Test("Test 的 vs 得 vs 地 semantic context re-ranking")
    func testDeParticles() {
        let reranker = WTFNeuralReranker.shared
        reranker.isEnabled = true

        // Case 1: 他跑得很快 -> "得" should be #1
        let deCandidates = [
            InputState.Candidate(reading: "ㄉㄜ˙", value: "的", displayText: "的", rawValue: "的"),
            InputState.Candidate(reading: "ㄉㄜˊ", value: "得", displayText: "得", rawValue: "得"),
        ]
        let rerankedDe = reranker.rerank(
            candidates: deCandidates,
            composingBuffer: "他跑很快",
            cursorIndex: 2
        )
        #expect(rerankedDe.first?.value == "得")

        // Case 2: 美麗的花朵 -> "的" should be #1
        let diCandidates = [
            InputState.Candidate(reading: "ㄉㄜˊ", value: "得", displayText: "得", rawValue: "得"),
            InputState.Candidate(reading: "ㄉㄜ˙", value: "的", displayText: "的", rawValue: "的"),
        ]
        let rerankedNoun = reranker.rerank(
            candidates: diCandidates,
            composingBuffer: "美麗花朵",
            cursorIndex: 2
        )
        #expect(rerankedNoun.first?.value == "的")

        // Case 3: 慢慢地走開 -> "地" should be #1
        let adverbCandidates = [
            InputState.Candidate(reading: "ㄉㄜ˙", value: "的", displayText: "的", rawValue: "的"),
            InputState.Candidate(reading: "ㄉㄜ˙", value: "地", displayText: "地", rawValue: "地"),
        ]
        let rerankedAdverb = reranker.rerank(
            candidates: adverbCandidates,
            composingBuffer: "慢慢走開",
            cursorIndex: 2
        )
        #expect(rerankedAdverb.first?.value == "地")
    }

    @Test("Test 在 vs 再 semantic context re-ranking")
    func testZaiLocationsVsRepeat() {
        let reranker = WTFNeuralReranker.shared
        reranker.isEnabled = true

        // Case 1: 在家裡 -> "在" should be #1
        let atHomeCandidates = [
            InputState.Candidate(reading: "ㄗㄞˋ", value: "再", displayText: "再", rawValue: "再"),
            InputState.Candidate(reading: "ㄗㄞˋ", value: "在", displayText: "在", rawValue: "在"),
        ]
        let rerankedAtHome = reranker.rerank(
            candidates: atHomeCandidates,
            composingBuffer: "家裡讀書",
            cursorIndex: 0
        )
        #expect(rerankedAtHome.first?.value == "在")

        // Case 2: 明天再說 -> "再" should be #1
        let repeatCandidates = [
            InputState.Candidate(reading: "ㄗㄞˋ", value: "在", displayText: "在", rawValue: "在"),
            InputState.Candidate(reading: "ㄗㄞˋ", value: "再", displayText: "再", rawValue: "再"),
        ]
        let rerankedRepeat = reranker.rerank(
            candidates: repeatCandidates,
            composingBuffer: "明天說吧",
            cursorIndex: 2
        )
        #expect(rerankedRepeat.first?.value == "再")
    }

    @Test("Test 果 vs 國 vs 過 semantic context re-ranking")
    func testGuoWords() {
        let reranker = WTFNeuralReranker.shared
        reranker.isEnabled = true

        // Case 1: 蘋果汁 -> "果" should be #1
        let fruitCandidates = [
            InputState.Candidate(reading: "ㄍㄨㄛˊ", value: "國", displayText: "國", rawValue: "國"),
            InputState.Candidate(reading: "ㄍㄨㄛˋ", value: "過", displayText: "過", rawValue: "過"),
            InputState.Candidate(reading: "ㄍㄨㄛˇ", value: "果", displayText: "果", rawValue: "果"),
        ]
        let rerankedFruit = reranker.rerank(
            candidates: fruitCandidates,
            composingBuffer: "這杯蘋汁",
            cursorIndex: 3
        )
        #expect(rerankedFruit.first?.value == "果")

        // Case 2: 我們的國家 -> "國" should be #1
        let nationCandidates = [
            InputState.Candidate(reading: "ㄍㄨㄛˇ", value: "果", displayText: "果", rawValue: "果"),
            InputState.Candidate(reading: "ㄍㄨㄛˋ", value: "過", displayText: "過", rawValue: "過"),
            InputState.Candidate(reading: "ㄍㄨㄛˊ", value: "國", displayText: "國", rawValue: "國"),
        ]
        let rerankedNation = reranker.rerank(
            candidates: nationCandidates,
            composingBuffer: "我們的家",
            cursorIndex: 3
        )
        #expect(rerankedNation.first?.value == "國")
    }

    @Test("Test dynamic lattice node rescoring (零人工清單，直接從晶格候選動態重排)")
    func testDynamicNodeRescoringInLattice() {
        let reranker = WTFNeuralReranker.shared
        reranker.isEnabled = true

        // 1. 我想在看一次 -> 應動態選出「再」
        let zaiWinner = reranker.rescoreNodeCandidates(
            candidates: ["在", "再", "載"],
            currentValue: "在",
            leftContext: "我想",
            rightContext: "看一次"
        )
        #expect(zaiWinner == "再")

        // 2. 今天在學校開會 -> 處所語意，應維持「在」(回傳 nil)
        let zaiLocWinner = reranker.rescoreNodeCandidates(
            candidates: ["在", "再", "載"],
            currentValue: "在",
            leftContext: "今天",
            rightContext: "學校開會"
        )
        #expect(zaiLocWinner == nil)

        // 3. 跑的快 -> 應動態選出「得」
        let deWinner = reranker.rescoreNodeCandidates(
            candidates: ["的", "得", "地"],
            currentValue: "的",
            leftContext: "跑",
            rightContext: "快"
        )
        #expect(deWinner == "得")

        // 4. 向主管反應問題 -> 應動態選出「反映」
        let fanyingWinner = reranker.rescoreNodeCandidates(
            candidates: ["反應", "反映"],
            currentValue: "反應",
            leftContext: "向主管",
            rightContext: "問題"
        )
        #expect(fanyingWinner == "反映")

        // 5. 請帶口罩 -> 應動態選出「戴」
        let daiWinner = reranker.rescoreNodeCandidates(
            candidates: ["帶", "戴", "代"],
            currentValue: "帶",
            leftContext: "請",
            rightContext: "口罩"
        )
        #expect(daiWinner == "戴")

        // 6. 請記得戴雨傘 -> 應動態選出「帶」
        let carryWinner = reranker.rescoreNodeCandidates(
            candidates: ["戴", "帶", "代"],
            currentValue: "戴",
            leftContext: "請記得",
            rightContext: "雨傘"
        )
        #expect(carryWinner == "帶")
    }

    @Test("Test reviewDisplaySentence: 茸於 -> 冗餘 and 我在策試一次 -> 我再測試一次")
    func testReviewDisplaySentenceUserCases() {
        let reranker = WTFNeuralReranker.shared
        reranker.isEnabled = true

        // Case 1: 茸於 -> 應雙向審查動態修復為 冗餘
        let rongNode = WTFNodeInfo(
            value: "茸",
            reading: "ㄖㄨㄥˇ",
            spanningLength: 1,
            isUserLocked: false,
            candidateValues: ["茸", "冗"],
            candidateLogProbs: [-5.74, -5.60]
        )
        let yuNode = WTFNodeInfo(
            value: "於",
            reading: "ㄩˊ",
            spanningLength: 1,
            isUserLocked: false,
            candidateValues: ["於", "餘", "魚"],
            candidateLogProbs: [-2.95, -4.09, -4.08]
        )
        let reviewedRongYu = reranker.reviewDisplaySentence(viterbiNodes: [rongNode, yuNode])
        #expect(reviewedRongYu.joined() == "冗餘")

        // Case 2: 我在策試一次 -> 應審查修復為 我再測試一次
        let woNode = WTFNodeInfo(
            value: "我",
            reading: "ㄨㄛˇ",
            spanningLength: 1,
            isUserLocked: false,
            candidateValues: ["我"],
            candidateLogProbs: [-2.0]
        )
        let zaiNode = WTFNodeInfo(
            value: "在",
            reading: "ㄗㄞˋ",
            spanningLength: 1,
            isUserLocked: false,
            candidateValues: ["在", "再", "載"],
            candidateLogProbs: [-2.5, -3.2, -6.0]
        )
        let ceNode = WTFNodeInfo(
            value: "策",
            reading: "ㄘㄜˋ",
            spanningLength: 1,
            isUserLocked: false,
            candidateValues: ["策", "測", "側"],
            candidateLogProbs: [-4.5, -4.2, -5.0]
        )
        let shiNode = WTFNodeInfo(
            value: "試",
            reading: "ㄕˋ",
            spanningLength: 1,
            isUserLocked: false,
            candidateValues: ["試", "是", "事"],
            candidateLogProbs: [-2.0, -1.8, -2.5]
        )
        let yiNode = WTFNodeInfo(
            value: "一",
            reading: "ㄧ",
            spanningLength: 1,
            isUserLocked: false,
            candidateValues: ["一"],
            candidateLogProbs: [-1.0]
        )
        let ciNode = WTFNodeInfo(
            value: "次",
            reading: "ㄘˋ",
            spanningLength: 1,
            isUserLocked: false,
            candidateValues: ["次", "刺", "賜"],
            candidateLogProbs: [-2.8, -4.5, -5.0]
        )
        let reviewedZaiCe = reranker.reviewDisplaySentence(viterbiNodes: [woNode, zaiNode, ceNode, shiNode, yiNode, ciNode])
        #expect(reviewedZaiCe.joined() == "我再測試一次")

        // Case 3: 鑰匙在桌上 -> 處所語意，應維持「鑰匙在桌上」絕不誤改
        let yaoNode = WTFNodeInfo(
            value: "鑰匙",
            reading: "ㄧㄠˋ-˙ㄕ",
            spanningLength: 2,
            isUserLocked: false,
            candidateValues: ["鑰匙"],
            candidateLogProbs: [-4.0]
        )
        let zaiLocNode = WTFNodeInfo(
            value: "在",
            reading: "ㄗㄞˋ",
            spanningLength: 1,
            isUserLocked: false,
            candidateValues: ["在", "再", "載"],
            candidateLogProbs: [-2.5, -3.2, -6.0]
        )
        let zhuNode = WTFNodeInfo(
            value: "桌上",
            reading: "ㄓㄨㄛ-ㄕㄤˋ",
            spanningLength: 2,
            isUserLocked: false,
            candidateValues: ["桌上"],
            candidateLogProbs: [-3.5]
        )
        let reviewedLoc = reranker.reviewDisplaySentence(viterbiNodes: [yaoNode, zaiLocNode, zhuNode])
        #expect(reviewedLoc.joined() == "鑰匙在桌上")
    }

    @Test("Test whole-sentence N-Best review for reported failure sentences")
    func testWholeSentenceNBestReportedFailures() {
        let reranker = WTFNeuralReranker.shared
        reranker.isEnabled = true
        reranker.clearNegativeFeedback()

        func makeHyp(values: [String], readings: [String], locked: [Bool] = [], logProb: Double, totalReadings: Int) -> WTFNBestHypothesis {
            let lockFlags = locked.isEmpty ? [NSNumber](repeating: false, count: values.count) : locked.map { NSNumber(value: $0) }
            let spans = readings.map { NSNumber(value: $0.split(separator: "-").count) }
            return WTFNBestHypothesis(
                sentence: values.joined(),
                nodeValues: values,
                nodeReadings: readings,
                nodeSpanningLengths: spans,
                nodeLockedFlags: lockFlags,
                totalReadings: totalReadings,
                lexiconLogProb: logProb
            )
        }

        // 1. 他一再強調鑰匙不再他身上 -> 他一再強調鑰匙不在他身上
        let hyp1 = makeHyp(
            values: ["他", "一再", "強調", "鑰匙", "不再", "他", "身上"],
            readings: ["ㄊㄚ", "ㄧˊ-ㄗㄞˋ", "ㄑㄧㄤˊ-ㄉㄧㄠˋ", "ㄧㄠˋ-ㄕˊ", "ㄅㄨˋ-ㄗㄞˋ", "ㄊㄚ", "ㄕㄣ-ㄕㄤˋ"],
            logProb: -24.0,
            totalReadings: 11
        )
        let res1 = reranker.reviewNBestHypotheses([hyp1])
        #expect(res1?.joined() == "他一再強調鑰匙不在他身上")

        // 2. 請先再表單簽名 -> 請先在表單簽名
        let hyp2 = makeHyp(
            values: ["請先", "再", "表單", "簽名"],
            readings: ["ㄑㄧㄥˇ-ㄒㄧㄢ", "ㄗㄞˋ", "ㄅㄧㄠˇ-ㄉㄢ", "ㄑㄧㄢ-ㄇㄧㄥˊ"],
            logProb: -15.0,
            totalReadings: 7
        )
        let res2 = reranker.reviewNBestHypotheses([hyp2])
        #expect(res2?.joined() == "請先在表單簽名")

        // 3. 明天在交給主管 -> 明天再交給主管
        let hyp3 = makeHyp(
            values: ["明天", "在", "交給", "主管"],
            readings: ["ㄇㄧㄥˊ-ㄊㄧㄢ", "ㄗㄞˋ", "ㄐㄧㄠ-ㄍㄟˇ", "ㄓㄨˇ-ㄍㄨㄢˇ"],
            logProb: -14.0,
            totalReadings: 7
        )
        let res3 = reranker.reviewNBestHypotheses([hyp3])
        #expect(res3?.joined() == "明天再交給主管")

        // 4. 他帶著耳機 -> 他戴著耳機
        let hyp4 = makeHyp(
            values: ["他", "帶著", "耳機"],
            readings: ["ㄊㄚ", "ㄉㄞˋ-ㄓㄜ˙", "ㄦˇ-ㄐㄧ"],
            logProb: -11.0,
            totalReadings: 5
        )
        let res4 = reranker.reviewNBestHypotheses([hyp4])
        #expect(res4?.joined() == "他戴著耳機")

        // 5. 慢慢的走向 / 認真的寫完 / 仔細的檢查 -> 慢慢地走向 / 認真地寫完 / 仔細地檢查
        let hyp5 = makeHyp(
            values: ["慢慢的", "走向"],
            readings: ["ㄇㄢˋ-ㄇㄢˋ-ㄉㄜ˙", "ㄗㄡˇ-ㄒㄧㄤˋ"],
            logProb: -9.2,
            totalReadings: 5
        )
        #expect(reranker.reviewNBestHypotheses([hyp5])?.joined() == "慢慢地走向")

        let hyp6 = makeHyp(
            values: ["認真", "的", "寫完"],
            readings: ["ㄖㄣˋ-ㄓㄣ", "ㄉㄜ˙", "ㄒㄧㄝˇ-ㄨㄢˊ"],
            logProb: -11.4,
            totalReadings: 5
        )
        #expect(reranker.reviewNBestHypotheses([hyp6])?.joined() == "認真地寫完")

        let hyp7 = makeHyp(
            values: ["仔細", "的", "檢查"],
            readings: ["ㄗˇ-ㄒㄧˋ", "ㄉㄜ˙", "ㄐㄧㄢˇ-ㄔㄚˊ"],
            logProb: -10.3,
            totalReadings: 5
        )
        #expect(reranker.reviewNBestHypotheses([hyp7])?.joined() == "仔細地檢查")

        // 8. 我正在開會等等在打給你 -> 我正在開會等等再打給你
        let hyp8 = makeHyp(
            values: ["我", "正在", "開會", "等等", "在", "打給", "你"],
            readings: ["ㄨㄛˇ", "ㄓㄥˋ-ㄗㄞˋ", "ㄎㄞ-ㄏㄨㄟˋ", "ㄉㄥˇ-ㄉㄥˇ", "ㄗㄞˋ", "ㄉㄚˇ-ㄍㄟˇ", "ㄋㄧˇ"],
            logProb: -22.0,
            totalReadings: 11
        )
        let res8 = reranker.reviewNBestHypotheses([hyp8])
        #expect(res8?.joined() == "我正在開會等等再打給你")
    }

    @Test("Test user lock protection and negative feedback memory")
    func testUserLockAndNegativeFeedback() {
        let reranker = WTFNeuralReranker.shared
        reranker.isEnabled = true
        reranker.clearNegativeFeedback()

        // 1. 若使用者已手選鎖定「帶著」（isLocked = true），則不可改為「戴著」
        let lockedHyp = WTFNBestHypothesis(
            sentence: "他帶著耳機",
            nodeValues: ["他", "帶著", "耳機"],
            nodeReadings: ["ㄊㄚ", "ㄉㄞˋ-ㄓㄜ˙", "ㄦˇ-ㄐㄧ"],
            nodeSpanningLengths: [1, 2, 2],
            nodeLockedFlags: [false, true, false],
            totalReadings: 5,
            lexiconLogProb: -11.0
        )
        #expect(reranker.reviewNBestHypotheses([lockedHyp]) == nil)

        // 2. 若使用者曾將「戴著」手動改回「帶著」（觸發負回饋紀錄），同語境下不再自動改成「戴著」
        reranker.recordNegativeFeedback(
            reading: "ㄉㄞˋ-ㄓㄜ˙",
            rejected: "戴著",
            kept: "帶著",
            leftContext: "他"
        )
        let unlockedHyp = WTFNBestHypothesis(
            sentence: "他帶著耳機",
            nodeValues: ["他", "帶著", "耳機"],
            nodeReadings: ["ㄊㄚ", "ㄉㄞˋ-ㄓㄜ˙", "ㄦˇ-ㄐㄧ"],
            nodeSpanningLengths: [1, 2, 2],
            nodeLockedFlags: [false, false, false],
            totalReadings: 5,
            lexiconLogProb: -11.0
        )
        #expect(reranker.reviewNBestHypotheses([unlockedHyp]) == nil)
        reranker.clearNegativeFeedback()
    }

    @Test("Test end-to-end KeyHandler C++ walkNBest, gridRevision, and updated data.txt lexicon")
    func testEndToEndKeyHandlerNBestAndLexicon() {
        LanguageModelManager.loadDataModels()
        let handler = KeyHandler()
        handler.inputMode = .bopomofo
        Preferences.keyboardLayout = .standard
        Preferences.chineseConversionEnabled = false
        handler.syncWithPreferences()

        func typeKeys(_ keys: String) -> InputState.Inputting? {
            handler.clear()
            var state: InputState = InputState.Empty()
            for ch in keys {
                let s = String(ch)
                let scalar = UInt16(s.unicodeScalars.first!.value)
                let input = KeyHandlerInput(
                    inputText: s, keyCode: 0, charCode: scalar, flags: [], isVerticalMode: false
                )
                handler.handle(input: input, state: state) { newState in
                    state = newState
                } errorCallback: {}
            }
            let nBest = handler.currentNBestHypotheses(8)
            if !nBest.isEmpty, let reviewed = WTFNeuralReranker.shared.reviewNBestHypotheses(nBest) {
                handler.reviewedNodeValues = reviewed
                if let rebuilt = handler.buildInputtingState() as? InputState.Inputting {
                    return rebuilt
                }
            }
            return state as? InputState.Inputting
        }

        // 1. 驗證 gridRevision：單純輸入未成音聲母「ㄅ (1)」時，gridRevision 不變；完成音節後才遞增
        handler.clear()
        let rev0 = handler.gridRevision
        var tempState: InputState = InputState.Empty()
        let inputB = KeyHandlerInput(inputText: "1", keyCode: 0, charCode: charCode("1"), flags: [], isVerticalMode: false)
        handler.handle(input: inputB, state: tempState, stateCallback: { tempState = $0 }, errorCallback: {})
        #expect(handler.gridRevision == rev0)

        for k in ["u", "3"] {
            let inp = KeyHandlerInput(inputText: k, keyCode: 0, charCode: charCode(k), flags: [], isVerticalMode: false)
            handler.handle(input: inp, state: tempState, stateCallback: { tempState = $0 }, errorCallback: {})
        }
        #expect(handler.gridRevision > rev0)

        // 2. 驗證詞庫修復：表單 (1ul320 )、直冒汗 (56al4c04)、這份工作 (5k4zp4ej/ yji4)、笑到最後 (vul42l4yjo4c.4)
        #expect(typeKeys("1ul320 ")?.composingBuffer == "表單")
        #expect(typeKeys("56al4c04")?.composingBuffer == "直冒汗")
        #expect(typeKeys("5k4zp4ej/ yji4")?.composingBuffer == "這份工作")
        #expect(typeKeys("vul42l4yjo4c.4")?.composingBuffer == "笑到最後")

        // 3. 驗證整句 C++ walkNBest + reviewNBestHypotheses + reviewedNodeValues 狀態同步：
        // 「他一再強調鑰匙不在他身上」 (w8 u6y94fu;62ul4ul4g61j4y94w8 gp g;4)
        let e2e1 = typeKeys("w8 u6y94fu;62ul4ul4g61j4y94w8 gp g;4")
        #expect(e2e1?.composingBuffer == "他一再強調鑰匙不在他身上")
    }

    @Test("Test 100-sentence homophone_regression.tsv benchmark (0% control false-positive rate)")
    func testHomophoneRegressionBenchmark100Sentences() throws {
        let reranker = WTFNeuralReranker.shared
        reranker.isEnabled = true
        reranker.clearNegativeFeedback()
        reranker.config = ReviewerConfig.loadDefault()

        let testFileURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/homophone_regression.tsv")
        let content = try String(contentsOf: testFileURL, encoding: .utf8)

        var totalCases = 0
        var controlCases = 0
        var controlFalseModifications = 0

        for rawLine in content.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            if line.isEmpty || line.hasPrefix("#") { continue }
            let parts = line.components(separatedBy: "\t")
            guard parts.count >= 4 else { continue }

            let category = parts[0]
            let reading = parts[1]
            let viterbiNodes = parts[2].components(separatedBy: "|")
            let expected = parts[3]
            let readingLen = reading.components(separatedBy: "-").count
            let spans = viterbiNodes.map { NSNumber(value: max(1, $0.count)) }
            let locks = [NSNumber](repeating: false, count: viterbiNodes.count)
            let dummyReadings = [String](repeating: "", count: viterbiNodes.count)

            let hyp = WTFNBestHypothesis(
                sentence: viterbiNodes.joined(),
                nodeValues: viterbiNodes,
                nodeReadings: dummyReadings,
                nodeSpanningLengths: spans,
                nodeLockedFlags: locks,
                totalReadings: readingLen,
                lexiconLogProb: -3.8 * Double(readingLen)
            )

            let reviewed = reranker.reviewNBestHypotheses([hyp])?.joined() ?? viterbiNodes.joined()
            totalCases += 1
            if category == "control" {
                controlCases += 1
                if reviewed != expected {
                    controlFalseModifications += 1
                }
            }
            #expect(reviewed == expected, "Category [\(category)] failed: expected '\(expected)', got '\(reviewed)'")
        }

        #expect(totalCases == 100)
        #expect(controlCases == 50)
        #expect(controlFalseModifications == 0)
    }

    @Test("Test KyonLM Core ML [8, 48] model loading, SHA-256 verification, and batch scoring")
    func testKyonLMCoreMLModelContractAndScoring() throws {
        let reranker = WTFNeuralReranker.shared
        reranker.reloadModelAndConfig()

        guard let scorer = KyonLMScorer() else {
            Issue.record("Expected KyonLMScorer to initialize from KyonLM.mlmodelc and vocab.txt")
            return
        }
        #expect(scorer.isAvailable == true)
        #expect(scorer.identifier.hasPrefix("kyon-lm-"))

        let sentences = [
            "鑰匙不在他身上",
            "鑰匙不再他身上",
            "他戴著耳機",
            "他帶著耳機",
            "慢慢地走向門口",
            "慢慢的走向門口"
        ]
        let t0 = CFAbsoluteTimeGetCurrent()
        let scores = scorer.score(sentences: sentences)
        let elapsedMs = (CFAbsoluteTimeGetCurrent() - t0) * 1000.0

        #expect(scores != nil)
        #expect(scores?.count == sentences.count)
        if let sc = scores {
            for val in sc {
                #expect(val.isFinite)
                #expect(val < 0.0)
            }
        }
        #expect(elapsedMs < 60.0)
    }
}
