// Copyright (c) 2026 wtf. All rights reserved.
// WTFNeuralReranker.swift — 整句 N-Best 審查器、可插拔 KyonLM 語言模型介面、同尺度語意規則與負回饋系統

import CoreML
import CryptoKit
import Foundation
import os.log

// MARK: - 1. 可插拔整句評分介面 (SentenceScorer Protocol)

public protocol SentenceScorer {
    var isAvailable: Bool { get }
    var identifier: String { get }
    /// 對最多 8 條候選整句評分，回傳每句的平均 token log-probability；若無模型或失敗則回傳 nil
    func score(sentences: [String]) -> [Float]?
}

public final class NullScorer: SentenceScorer {
    public let isAvailable: Bool = false
    public let identifier: String = "null-scorer"
    public init() {}
    public func score(sentences: [String]) -> [Float]? {
        return nil
    }
}

/// 新一代字級單向 Transformer 語言模型評分器 (規格對齊 redesign-spec.md 第 7 節：[8, 48] Int32/Float16)
public final class KyonLMScorer: SentenceScorer {
    public private(set) var isAvailable: Bool = false
    public private(set) var identifier: String = "kyon-lm-v2"

    private var mlModel: MLModel?
    private var vocabMap: [Character: Int32] = [:]
    private let padId: Int32 = 0
    private let unkId: Int32 = 1
    private let bosId: Int32 = 2
    private let eosId: Int32 = 3
    private let batchSize: Int = 8
    private let maxSeqLen: Int = 48
    private var slowInferenceStreak: Int = 0

    public init?() {
        guard let (modelURL, vocabURL) = Self.locateModelAndVocab() else {
            return nil
        }
        do {
            let vocabData = try Data(contentsOf: vocabURL)
            let vocabDigest = SHA256.hash(data: vocabData)
            let actualSha256 = vocabDigest.map { String(format: "%02x", $0) }.joined()

            guard let vocabText = String(data: vocabData, encoding: .utf8) else {
                return nil
            }
            let lines = vocabText.components(separatedBy: .newlines)
            var map: [Character: Int32] = [:]
            for (idx, line) in lines.enumerated() {
                if idx >= 4, let ch = line.first, line.count == 1 {
                    map[ch] = Int32(idx)
                }
            }
            guard !map.isEmpty else { return nil }

            let config = MLModelConfiguration()
            config.computeUnits = .all
            let loaded = try MLModel(contentsOf: modelURL, configuration: config)
            if let meta = loaded.modelDescription.metadata[MLModelMetadataKey.creatorDefinedKey] as? [String: String] {
                if let expectedSha = meta["kyon.vocab_sha256"],
                   !expectedSha.isEmpty,
                   expectedSha.lowercased() != actualSha256.lowercased() {
                    return nil
                }
                if let kyonVer = meta["kyon.version"], !kyonVer.isEmpty {
                    self.identifier = "kyon-lm-\(kyonVer)"
                }
            }
            self.vocabMap = map
            self.mlModel = loaded
            self.isAvailable = true
        } catch {
            return nil
        }
    }

    private static func locateModelAndVocab() -> (URL, URL)? {
        let fm = FileManager.default
        let userModelsDir = fm.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/gg/Models")
        let userModel = userModelsDir.appendingPathComponent("KyonLM.mlmodelc")
        let userVocab = userModelsDir.appendingPathComponent("vocab.txt")
        if fm.fileExists(atPath: userModel.path) && fm.fileExists(atPath: userVocab.path) {
            return (userModel, userVocab)
        }

        let bundles = [Bundle.main, Bundle(for: WTFNeuralReranker.self)]
        for bundle in bundles {
            if let mURL = bundle.url(forResource: "KyonLM", withExtension: "mlmodelc"),
               let vURL = bundle.url(forResource: "vocab", withExtension: "txt") {
                return (mURL, vURL)
            }
        }

        let sourceModelDir = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Resources/Model")
        let srcModel = sourceModelDir.appendingPathComponent("KyonLM.mlmodelc")
        let srcVocab = sourceModelDir.appendingPathComponent("vocab.txt")
        if fm.fileExists(atPath: srcModel.path) && fm.fileExists(atPath: srcVocab.path) {
            return (srcModel, srcVocab)
        }

        return nil
    }

    public func score(sentences: [String]) -> [Float]? {
        guard isAvailable, let model = mlModel, !sentences.isEmpty else {
            return nil
        }

        let t0 = CFAbsoluteTimeGetCurrent()
        do {
            let shape: [NSNumber] = [NSNumber(value: batchSize), NSNumber(value: maxSeqLen)]
            let inputIds = try MLMultiArray(shape: shape, dataType: .int32)
            let targetIds = try MLMultiArray(shape: shape, dataType: .int32)
            let attnMask = try MLMultiArray(shape: shape, dataType: .float16)

            let inStrideB = inputIds.strides[0].intValue
            let inStrideP = inputIds.strides[1].intValue
            let tgtStrideB = targetIds.strides[0].intValue
            let tgtStrideP = targetIds.strides[1].intValue
            let maskStrideB = attnMask.strides[0].intValue
            let maskStrideP = attnMask.strides[1].intValue

            let inPtr = inputIds.dataPointer.bindMemory(to: Int32.self, capacity: batchSize * inStrideB)
            let tgtPtr = targetIds.dataPointer.bindMemory(to: Int32.self, capacity: batchSize * tgtStrideB)
            let maskPtr = attnMask.dataPointer.bindMemory(to: Float16.self, capacity: batchSize * maskStrideB)

            var validLengths = [Int](repeating: 1, count: batchSize)

            for b in 0..<batchSize {
                for pos in 0..<maxSeqLen {
                    inPtr[b * inStrideB + pos * inStrideP] = padId
                    tgtPtr[b * tgtStrideB + pos * tgtStrideP] = padId
                    maskPtr[b * maskStrideB + pos * maskStrideP] = 0.0
                }

                guard b < sentences.count else { continue }
                let chars = Array(sentences[b].prefix(maxSeqLen - 2))
                var tokens: [Int32] = [bosId]
                for ch in chars {
                    tokens.append(vocabMap[ch] ?? unkId)
                }
                tokens.append(eosId)

                let targetCount = max(1, tokens.count - 1)
                validLengths[b] = targetCount
                for pos in 0..<targetCount {
                    inPtr[b * inStrideB + pos * inStrideP] = tokens[pos]
                    tgtPtr[b * tgtStrideB + pos * tgtStrideP] = tokens[pos + 1]
                    maskPtr[b * maskStrideB + pos * maskStrideP] = 1.0
                }
            }

            let provider = try MLDictionaryFeatureProvider(dictionary: [
                "input_ids": MLFeatureValue(multiArray: inputIds),
                "target_ids": MLFeatureValue(multiArray: targetIds),
                "attention_mask": MLFeatureValue(multiArray: attnMask)
            ])

            let prediction = try model.prediction(from: provider)
            guard let outArray = prediction.featureValue(for: "token_logprob")?.multiArrayValue else {
                return nil
            }

            let elapsedMs = (CFAbsoluteTimeGetCurrent() - t0) * 1000.0
            if elapsedMs > 60.0 {
                slowInferenceStreak += 1
                if slowInferenceStreak >= 5 {
                    isAvailable = false
                    return nil
                }
            } else {
                slowInferenceStreak = 0
            }

            let outStrideB = outArray.strides[0].intValue
            let outStrideP = outArray.strides[1].intValue
            var scores: [Float] = []
            scores.reserveCapacity(sentences.count)

            if outArray.dataType == .float16 {
                let outPtr = outArray.dataPointer.bindMemory(to: Float16.self, capacity: batchSize * outStrideB)
                for b in 0..<min(sentences.count, batchSize) {
                    var sum: Float = 0.0
                    for pos in 0..<validLengths[b] {
                        sum += Float(outPtr[b * outStrideB + pos * outStrideP])
                    }
                    scores.append(sum / Float(validLengths[b]))
                }
            } else {
                let outPtr = outArray.dataPointer.bindMemory(to: Float.self, capacity: batchSize * outStrideB)
                for b in 0..<min(sentences.count, batchSize) {
                    var sum: Float = 0.0
                    for pos in 0..<validLengths[b] {
                        sum += outPtr[b * outStrideB + pos * outStrideP]
                    }
                    scores.append(sum / Float(validLengths[b]))
                }
            }
            return scores
        } catch {
            return nil
        }
    }
}

// MARK: - 2. 負回饋儲存系統 (ReviewFeedbackStore)

public struct NegativeFeedbackEntry: Codable, Equatable {
    public let reading: String
    public let rejected: String
    public let kept: String
    public let leftContext: String
    public var count: Int
    public var lastSeen: TimeInterval
}

public final class ReviewFeedbackStore {
    private var entries: [String: NegativeFeedbackEntry] = [:]
    private let lock = NSLock()
    private let maxEntries = 5000

    private var fileURL: URL {
        let dir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/gg")
        return dir.appendingPathComponent("review_feedback.json")
    }

    public init() {
        loadFromDisk()
    }

    private func makeKey(reading: String, rejected: String, leftContext: String) -> String {
        let left2 = String(leftContext.suffix(2))
        return "\(left2)|\(reading)|\(rejected)"
    }

    public func record(reading: String, rejected: String, kept: String, leftContext: String) {
        guard !rejected.isEmpty, rejected != kept else { return }
        let left2 = String(leftContext.suffix(2))
        let key = makeKey(reading: reading, rejected: rejected, leftContext: left2)
        let now = Date().timeIntervalSince1970

        lock.lock()
        if var existing = entries[key] {
            existing.count += 1
            existing.lastSeen = now
            entries[key] = existing
        } else {
            if entries.count >= maxEntries {
                if let oldestKey = entries.min(by: { $0.value.lastSeen < $1.value.lastSeen })?.key {
                    entries.removeValue(forKey: oldestKey)
                }
            }
            entries[key] = NegativeFeedbackEntry(
                reading: reading,
                rejected: rejected,
                kept: kept,
                leftContext: left2,
                count: 1,
                lastSeen: now
            )
        }
        let snapshot = Array(entries.values)
        lock.unlock()

        saveToDiskAsync(snapshot)
    }

    public func isRejected(reading: String, candidate: String, leftContext: String) -> Bool {
        let left2 = String(leftContext.suffix(2))
        let key = makeKey(reading: reading, rejected: candidate, leftContext: left2)
        lock.lock()
        let hit = entries[key] != nil
        lock.unlock()
        return hit
    }

    public func clearAll() {
        lock.lock()
        entries.removeAll()
        lock.unlock()
        try? FileManager.default.removeItem(at: fileURL)
    }

    private func loadFromDisk() {
        guard let data = try? Data(contentsOf: fileURL),
              let list = try? JSONDecoder().decode([NegativeFeedbackEntry].self, from: data) else {
            return
        }
        lock.lock()
        for item in list {
            let key = makeKey(reading: item.reading, rejected: item.rejected, leftContext: item.leftContext)
            entries[key] = item
        }
        lock.unlock()
    }

    private func saveToDiskAsync(_ snapshot: [NegativeFeedbackEntry]) {
        let url = fileURL
        DispatchQueue.global(qos: .utility).async {
            let dir = url.deletingLastPathComponent()
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            if let data = try? JSONEncoder().encode(snapshot) {
                try? data.write(to: url, options: .atomic)
            }
        }
    }
}

// MARK: - 3. 審查門檻與融合設定 (ReviewerConfig)

public struct ReviewerConfig: Codable {
    public var alphaLM: Double = 1.0
    public var betaLex: Double = 0.05
    public var temperature: Double = 0.15
    public var minBestProb: Double = 0.58
    public var minProbMargin: Double = 0.12
    public var singleRuleScale: Double = 0.30
    public var maxTotalRuleBias: Double = 0.60

    public static func loadDefault() -> ReviewerConfig {
        let bundles = [Bundle.main, Bundle(for: WTFNeuralReranker.self)]
        for bundle in bundles {
            if let url = bundle.url(forResource: "reviewer_config", withExtension: "json"),
               let data = try? Data(contentsOf: url),
               let decoded = try? JSONDecoder().decode(ReviewerConfig.self, from: data) {
                return decoded
            }
        }
        let sourceConfigURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Resources/reviewer_config.json")
        if let data = try? Data(contentsOf: sourceConfigURL),
           let decoded = try? JSONDecoder().decode(ReviewerConfig.self, from: data) {
            return decoded
        }
        return ReviewerConfig()
    }
}

// MARK: - 4. 整句與節點審查器 (WTFNeuralReranker)

public class WTFNeuralReranker {
    public static let shared = WTFNeuralReranker()

    private let log = OSLog(subsystem: "com.wtf.inputmethod.gg", category: "NeuralReranker")

    public var isEnabled: Bool = true {
        didSet {
            publishTelemetryToSharedDefaults()
        }
    }
    public var config: ReviewerConfig = ReviewerConfig.loadDefault()
    public var sentenceScorer: SentenceScorer
    public let feedbackStore = ReviewFeedbackStore()

    public private(set) var totalInferenceCount: Int = 0
    public private(set) var lastInferenceLatencyMs: Double = 0.0
    public private(set) var lastRerankedSummary: String = "待命中"

    public var isNeuralModelLoaded: Bool {
        return sentenceScorer.isAvailable
    }


    private init() {
        if let kyonLM = KyonLMScorer() {
            self.sentenceScorer = kyonLM
        } else {
            self.sentenceScorer = NullScorer()
        }
        publishTelemetryToSharedDefaults()
    }

    public func reloadModelAndConfig() {
        self.config = ReviewerConfig.loadDefault()
        if let kyonLM = KyonLMScorer() {
            self.sentenceScorer = kyonLM
        } else {
            self.sentenceScorer = NullScorer()
        }
        publishTelemetryToSharedDefaults()
    }

    private func publishTelemetryToSharedDefaults() {
        let suiteName = "com.wtf.inputmethod.gg"
        let defaults = UserDefaults(suiteName: suiteName) ?? .standard
        defaults.set(isEnabled, forKey: "NeuralIsModelLoaded")
        defaults.set(totalInferenceCount, forKey: "NeuralTotalInferences")
        defaults.set(lastInferenceLatencyMs, forKey: "NeuralLastLatencyMs")
        defaults.set(lastRerankedSummary, forKey: "NeuralLastSummary")
        defaults.set(sentenceScorer.isAvailable ? "KyonLM (\(sentenceScorer.identifier))" : "規則與詞庫融合", forKey: "NeuralModelSizeString")
        defaults.set("Apple Neural Engine (ANE)", forKey: "NeuralHardwareEngine")
    }

    // MARK: - 負回饋公開 API

    public func recordNegativeFeedback(reading: String, rejected: String, kept: String, leftContext: String) {
        feedbackStore.record(reading: reading, rejected: rejected, kept: kept, leftContext: leftContext)
    }

    public func clearNegativeFeedback() {
        feedbackStore.clearAll()
    }

    // MARK: - 整句 N-Best 審查主入口 (Stage 3 核心)

    private static let homophoneTriggerChars = CharacterSet(charactersIn: "在再的得地帶戴做作冗茸")

    private struct CandidatePath {
        let nodeValues: [String]
        let nodeReadings: [String]
        let nodeLockedFlags: [Bool]
        let sentence: String
        let lexiconLogProb: Double
    }

    /// 對 ReadingGrid::walkNBest(8) 產生的前 N 條整句候選進行融合打分與 Softmax 門檻決策
    /// 回傳最終選定路徑的各節點字串；若維持 Viterbi 原句且無需修改則回傳 nil
    public func reviewNBestHypotheses(_ hypotheses: [WTFNBestHypothesis]) -> [String]? {
        guard isEnabled, let firstHyp = hypotheses.first else {
            return nil
        }

        // 極速前置剪枝（< 1 微秒）：若只有 1 條候選且全句不含常見同音詞，則無需神經模型推論，避免主執行緒卡頓
        if hypotheses.count <= 1 {
            let s = firstHyp.sentence
            if s.rangeOfCharacter(from: Self.homophoneTriggerChars) == nil
                && !s.contains("反映") && !s.contains("反應") {
                return nil
            }
        }

        let t0 = CFAbsoluteTimeGetCurrent()
        let readingLen = max(1, firstHyp.totalReadings)

        // 1. 準備候選路徑集合（包含對每條 N-best 進行整句同音規則微調的衍生句）
        var pool: [CandidatePath] = []
        var seenSentences = Set<String>()

        for hyp in hypotheses {
            let locked = hyp.nodeLockedFlags.map { $0.boolValue }
            let base = CandidatePath(
                nodeValues: hyp.nodeValues,
                nodeReadings: hyp.nodeReadings,
                nodeLockedFlags: locked,
                sentence: hyp.sentence,
                lexiconLogProb: hyp.lexiconLogProb
            )
            if seenSentences.insert(base.sentence).inserted {
                pool.append(base)
            }

            // 檢查該路徑上是否有未鎖定節點可由整句規則直接產生更佳同音變體（例如「不再」->「不在」、「慢慢的」->「慢慢地」）
            let refinedValues = refineNodesWithSentenceRules(
                nodeValues: hyp.nodeValues,
                nodeReadings: hyp.nodeReadings,
                nodeLockedFlags: locked
            )
            let refinedSentence = refinedValues.joined()
            if refinedSentence != base.sentence && seenSentences.insert(refinedSentence).inserted {
                pool.append(CandidatePath(
                    nodeValues: refinedValues,
                    nodeReadings: hyp.nodeReadings,
                    nodeLockedFlags: locked,
                    sentence: refinedSentence,
                    lexiconLogProb: hyp.lexiconLogProb
                ))
            }

            // 主動衍生同音候選變體（在/再、的/得/地、帶/戴、做/作、反映/反應），讓 KyonLM 直接評估
            let variants = generateHomophoneCandidateVariants(
                nodeValues: hyp.nodeValues,
                nodeReadings: hyp.nodeReadings,
                nodeLockedFlags: locked,
                baseLexiconLogProb: hyp.lexiconLogProb
            )
            for v in variants {
                if pool.count >= 8 { break }
                if seenSentences.insert(v.sentence).inserted {
                    pool.append(v)
                }
            }
        }

        guard pool.count > 1 else {
            return nil
        }

        // 限制最多 8 條送入評分
        let activePool = Array(pool.prefix(8))
        let sentences = activePool.map { $0.sentence }
        let lmScores = sentenceScorer.score(sentences: sentences)
        let baseLmScore = (lmScores != nil && !lmScores!.isEmpty) ? Double(lmScores![0]) : 0.0
        let baseLexScore = activePool[0].lexiconLogProb
        let baseRuleTerm = computeSentenceRuleBias(
            nodeValues: activePool[0].nodeValues,
            nodeReadings: activePool[0].nodeReadings
        )

        // 2. 計算每條整句的融合分數 z_i
        var logits = [Double](repeating: 0.0, count: activePool.count)
        for (i, path) in activePool.enumerated() {
            if hasNegativeFeedbackViolation(path.nodeValues, readings: path.nodeReadings) {
                logits[i] = -1e9
                continue
            }

            let lexTerm = config.betaLex * (path.lexiconLogProb / Double(readingLen))
            let ruleTerm = computeSentenceRuleBias(
                nodeValues: path.nodeValues,
                nodeReadings: path.nodeReadings
            )

            var lmTerm = 0.0
            if let scores = lmScores, i < scores.count, i > 0 {
                let rawDelta = Double(scores[i]) - baseLmScore
                let lexDeltaPerReading = (path.lexiconLogProb - baseLexScore) / Double(readingLen)
                if ruleTerm <= baseRuleTerm && lexDeltaPerReading < -0.15 {
                    // 對詞庫分數明顯較差且無語意規則支撐的次佳切分路徑採取保守門檻，防止誤改正常句
                    let conservativeDelta = rawDelta > 0.35 ? (rawDelta - 0.35) : min(0.0, rawDelta)
                    lmTerm = config.alphaLM * max(-0.45, min(0.45, conservativeDelta * 0.25))
                } else {
                    lmTerm = config.alphaLM * max(-0.45, min(0.45, rawDelta * 0.25))
                }
            }

            logits[i] = lmTerm + lexTerm + ruleTerm
        }

        // 3. Softmax 機率轉換與門檻判斷
        let probs = softmax(logits, temperature: config.temperature)
        let viterbiProb = probs[0]

        var bestIdx = 0
        var bestProb = viterbiProb
        for i in 1..<probs.count {
            if probs[i] > bestProb {
                bestProb = probs[i]
                bestIdx = i
            }
        }

        let elapsedMs = (CFAbsoluteTimeGetCurrent() - t0) * 1000.0
        totalInferenceCount += 1
        lastInferenceLatencyMs = elapsedMs

        if bestIdx != 0 && bestProb >= config.minBestProb && (bestProb - viterbiProb) >= config.minProbMargin {
            let chosen = activePool[bestIdx]
            lastRerankedSummary = String(
                format: "整句修正：「%@」→「%@」(p=%.2f, Δ=%.2f, %.2fms)",
                activePool[0].sentence, chosen.sentence, bestProb, bestProb - viterbiProb, elapsedMs
            )
            publishTelemetryToSharedDefaults()
            return chosen.nodeValues
        }

        publishTelemetryToSharedDefaults()
        return nil
    }

    // MARK: - 節點陣列審查入口 (相容現有測試與單一路徑輸入)

    public func reviewDisplaySentence(viterbiNodes: [WTFNodeInfo]) -> [String] {
        guard isEnabled, !viterbiNodes.isEmpty else {
            return viterbiNodes.map { $0.value }
        }

        var workingWords = viterbiNodes.map { $0.value }
        let readings = viterbiNodes.map { $0.reading }
        let locked = viterbiNodes.map { $0.isUserLocked }

        // 先套用整句跨節點/多字節點規則（例如「不再他身上」->「不在他身上」、「慢慢的」->「慢慢地」）
        workingWords = refineNodesWithSentenceRules(
            nodeValues: workingWords,
            nodeReadings: readings,
            nodeLockedFlags: locked
        )

        // 再針對有超過 1 個候選的未鎖定節點進行雙向滑動視窗 Softmax 比較
        for pass in 0..<2 {
            var changedInPass = false
            for i in 0..<viterbiNodes.count {
                let node = viterbiNodes[i]
                if node.isUserLocked || node.candidateValues.count <= 1 {
                    continue
                }

                let leftContext = i > 0 ? workingWords[0..<i].joined() : ""
                let rightContext = (i + 1 < workingWords.count) ? workingWords[(i + 1)..<workingWords.count].joined() : ""

                let candidates = Array(node.candidateValues.prefix(8))
                let logProbs = node.candidateLogProbs.map { $0.doubleValue }
                let spanLen = Double(max(1, node.spanningLength))

                var candLogits = [Double](repeating: 0.0, count: candidates.count)
                for (cIdx, cand) in candidates.enumerated() {
                    if feedbackStore.isRejected(reading: node.reading, candidate: cand, leftContext: leftContext) {
                        candLogits[cIdx] = -1e9
                        continue
                    }
                    let rawLex = cIdx < logProbs.count ? logProbs[cIdx] : -6.0
                    let lexTerm = config.betaLex * (rawLex / spanLen)
                    let rawRule = computeSemanticAffinityRules(
                        candidate: cand,
                        reading: node.reading,
                        leftContext: leftContext,
                        rightContext: rightContext
                    )
                    // 縮放規則加權至同尺度 (±0.3 ~ ±0.6)
                    let scaledRule = max(-config.maxTotalRuleBias, min(config.maxTotalRuleBias, rawRule * 0.015))
                    candLogits[cIdx] = lexTerm + scaledRule
                }

                let probs = softmax(candLogits, temperature: config.temperature)
                let currentVal = workingWords[i]
                let currentIdx = candidates.firstIndex(of: currentVal) ?? 0
                let currentProb = probs[currentIdx]

                var bestIdx = currentIdx
                var bestProb = currentProb
                for cIdx in 0..<probs.count {
                    if probs[cIdx] > bestProb {
                        bestProb = probs[cIdx]
                        bestIdx = cIdx
                    }
                }

                if bestIdx != currentIdx && bestProb >= config.minBestProb && (bestProb - currentProb) >= config.minProbMargin {
                    workingWords[i] = candidates[bestIdx]
                    changedInPass = true
                }
            }
            if !changedInPass && pass == 0 {
                break
            }
        }

        return workingWords
    }

    // MARK: - 選字窗候選重排 (UTF-16 安全索引與剔除目標字)

    func rerank(
        candidates: [InputState.Candidate],
        composingBuffer: String,
        cursorIndex: Int
    ) -> [InputState.Candidate] {
        guard isEnabled, candidates.count > 1 else {
            return candidates
        }

        // 將 UTF-16 offset 安全轉換為 String.Index
        let utf16View = composingBuffer.utf16
        let safeUTF16Offset = max(0, min(cursorIndex, utf16View.count))
        let splitUTF16Idx = utf16View.index(utf16View.startIndex, offsetBy: safeUTF16Offset)
        let splitIdx = splitUTF16Idx.samePosition(in: composingBuffer) ?? composingBuffer.startIndex

        let leftContext = String(composingBuffer[..<splitIdx])
        var rightContext = String(composingBuffer[splitIdx...])

        // 若 rightContext 開頭正好是正在被替換的候選字，將其從右文剔除以避免干擾評分
        if let firstCandLen = candidates.first?.value.count, firstCandLen > 0,
           candidates.contains(where: { !$0.value.isEmpty && rightContext.hasPrefix($0.value) }) {
            rightContext = String(rightContext.dropFirst(firstCandLen))
        }

        let topK = min(candidates.count, 12)
        var scored: [(index: Int, score: Double)] = []
        scored.reserveCapacity(topK)

        for i in 0..<topK {
            let cand = candidates[i]
            if feedbackStore.isRejected(reading: cand.reading, candidate: cand.value, leftContext: leftContext) {
                scored.append((i, -1e9))
                continue
            }
            let prior = Double(topK - i) * 0.01
            let rawRule = computeSemanticAffinityRules(
                candidate: cand.value,
                reading: cand.reading,
                leftContext: leftContext,
                rightContext: rightContext
            )
            let scaledRule = max(-config.maxTotalRuleBias, min(config.maxTotalRuleBias, rawRule * 0.015))
            scored.append((i, prior + scaledRule))
        }

        let logits = scored.map { $0.score }
        let probs = softmax(logits, temperature: config.temperature)
        var bestSlot = 0
        for i in 1..<probs.count {
            if probs[i] > probs[bestSlot] {
                bestSlot = i
            }
        }

        guard bestSlot != 0,
              probs[bestSlot] >= config.minBestProb,
              (probs[bestSlot] - probs[0]) >= config.minProbMargin else {
            return candidates
        }

        let sortedIndices = scored.sorted { $0.score > $1.score }.map { $0.index }
        var result: [InputState.Candidate] = []
        result.reserveCapacity(candidates.count)
        for idx in sortedIndices {
            result.append(candidates[idx])
        }
        if topK < candidates.count {
            result.append(contentsOf: candidates[topK...])
        }
        return result
    }

    // MARK: - 單節點候選測試輔助入口

    public func rescoreNodeCandidates(
        candidates: [String],
        currentValue: String,
        leftContext: String,
        rightContext: String
    ) -> String? {
        guard isEnabled, candidates.count > 1 else {
            return nil
        }

        var logits: [Double] = []
        logits.reserveCapacity(candidates.count)
        for (i, cand) in candidates.enumerated() {
            let prior = (cand == currentValue) ? 0.02 : Double(candidates.count - i) * 0.005
            let rawRule = computeSemanticAffinityRules(
                candidate: cand,
                reading: "",
                leftContext: leftContext,
                rightContext: rightContext
            )
            let scaledRule = max(-config.maxTotalRuleBias, min(config.maxTotalRuleBias, rawRule * 0.015))
            logits.append(prior + scaledRule)
        }

        let probs = softmax(logits, temperature: config.temperature)
        let currIdx = candidates.firstIndex(of: currentValue) ?? 0
        var bestIdx = currIdx
        for i in 0..<probs.count {
            if probs[i] > probs[bestIdx] {
                bestIdx = i
            }
        }

        if bestIdx != currIdx && probs[bestIdx] >= config.minBestProb && (probs[bestIdx] - probs[currIdx]) >= config.minProbMargin {
            return candidates[bestIdx]
        }
        return nil
    }

    // MARK: - 數學與輔助函式

    private func softmax(_ logits: [Double], temperature: Double) -> [Double] {
        guard !logits.isEmpty else { return [] }
        let tau = max(0.05, temperature)
        let scaled = logits.map { $0 / tau }
        let maxVal = scaled.max() ?? 0.0
        let exps = scaled.map { exp($0 - maxVal) }
        let sumExp = exps.reduce(0.0, +)
        guard sumExp > 0 else {
            return [Double](repeating: 1.0 / Double(logits.count), count: logits.count)
        }
        return exps.map { $0 / sumExp }
    }

    private func hasNegativeFeedbackViolation(_ nodeValues: [String], readings: [String]) -> Bool {
        var leftBuf = ""
        for i in 0..<min(nodeValues.count, readings.count) {
            if feedbackStore.isRejected(reading: readings[i], candidate: nodeValues[i], leftContext: leftBuf) {
                return true
            }
            leftBuf += nodeValues[i]
        }
        return false
    }

    /// 針對句子中出現的常見同音混淆字（在/再、的/得/地、戴/帶、做/作、反映/反應），為未鎖定節點主動生成候選變體路徑，
    /// 以供神經語言模型（KyonLM）直接打分對比
    private func generateHomophoneCandidateVariants(
        nodeValues: [String],
        nodeReadings: [String],
        nodeLockedFlags: [Bool],
        baseLexiconLogProb: Double
    ) -> [CandidatePath] {
        var variants: [CandidatePath] = []
        let count = nodeValues.count

        for i in 0..<count {
            if i < nodeLockedFlags.count && nodeLockedFlags[i] {
                continue
            }

            let val = nodeValues[i]
            var replacementOptions: [String] = []

            if val == "在" {
                replacementOptions.append("再")
            } else if val == "再" {
                replacementOptions.append("在")
            } else if val == "的" {
                replacementOptions.append(contentsOf: ["地", "得"])
            } else if val == "地" {
                replacementOptions.append(contentsOf: ["的", "得"])
            } else if val == "得" {
                replacementOptions.append(contentsOf: ["的", "地"])
            } else if val == "帶" {
                replacementOptions.append("戴")
            } else if val == "戴" {
                replacementOptions.append("帶")
            } else if val == "做" {
                replacementOptions.append("作")
            } else if val == "作" {
                replacementOptions.append("做")
            } else if val == "反映" {
                replacementOptions.append("反應")
            } else if val == "反應" {
                replacementOptions.append("反映")
            } else if val == "不再" {
                replacementOptions.append("不在")
            } else if val == "不在" {
                replacementOptions.append("不再")
            } else if val == "先在" {
                replacementOptions.append("先再")
            } else if val == "先再" {
                replacementOptions.append("先在")
            } else if val == "帶著" {
                replacementOptions.append("戴著")
            } else if val == "戴著" {
                replacementOptions.append("帶著")
            }

            if replacementOptions.isEmpty {
                continue
            }

            let reading = i < nodeReadings.count ? nodeReadings[i] : ""
            let leftContext = i > 0 ? nodeValues[0..<i].joined() : ""

            for rep in replacementOptions {
                if feedbackStore.isRejected(reading: reading, candidate: rep, leftContext: leftContext) {
                    continue
                }
                var newValues = nodeValues
                newValues[i] = rep
                let newSentence = newValues.joined()
                variants.append(CandidatePath(
                    nodeValues: newValues,
                    nodeReadings: nodeReadings,
                    nodeLockedFlags: nodeLockedFlags,
                    sentence: newSentence,
                    lexiconLogProb: baseLexiconLogProb
                ))
            }
        }

        return variants
    }

    /// 針對整句包含多字節點或跨節點的場景（例如「慢慢的」+「走向」、「不再」+「他身上」），產生規則微調後的節點陣列
    private func refineNodesWithSentenceRules(
        nodeValues: [String],
        nodeReadings: [String],
        nodeLockedFlags: [Bool]
    ) -> [String] {
        var out = nodeValues
        let count = out.count

        for i in 0..<count {
            let isLocked = i < nodeLockedFlags.count ? nodeLockedFlags[i] : false
            if isLocked { continue }

            let val = out[i]
            let reading = i < nodeReadings.count ? nodeReadings[i] : ""
            let leftContext = i > 0 ? out[0..<i].joined() : ""
            let rightContext = (i + 1 < count) ? out[(i + 1)..<count].joined() : ""

            // 1. 多字詞節點結尾「的 -> 地」修正（例如 Viterbi 切出「慢慢的」「認真的」「仔細的」後接動詞）
            if val.count >= 2 && val.hasSuffix("的") && (reading.isEmpty || reading.hasSuffix("ㄉㄜ˙")) && !rightContext.isEmpty {
                let prefix = String(val.dropLast())
                let dummyBoost = computeSemanticAffinityRules(
                    candidate: "地",
                    reading: "ㄉㄜ˙",
                    leftContext: leftContext + prefix,
                    rightContext: rightContext
                )
                if dummyBoost >= 15.0 {
                    let candidateVal = prefix + "地"
                    if !feedbackStore.isRejected(reading: reading, candidate: candidateVal, leftContext: leftContext) {
                        out[i] = candidateVal
                        continue
                    }
                }
            }

            // 2. 雙字節點「不再 <-> 不在」與「先在 <-> 先再」修正
            if (val == "不再" || val == "不在") && (reading.isEmpty || reading == "ㄅㄨˋ-ㄗㄞˋ" || reading == "ㄅㄨˊ-ㄗㄞˋ") {
                let zaiScore = computeSemanticAffinityRules(
                    candidate: "在",
                    reading: "ㄗㄞˋ",
                    leftContext: leftContext + "不",
                    rightContext: rightContext
                )
                let repeatScore = computeSemanticAffinityRules(
                    candidate: "再",
                    reading: "ㄗㄞˋ",
                    leftContext: leftContext + "不",
                    rightContext: rightContext
                )
                if val == "不再" && zaiScore - repeatScore >= 15.0 {
                    if !feedbackStore.isRejected(reading: reading, candidate: "不在", leftContext: leftContext) {
                        out[i] = "不在"
                        continue
                    }
                } else if val == "不在" && repeatScore - zaiScore >= 15.0 {
                    if !feedbackStore.isRejected(reading: reading, candidate: "不再", leftContext: leftContext) {
                        out[i] = "不再"
                        continue
                    }
                }
            }

            if (val == "先在" || val == "先再") && (reading.isEmpty || reading == "ㄒㄧㄢ-ㄗㄞˋ") {
                let zaiScore = computeSemanticAffinityRules(
                    candidate: "在",
                    reading: "ㄗㄞˋ",
                    leftContext: leftContext + "先",
                    rightContext: rightContext
                )
                let repeatScore = computeSemanticAffinityRules(
                    candidate: "再",
                    reading: "ㄗㄞˋ",
                    leftContext: leftContext + "先",
                    rightContext: rightContext
                )
                if val == "先再" && zaiScore - repeatScore >= 15.0 {
                    if !feedbackStore.isRejected(reading: reading, candidate: "先在", leftContext: leftContext) {
                        out[i] = "先在"
                        continue
                    }
                } else if val == "先在" && repeatScore - zaiScore >= 15.0 {
                    if !feedbackStore.isRejected(reading: reading, candidate: "先再", leftContext: leftContext) {
                        out[i] = "先再"
                        continue
                    }
                }
            }

            // 3. 雙字節點「帶著 <-> 戴著」修正
            if (val == "帶著" || val == "戴著") && (reading.isEmpty || reading.hasPrefix("ㄉㄞˋ-")) {
                let wearScore = computeSemanticAffinityRules(
                    candidate: "戴",
                    reading: "ㄉㄞˋ",
                    leftContext: leftContext,
                    rightContext: "著" + rightContext
                )
                let carryScore = computeSemanticAffinityRules(
                    candidate: "帶",
                    reading: "ㄉㄞˋ",
                    leftContext: leftContext,
                    rightContext: "著" + rightContext
                )
                if val == "帶著" && wearScore - carryScore >= 15.0 {
                    if !feedbackStore.isRejected(reading: reading, candidate: "戴著", leftContext: leftContext) {
                        out[i] = "戴著"
                        continue
                    }
                } else if val == "戴著" && carryScore - wearScore >= 15.0 {
                    if !feedbackStore.isRejected(reading: reading, candidate: "帶著", leftContext: leftContext) {
                        out[i] = "帶著"
                        continue
                    }
                }
            }

            // 4. 單字節點「在 <-> 再」「的 <-> 地 <-> 得」「帶 <-> 戴」修正
            if val == "在" || val == "再" {
                let other = (val == "在") ? "再" : "在"
                let currScore = computeSemanticAffinityRules(candidate: val, reading: reading, leftContext: leftContext, rightContext: rightContext)
                let otherScore = computeSemanticAffinityRules(candidate: other, reading: reading, leftContext: leftContext, rightContext: rightContext)
                if otherScore - currScore >= 15.0 && !feedbackStore.isRejected(reading: reading, candidate: other, leftContext: leftContext) {
                    out[i] = other
                }
            } else if val == "的" || val == "地" || val == "得" {
                var bestP = val
                var bestS = computeSemanticAffinityRules(candidate: val, reading: reading, leftContext: leftContext, rightContext: rightContext)
                for alt in ["的", "地", "得"] where alt != val {
                    let s = computeSemanticAffinityRules(candidate: alt, reading: reading, leftContext: leftContext, rightContext: rightContext)
                    if s - bestS >= 15.0 && !feedbackStore.isRejected(reading: reading, candidate: alt, leftContext: leftContext) {
                        bestS = s
                        bestP = alt
                    }
                }
                out[i] = bestP
            } else if val == "帶" || val == "戴" {
                let other = (val == "帶") ? "戴" : "帶"
                let currScore = computeSemanticAffinityRules(candidate: val, reading: reading, leftContext: leftContext, rightContext: rightContext)
                let otherScore = computeSemanticAffinityRules(candidate: other, reading: reading, leftContext: leftContext, rightContext: rightContext)
                if otherScore - currScore >= 15.0 && !feedbackStore.isRejected(reading: reading, candidate: other, leftContext: leftContext) {
                    out[i] = other
                }
            } else if val == "反應" || val == "反映" {
                let other = (val == "反應") ? "反映" : "反應"
                let currScore = computeSemanticAffinityRules(candidate: val, reading: reading, leftContext: leftContext, rightContext: rightContext)
                let otherScore = computeSemanticAffinityRules(candidate: other, reading: reading, leftContext: leftContext, rightContext: rightContext)
                if otherScore - currScore >= 15.0 && !feedbackStore.isRejected(reading: reading, candidate: other, leftContext: leftContext) {
                    out[i] = other
                }
            } else if val == "茸" && (rightContext.hasPrefix("於") || rightContext.hasPrefix("餘")) {
                if !feedbackStore.isRejected(reading: reading, candidate: "冗", leftContext: leftContext) {
                    out[i] = "冗"
                }
            } else if val == "於" && (leftContext.hasSuffix("茸") || leftContext.hasSuffix("冗")) {
                if !feedbackStore.isRejected(reading: reading, candidate: "餘", leftContext: leftContext) {
                    out[i] = "餘"
                }
            } else if val == "策" && rightContext.hasPrefix("試") {
                if !feedbackStore.isRejected(reading: reading, candidate: "測", leftContext: leftContext) {
                    out[i] = "測"
                }
            } else if val == "國" && leftContext.hasSuffix("蘋") && rightContext.hasPrefix("汁") {
                if !feedbackStore.isRejected(reading: reading, candidate: "果", leftContext: leftContext) {
                    out[i] = "果"
                }
            } else if val == "果" && rightContext.hasPrefix("家") {
                if !feedbackStore.isRejected(reading: reading, candidate: "國", leftContext: leftContext) {
                    out[i] = "國"
                }
            }
        }

        return out
    }

    /// 計算整句的規則加權（已縮放至 [-maxTotalRuleBias, +maxTotalRuleBias]）
    private func computeSentenceRuleBias(nodeValues: [String], nodeReadings: [String]) -> Double {
        var totalRaw = 0.0
        for i in 0..<nodeValues.count {
            let leftContext = i > 0 ? nodeValues[0..<i].joined() : ""
            let rightContext = (i + 1 < nodeValues.count) ? nodeValues[(i + 1)..<nodeValues.count].joined() : ""
            let reading = i < nodeReadings.count ? nodeReadings[i] : ""
            let val = nodeValues[i]

            totalRaw += computeSemanticAffinityRules(
                candidate: val,
                reading: reading,
                leftContext: leftContext,
                rightContext: rightContext
            )

            // 若是雙字/多字節點，也評估其內部關鍵同音字與左右文的搭配
            if val.count >= 2 && val.hasSuffix("地") {
                let prefix = String(val.dropLast())
                totalRaw += computeSemanticAffinityRules(
                    candidate: "地",
                    reading: "ㄉㄜ˙",
                    leftContext: leftContext + prefix,
                    rightContext: rightContext
                )
            } else if val.count >= 2 && val.hasSuffix("的") {
                let prefix = String(val.dropLast())
                totalRaw += computeSemanticAffinityRules(
                    candidate: "的",
                    reading: "ㄉㄜ˙",
                    leftContext: leftContext + prefix,
                    rightContext: rightContext
                )
            } else if val == "不在" || val == "不再" {
                let secondChar = String(val.suffix(1))
                totalRaw += computeSemanticAffinityRules(
                    candidate: secondChar,
                    reading: "ㄗㄞˋ",
                    leftContext: leftContext + "不",
                    rightContext: rightContext
                )
            } else if val == "先在" || val == "先再" {
                let secondChar = String(val.suffix(1))
                totalRaw += computeSemanticAffinityRules(
                    candidate: secondChar,
                    reading: "ㄗㄞˋ",
                    leftContext: leftContext + "先",
                    rightContext: rightContext
                )
            } else if val == "戴著" || val == "帶著" {
                let firstChar = String(val.prefix(1))
                totalRaw += computeSemanticAffinityRules(
                    candidate: firstChar,
                    reading: "ㄉㄞˋ",
                    leftContext: leftContext,
                    rightContext: "著" + rightContext
                )
            }
        }
        let scaled = totalRaw * 0.015
        return max(-config.maxTotalRuleBias, min(config.maxTotalRuleBias, scaled))
    }

    // MARK: - 語意搭配規則表 (供 computeSentenceRuleBias 與 refineNodesWithSentenceRules 縮放使用)

    public func computeSemanticAffinityRules(
        candidate: String,
        reading: String,
        leftContext: String,
        rightContext: String
    ) -> Double {
        var boost = 0.0

        // 規則 1：穿戴動詞「戴」vs 攜帶動詞「帶」
        let wearObjects = ["口罩", "眼鏡", "耳機", "帽子", "安全帽", "手錶", "戒指", "項鍊", "假髮", "隱形眼鏡", "頭盔", "手套", "護具"]
        let carryObjects = ["伴手禮", "雨傘", "傘", "錢包", "鑰匙", "手機", "行李", "便當", "禮物", "水壺", "護照", "微笑", "笑容", "孩子", "小孩"]
        let carryComplements = ["走", "來", "去", "回", "上", "下", "出", "進", "動", "領", "頭"]
        let wearComplements = ["上", "好", "著", "起"]

        let rightStrippedZhe = rightContext.hasPrefix("著") ? String(rightContext.dropFirst()) : rightContext

        if candidate == "戴" {
            for obj in wearObjects {
                if leftContext.hasSuffix(obj) || rightContext.hasPrefix(obj) || rightStrippedZhe.hasPrefix(obj) {
                    boost += 25.0
                }
            }
            for comp in wearComplements {
                if rightContext.hasPrefix(comp) && wearObjects.contains(where: { leftContext.contains($0) }) {
                    boost += 15.0
                }
            }
            for obj in carryObjects {
                if leftContext.hasSuffix(obj) || rightContext.hasPrefix(obj) || rightStrippedZhe.hasPrefix(obj) {
                    boost -= 20.0
                }
            }
        } else if candidate == "帶" {
            for obj in carryObjects {
                if leftContext.hasSuffix(obj) || rightContext.hasPrefix(obj) || rightStrippedZhe.hasPrefix(obj) {
                    boost += 25.0
                }
            }
            for comp in carryComplements {
                if rightContext.hasPrefix(comp) && !wearObjects.contains(where: { leftContext.contains($0) }) {
                    boost += 18.0
                }
            }
            for obj in wearObjects {
                if leftContext.hasSuffix(obj) || rightContext.hasPrefix(obj) || rightStrippedZhe.hasPrefix(obj) {
                    boost -= 20.0
                }
            }
        }

        // 規則 2：結構助詞「的 / 得 / 地」
        let degreeMarkers = ["很", "太", "真", "好", "快", "慢", "高", "低", "遠", "近", "多", "少", "早", "晚", "棒", "糟", "美", "慘", "清楚", "乾淨", "開心", "高興", "要命", "不得了", "不亦樂乎", "起勁", "出色", "完美", "徹底", "非常"]
        let commonVerbsBeforeDe = ["跑", "走", "飛", "跳", "游", "開", "騎", "寫", "說", "唱", "跳", "看", "聽", "做", "弄", "搞", "吃", "喝", "睡", "笑", "哭", "長", "變", "覺", "記", "懂", "認", "算", "拿", "抓", "打", "罵", "洗", "擦", "收", "來", "去", "起", "進", "出", "回", "過", "買", "賣", "學", "教", "玩", "累", "氣", "急", "嚇", "樂", "痛", "熱", "冷", "忙", "慌", "餓", "渴"]
        let adverbialModifiers = ["慢慢", "快快", "悄悄", "靜靜", "默默", "漸漸", "緊緊", "深深", "遠遠", "早早", "乖乖", "好好", "輕輕", "重重", "暗暗", "狠狠", "牢牢", "穩穩", "細細", "苦苦", "傻傻", "呆呆", "大聲", "小聲", "用力", "努力", "認真", "仔細", "小心", "專心", "耐心", "開心", "傷心", "放心", "安心", "甘心", "大膽", "勇敢", "熱情", "冷靜", "溫柔", "禮貌", "客氣", "順利", "成功", "迅速", "緩慢", "徹底", "完全", "正式", "公開", "私下", "偷偷", "不斷", "持續", "積極", "主動", "被動", "無奈", "驚訝", "憤怒", "焦急", "興奮", "驕傲", "謙虛", "誠實", "坦白", "果斷", "堅定", "明確", "清楚", "詳細", "簡單", "隨便", "敷衍", "勉強"]
        let actionVerbsAfterDi = ["走", "跑", "說", "看", "聽", "寫", "做", "吃", "笑", "哭", "問", "答", "想", "看", "望", "盯", "瞧", "喊", "叫", "唱", "跳", "飛", "游", "爬", "坐", "站", "躺", "睡", "開", "關", "推", "拉", "拿", "放", "抱", "握", "抓", "摸", "拍", "打", "踢", "咬", "吞", "喝", "吸", "吹", "吐", "穿", "脫", "戴", "洗", "擦", "刷", "掃", "收", "撿", "丟", "扔", "找", "尋", "查", "檢", "讀", "念", "背", "記", "學", "練", "教", "幫", "助", "救", "護", "守", "等", "待", "迎", "送", "追", "趕", "逃", "躲", "藏", "進", "出", "上", "下", "回", "過", "起", "落", "升", "降", "轉", "變", "改", "換", "修", "建", "造", "畫", "拍", "錄", "播", "傳", "寄", "買", "賣", "付", "賠", "賺", "存", "借", "還", "工作", "學習", "思考", "討論", "研究", "檢查", "觀察", "回答", "解釋", "說明", "宣布", "發起", "推動", "執行", "完成", "結束", "開始", "繼續", "保持", "維持", "離開", "解決", "決定"]

        let nounPrefixesExcludedFromAction = ["笑容", "笑臉", "笑話", "笑聲", "說明書", "工作室", "工作人員", "工作證", "研究所", "研究員", "檢查表", "檢查報告", "觀察家", "表演者", "創作者", "使用者"]
        let isRightNounException = nounPrefixesExcludedFromAction.contains { rightContext.hasPrefix($0) }

        if candidate == "得" {
            let leftIsVerb = commonVerbsBeforeDe.contains { leftContext.hasSuffix($0) }
            let rightIsDegree = degreeMarkers.contains { rightContext.hasPrefix($0) }
            if leftIsVerb && rightIsDegree {
                boost += 28.0
            } else if rightIsDegree {
                boost += 18.0
            } else if ["到", "出", "起", "上", "下", "了", "過", "住", "開", "來", "去"].contains(where: { rightContext.hasPrefix($0) }) && leftIsVerb {
                boost += 16.0
            }
        } else if candidate == "地" {
            let leftIsAA = leftContext.count >= 2 && leftContext.suffix(1) == leftContext.dropLast().suffix(1)
            let leftIsAdverb = leftIsAA || adverbialModifiers.contains { leftContext.hasSuffix($0) }
            let rightIsAction = !isRightNounException && actionVerbsAfterDi.contains { rightContext.hasPrefix($0) }
            if leftIsAdverb && rightIsAction {
                boost += 28.0
            }
        } else if candidate == "的" {
            let leftIsVerb = commonVerbsBeforeDe.contains { leftContext.hasSuffix($0) }
            let rightIsDegree = degreeMarkers.contains { rightContext.hasPrefix($0) }
            if leftIsVerb && rightIsDegree {
                boost -= 22.0
            }
            let leftIsAA = leftContext.count >= 2 && leftContext.suffix(1) == leftContext.dropLast().suffix(1)
            let leftIsAdverb = leftIsAA || adverbialModifiers.contains { leftContext.hasSuffix($0) }
            let rightIsAction = !isRightNounException && actionVerbsAfterDi.contains { rightContext.hasPrefix($0) }
            if leftIsAdverb && rightIsAction {
                boost -= 22.0
            }
            if !leftIsVerb && !rightIsDegree && !rightIsAction {
                boost += 20.0
            }
        }

        // 規則 3：「在」vs「再」
        let locationNouns = ["家", "學校", "公司", "辦公室", "店", "餐廳", "醫院", "車站", "機場", "公園", "圖書館", "教室", "會議室", "房間", "客廳", "廚房", "廁所", "浴室", "床", "桌", "椅", "車", "船", "飛機", "路", "街", "巷", "門", "窗", "牆", "地", "天", "海", "山", "水", "林", "場", "館", "院", "局", "處", "部", "科", "室", "組", "中心", "平台", "網站", "網路", "線上", "現場", "心裡", "心中", "腦海", "眼裡", "手裡", "手中", "身上", "身旁", "身邊", "背後", "前面", "後面", "上面", "下面", "裡面", "外面", "左邊", "右邊", "中間", "旁邊", "附近", "周圍", "這裡", "那裡", "哪裡", "這兒", "那兒", "哪兒", "台灣", "台北", "台中", "台南", "高雄", "新北", "桃園", "新竹", "日本", "美國", "世界", "國際", "國內", "國外", "表單", "表格", "文件", "合約", "紙上", "螢幕", "黑板", "白板"]
        let prepositionsBeforeLocation = ["放", "留", "住", "坐", "站", "躺", "睡", "停", "擺", "掛", "貼", "寫", "畫", "印", "刻", "埋", "藏", "躲", "困", "卡", "掉", "落", "留", "待", "生", "長", "死", "工作", "讀書", "上課", "上班", "開會", "吃飯", "休息", "生活", "居住", "出現", "發生", "進行", "舉行", "舉辦"]
        let repeatAdverbLeft = [
            "明天", "後天", "下次", "下回", "改天", "稍後", "晚點", "等一下", "待會", "待會兒", "等會", "等會兒", "等等", "稍候", "過會兒",
            "回頭", "以後", "之後", "然後", "接著", "緊接著", "不妨", "不如", "乾脆", "索性", "只好", "只能",
            "必須", "應該", "可以", "需要", "想要", "想", "要", "會", "能", "敢", "肯", "願",
            "別", "勿", "莫", "不要", "不用", "不必", "不可", "不能", "不會", "不再", "一", "又", "還", "先"
        ]
        let repeatActionRight = [
            "說", "講", "看", "聽", "想", "考慮", "決定", "討論", "研究", "商量", "聯絡", "聯繫", "通知", "告訴",
            "確認", "檢查", "測試", "試", "做", "弄", "搞", "寫", "改", "修", "寄", "發", "傳", "送", "交", "給",
            "打", "打給", "打電話", "撥", "撥給", "回電", "回覆", "回信", "見面", "碰面",
            "買", "賣", "吃", "喝", "玩", "去", "來", "回", "走", "跑", "見", "聚", "聊", "約",
            "問", "答", "找", "查", "加", "減", "添", "補", "續", "次", "回", "遍", "番", "三", "度", "生", "造", "現", "見", "一起"
        ]

        if candidate == "在" {
            let rightIsLocation = locationNouns.contains { rightContext.hasPrefix($0) }
                || ((rightContext.hasPrefix("他") || rightContext.hasPrefix("她") || rightContext.hasPrefix("我") || rightContext.hasPrefix("你") || rightContext.hasPrefix("這") || rightContext.hasPrefix("那"))
                    && locationNouns.contains { rightContext.dropFirst().hasPrefix($0) })
            let leftIsLocVerb = prepositionsBeforeLocation.contains { leftContext.hasSuffix($0) }

            if rightIsLocation {
                boost += 26.0
            }
            if leftIsLocVerb && rightIsLocation {
                boost += 15.0
            }
            if leftContext.hasSuffix("不") && rightIsLocation {
                boost += 30.0
            }
            if leftContext.hasSuffix("先") && rightIsLocation {
                boost += 28.0
            }
            if ["正", "還", "仍", "都", "也", "就", "只", "全"].contains(where: { leftContext.hasSuffix($0) }) && rightIsLocation {
                boost += 15.0
            }
            if leftContext.hasSuffix("一") && (rightContext.hasPrefix("強調") || rightContext.hasPrefix("提醒") || rightContext.hasPrefix("要求") || rightContext.hasPrefix("表示") || rightContext.hasPrefix("發生") || rightContext.hasPrefix("出現")) {
                boost -= 28.0
            }
        } else if candidate == "再" {
            let rightIsLocation = locationNouns.contains { rightContext.hasPrefix($0) }
                || ((rightContext.hasPrefix("他") || rightContext.hasPrefix("她") || rightContext.hasPrefix("我") || rightContext.hasPrefix("你") || rightContext.hasPrefix("這") || rightContext.hasPrefix("那"))
                    && locationNouns.contains { rightContext.dropFirst().hasPrefix($0) })

            if rightIsLocation {
                boost -= 26.0
            } else {
                let leftIsRepeat = repeatAdverbLeft.contains { leftContext.hasSuffix($0) }
                let rightIsRepeatVerb = repeatActionRight.contains { rightContext.hasPrefix($0) }
                if leftIsRepeat && rightIsRepeatVerb {
                    boost += 26.0
                } else if rightContext.contains("一次") || rightContext.contains("一遍") || rightContext.contains("一回") || rightContext.contains("一下") {
                    boost += 24.0
                } else if leftContext.hasSuffix("一") && !rightIsLocation {
                    boost += 24.0
                }
            }
        }

        // 規則 4：「反映」vs「反應」
        if candidate == "反映" {
            if ["意見", "問題", "情況", "心聲", "民意", "現況", "事實", "真實", "出", "給", "向", "客觀"].contains(where: { rightContext.hasPrefix($0) || leftContext.hasSuffix($0) }) {
                boost += 25.0
            }
        } else if candidate == "反應" {
            if ["化學", "過度", "連鎖", "不良", "過敏", "生理", "本能", "速度", "時間", "能力", "熱烈", "冷淡", "激烈", "很大", "很快", "很慢", "過來"].contains(where: { leftContext.hasSuffix($0) || rightContext.hasPrefix($0) }) {
                boost += 25.0
            }
        }

        // 規則 5：其他常見雙字同音詞（「冗餘」、「測試」、「果/國」）
        if candidate == "冗" && (rightContext.hasPrefix("餘") || rightContext.hasPrefix("於")) {
            boost += 30.0
        } else if candidate == "餘" && (leftContext.hasSuffix("冗") || leftContext.hasSuffix("茸")) {
            boost += 30.0
        } else if candidate == "測" && rightContext.hasPrefix("試") {
            boost += 28.0
        } else if candidate == "果" && (leftContext.hasSuffix("蘋") || rightContext.hasPrefix("汁") || leftContext.hasSuffix("水")) {
            boost += 28.0
        } else if candidate == "國" && (rightContext.hasPrefix("家") || rightContext.hasPrefix("際") || rightContext.hasPrefix("內") || rightContext.hasPrefix("外")) {
            boost += 28.0
        }

        return boost
    }
}
