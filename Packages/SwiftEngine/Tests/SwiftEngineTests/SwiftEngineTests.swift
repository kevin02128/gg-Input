import XCTest
@testable import SwiftEngine

final class SwiftEngineTests: XCTestCase {

    final class SimpleLM: LanguageModel {
        var db: [String: [Unigram]] = [:]

        init(sample: String) {
            let lines = sample.split(separator: "\n")
            for line in lines {
                let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmed.isEmpty || trimmed.hasPrefix("#") {
                    continue
                }
                let parts = trimmed.split(separator: " ")
                if parts.count >= 3 {
                    let reading = String(parts[0])
                    let val = String(parts[1])
                    let score = Double(parts[2]) ?? 0.0
                    db[reading, default: []].append(Unigram(value: val, score: score))
                }
            }
        }

        func getUnigrams(reading: String) -> [Unigram] {
            db[reading] ?? []
        }

        func hasUnigrams(reading: String) -> Bool {
            db[reading] != nil
        }
    }

    let sampleData = """
    ㄙ 絲 -9.495858
    ㄙ 思 -9.006414
    ㄍㄠ 高 -7.171551
    ㄍㄠ 膏 -11.928720
    ㄎㄜ 顆 -10.574273
    ㄎㄜ 科 -7.171052
    ㄐㄧˋ 際 -7.608341
    ㄐㄧˋ 技 -8.450826
    ㄍㄨㄥㄙ 公司 -6.299461
    ㄎㄜㄐㄧˋ 科技 -6.736613
    ㄍㄠㄎㄜㄐㄧˋ 高科技 -9.842421
    """

    func testSpan() {
        let lm = SimpleLM(sample: sampleData)
        let span = ReadingGrid.Span()

        let n1 = ReadingGrid.Node(reading: "ㄍㄠ", spanningLength: 1, unigrams: lm.getUnigrams(reading: "ㄍㄠ"))
        let n3 = ReadingGrid.Node(reading: "ㄍㄠㄎㄜㄐㄧˋ", spanningLength: 3, unigrams: lm.getUnigrams(reading: "ㄍㄠㄎㄜㄐㄧˋ"))

        XCTAssertEqual(span.maxLength, 0)
        span.add(n1)
        XCTAssertEqual(span.maxLength, 1)
        span.add(n3)
        XCTAssertEqual(span.maxLength, 3)

        XCTAssertTrue(span.nodeOf(length: 1) === n1)
        XCTAssertNil(span.nodeOf(length: 2))
        XCTAssertTrue(span.nodeOf(length: 3) === n3)

        span.clear()
        XCTAssertEqual(span.maxLength, 0)
        XCTAssertNil(span.nodeOf(length: 1))

        span.add(n1)
        span.add(n3)
        span.removeNodesOfOrLongerThan(length: 2)
        XCTAssertEqual(span.maxLength, 1)
        XCTAssertTrue(span.nodeOf(length: 1) === n1)
    }

    func testReadingGridBasicWalk() {
        let lm = SimpleLM(sample: sampleData)
        let grid = ReadingGrid(languageModel: lm)
        grid.readingSeparator = ""

        _ = grid.insertReading("ㄍㄠ")
        _ = grid.insertReading("ㄎㄜ")
        _ = grid.insertReading("ㄐㄧˋ")

        let walkResult = grid.walk()
        XCTAssertEqual(walkResult.totalReadings, 3)
        XCTAssertEqual(walkResult.valuesAsStrings, ["高科技"])
    }

    final class MockLM: LanguageModel {
        func getUnigrams(reading: String) -> [Unigram] {
            [Unigram(value: reading, score: -1.0)]
        }
        func hasUnigrams(reading: String) -> Bool {
            true
        }
    }

    final class ContextualLM: LanguageModel {
        private let unigrams: [String: [Unigram]]
        private let associations: [UInt64: Double]

        init(unigrams: [String: [Unigram]], associations: [UInt64: Double]) {
            self.unigrams = unigrams
            self.associations = associations
        }

        func getUnigrams(reading: String) -> [Unigram] {
            unigrams[reading] ?? []
        }

        func hasUnigrams(reading: String) -> Bool {
            unigrams[reading] != nil
        }

        func characterBigramAssociationScore(previous: UInt32, next: UInt32) -> Double {
            associations[(UInt64(previous) << 32) | UInt64(next)] ?? 0.0
        }
    }

    func testMultipleSpans() {
        let grid = ReadingGrid(languageModel: MockLM())
        grid.readingSeparator = ";"
        _ = grid.insertReading("a")
        _ = grid.insertReading("b")
        _ = grid.insertReading("c")

        XCTAssertEqual(grid.cursor, 3)
        XCTAssertEqual(grid.length, 3)
        XCTAssertEqual(grid.spans.count, 3)
        XCTAssertEqual(grid.spans[0].maxLength, 3)
        XCTAssertEqual(grid.spans[0].nodeOf(length: 1)?.reading, "a")
        XCTAssertEqual(grid.spans[0].nodeOf(length: 2)?.reading, "a;b")
        XCTAssertEqual(grid.spans[0].nodeOf(length: 3)?.reading, "a;b;c")
        XCTAssertEqual(grid.spans[1].maxLength, 2)
        XCTAssertEqual(grid.spans[1].nodeOf(length: 1)?.reading, "b")
        XCTAssertEqual(grid.spans[1].nodeOf(length: 2)?.reading, "b;c")
        XCTAssertEqual(grid.spans[2].maxLength, 1)
        XCTAssertEqual(grid.spans[2].nodeOf(length: 1)?.reading, "c")
    }

    func testSpanDeletionSimple() {
        let grid = ReadingGrid(languageModel: MockLM())
        grid.readingSeparator = ";"
        _ = grid.insertReading("a")
        _ = grid.insertReading("b")
        _ = grid.insertReading("c")
        XCTAssertTrue(grid.deleteReadingBeforeCursor())
        XCTAssertEqual(grid.cursor, 2)
        XCTAssertEqual(grid.length, 2)
        XCTAssertEqual(grid.spans.count, 2)
        XCTAssertEqual(grid.spans[0].maxLength, 2)
        XCTAssertEqual(grid.spans[0].nodeOf(length: 1)?.reading, "a")
        XCTAssertEqual(grid.spans[0].nodeOf(length: 2)?.reading, "a;b")
        XCTAssertEqual(grid.spans[1].maxLength, 1)
        XCTAssertEqual(grid.spans[1].nodeOf(length: 1)?.reading, "b")
    }

    func testSpanDeletionFromMiddle() {
        let grid = ReadingGrid(languageModel: MockLM())
        grid.readingSeparator = ";"
        _ = grid.insertReading("a")
        _ = grid.insertReading("b")
        _ = grid.insertReading("c")
        grid.setCursor(2)
        XCTAssertTrue(grid.deleteReadingBeforeCursor())
        XCTAssertEqual(grid.cursor, 1)
        XCTAssertEqual(grid.length, 2)
        XCTAssertEqual(grid.spans.count, 2)
        XCTAssertEqual(grid.spans[0].maxLength, 2)
        XCTAssertEqual(grid.spans[0].nodeOf(length: 1)?.reading, "a")
        XCTAssertEqual(grid.spans[0].nodeOf(length: 2)?.reading, "a;c")
        XCTAssertEqual(grid.spans[1].maxLength, 1)
        XCTAssertEqual(grid.spans[1].nodeOf(length: 1)?.reading, "c")
    }

    func testSpanDeletionFromMiddleUsingDeleteAfterCursor() {
        let grid = ReadingGrid(languageModel: MockLM())
        grid.readingSeparator = ";"
        _ = grid.insertReading("a")
        _ = grid.insertReading("b")
        _ = grid.insertReading("c")
        grid.setCursor(1)
        XCTAssertTrue(grid.deleteReadingAfterCursor())
        XCTAssertEqual(grid.cursor, 1)
        XCTAssertEqual(grid.length, 2)
        XCTAssertEqual(grid.spans.count, 2)
        XCTAssertEqual(grid.spans[0].maxLength, 2)
        XCTAssertEqual(grid.spans[0].nodeOf(length: 1)?.reading, "a")
        XCTAssertEqual(grid.spans[0].nodeOf(length: 2)?.reading, "a;c")
        XCTAssertEqual(grid.spans[1].maxLength, 1)
        XCTAssertEqual(grid.spans[1].nodeOf(length: 1)?.reading, "c")
    }

    func testSpanInsertion() {
        let grid = ReadingGrid(languageModel: MockLM())
        grid.readingSeparator = ";"
        _ = grid.insertReading("a")
        _ = grid.insertReading("b")
        _ = grid.insertReading("c")
        grid.setCursor(1)
        XCTAssertTrue(grid.insertReading("X"))

        XCTAssertEqual(grid.cursor, 2)
        XCTAssertEqual(grid.length, 4)
        XCTAssertEqual(grid.spans.count, 4)
        XCTAssertEqual(grid.spans[0].maxLength, 4)
        XCTAssertEqual(grid.spans[0].nodeOf(length: 1)?.reading, "a")
        XCTAssertEqual(grid.spans[0].nodeOf(length: 2)?.reading, "a;X")
        XCTAssertEqual(grid.spans[0].nodeOf(length: 3)?.reading, "a;X;b")
        XCTAssertEqual(grid.spans[0].nodeOf(length: 4)?.reading, "a;X;b;c")
        XCTAssertEqual(grid.spans[1].maxLength, 3)
        XCTAssertEqual(grid.spans[1].nodeOf(length: 1)?.reading, "X")
        XCTAssertEqual(grid.spans[1].nodeOf(length: 2)?.reading, "X;b")
        XCTAssertEqual(grid.spans[1].nodeOf(length: 3)?.reading, "X;b;c")
        XCTAssertEqual(grid.spans[2].maxLength, 2)
        XCTAssertEqual(grid.spans[2].nodeOf(length: 1)?.reading, "b")
        XCTAssertEqual(grid.spans[2].nodeOf(length: 2)?.reading, "b;c")
        XCTAssertEqual(grid.spans[3].maxLength, 1)
        XCTAssertEqual(grid.spans[3].nodeOf(length: 1)?.reading, "c")
    }

    func testCandidateOverride() {
        let lm = SimpleLM(sample: sampleData)
        let grid = ReadingGrid(languageModel: lm)
        grid.readingSeparator = ""

        _ = grid.insertReading("ㄎㄜ")
        _ = grid.insertReading("ㄐㄧˋ")

        var walkResult = grid.walk()
        XCTAssertEqual(walkResult.valuesAsStrings, ["科技"])

        let candidates = grid.candidatesAt(loc: 0)
        XCTAssertTrue(candidates.contains(where: { $0.value == "科技" }))
        XCTAssertTrue(candidates.contains(where: { $0.value == "科" }))

        XCTAssertTrue(grid.overrideCandidate(loc: 0, candidateValue: "顆"))
        walkResult = grid.walk()
        XCTAssertEqual(walkResult.valuesAsStrings.first, "顆")
    }

    func testBopomofoBuffer() {
        let buffer = BopomofoBuffer()
        XCTAssertTrue(buffer.isEmpty)

        // Type 'd' -> ㄎ
        XCTAssertTrue(buffer.combineKey("d"))
        XCTAssertEqual(buffer.reading, "ㄎ")
        XCTAssertFalse(buffer.hasToneMarker)

        // Type 'k' -> ㄜ
        XCTAssertTrue(buffer.combineKey("k"))
        XCTAssertEqual(buffer.reading, "ㄎㄜ")
        XCTAssertFalse(buffer.hasToneMarker)

        // Type '3' -> 3rd tone (ˇ)
        XCTAssertTrue(buffer.combineKey("3"))
        XCTAssertEqual(buffer.reading, "ㄎㄜˇ")
        XCTAssertTrue(buffer.hasToneMarker)
        XCTAssertFalse(buffer.hasToneMarkerOnly)

        // Test Hanyu Pinyin conversion
        XCTAssertEqual(buffer.syllable.toHanyuPinyin(), "ke")
        XCTAssertEqual(buffer.syllable.toHanyuPinyin(includesTone: true), "ke3")

        // Test backspace
        buffer.backspace()
        XCTAssertEqual(buffer.reading, "ㄎㄜ")
        XCTAssertFalse(buffer.hasToneMarker)
        buffer.backspace()
        XCTAssertEqual(buffer.reading, "ㄎ")
        buffer.backspace()
        XCTAssertTrue(buffer.isEmpty)

        // Test overwrite and backspace behavior
        buffer.clear()
        XCTAssertTrue(buffer.combineKey("1")) // ㄅ
        XCTAssertEqual(buffer.reading, "ㄅ")
        XCTAssertTrue(buffer.combineKey("q")) // Overwrite with ㄆ
        XCTAssertEqual(buffer.reading, "ㄆ")
        buffer.backspace()
        XCTAssertTrue(buffer.isEmpty, "Single backspace after overwriting consonant must completely clear syllable")

        buffer.clear()
        XCTAssertTrue(buffer.combineKey("1")) // ㄅ
        XCTAssertTrue(buffer.combineKey("1")) // Repeated ㄅ
        XCTAssertEqual(buffer.reading, "ㄅ")
        buffer.backspace()
        XCTAssertTrue(buffer.isEmpty, "Single backspace after repeated keystroke must clear consonant in one press")
    }

    func testHanyuPinyinConversions() {
        // 台灣人最需要的就是消波塊
        let s1 = BopomofoSyllable.fromComposed(string: "ㄊㄞˊ")
        XCTAssertEqual(s1.toHanyuPinyin(), "tai")

        let s2 = BopomofoSyllable.fromComposed(string: "ㄨㄢ")
        XCTAssertEqual(s2.toHanyuPinyin(), "wan")

        let s3 = BopomofoSyllable.fromComposed(string: "ㄖㄣˊ")
        XCTAssertEqual(s3.toHanyuPinyin(), "ren")

        let s4 = BopomofoSyllable.fromComposed(string: "ㄓㄨㄥ")
        XCTAssertEqual(s4.toHanyuPinyin(), "zhong")

        let s5 = BopomofoSyllable.fromComposed(string: "ㄑㄩ")
        XCTAssertEqual(s5.toHanyuPinyin(), "qu")
    }

    private var repoRootURL: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    func testPhraseDBWithRealData() {
        let db = PhraseDB()
        let path = repoRootURL.appendingPathComponent("Source/Data/data.txt").path
        guard FileManager.default.fileExists(atPath: path) else {
            return
        }

        XCTAssertTrue(db.open(path: path))
        XCTAssertTrue(db.isLoaded)

        let unigrams = db.getUnigrams(reading: "ㄎㄜ-ㄐㄧˋ")
        XCTAssertFalse(unigrams.isEmpty)
        XCTAssertTrue(unigrams.contains(where: { $0.value == "科技" }))

        let reversed = db.reverseFindRows(value: "科技")
        XCTAssertTrue(reversed.contains(where: { $0.reading == "ㄎㄜ-ㄐㄧˋ" }))
    }

    func testEngineLMWithAssociatedPhrases() {
        let lm = EngineLM()
        let dataPath = repoRootURL.appendingPathComponent("Source/Data/data.txt").path
        let assocPath = repoRootURL.appendingPathComponent("Source/Data/associated-phrases-v2.txt").path
        guard FileManager.default.fileExists(atPath: dataPath),
              FileManager.default.fileExists(atPath: assocPath) else {
            return
        }

        XCTAssertTrue(lm.loadLanguageModel(path: dataPath))
        XCTAssertTrue(lm.loadAssociatedPhrases(path: assocPath))

        // Find associated phrases for "輸入" with readings ["ㄕㄨ", "ㄖㄨˋ"]
        let phrases = lm.findAssociatedPhrases(prefixValue: "輸入", prefixReadings: ["ㄕㄨ", "ㄖㄨˋ"])
        XCTAssertFalse(phrases.isEmpty)
        XCTAssertTrue(phrases.contains(where: { $0.value.hasPrefix("輸入") }))
    }

    func testUserReportedSelectionsDictionaryOnlyBaseline() throws {
        let dataPath = repoRootURL.appendingPathComponent("Source/Data/data.txt").path
        guard FileManager.default.fileExists(atPath: dataPath) else {
            throw XCTSkip("Compiled dictionary data.txt is unavailable")
        }

        let lm = EngineLM()
        XCTAssertTrue(lm.loadLanguageModel(path: dataPath))

        let cases: [(String, [String], String)] = [
            ("umbrella", ["ㄉㄞˋ", "ㄧ", "ㄅㄚˇ", "ㄩˇ", "ㄙㄢˇ"], "帶一把雨傘"),
            ("raincoat", ["ㄒㄧㄚˋ", "ㄩˇ", "ㄊㄧㄢ", "ㄧㄠˋ", "ㄔㄨㄢ", "ㄩˇ", "ㄧ"], "下雨天要穿雨衣"),
            ("help-me", ["ㄐㄧㄡˋ", "ㄐㄧㄡˋ", "ㄨㄛˇ"], "救救我"),
            ("borrow", ["ㄐㄧㄝˋ", "ㄨㄛˇ", "ㄎㄢˋ", "ㄧ", "ㄒㄧㄚˋ"], "借我看一下")
        ]

        for (name, readings, expected) in cases {
            let grid = ReadingGrid(languageModel: lm)
            for reading in readings {
                XCTAssertTrue(grid.insertReading(reading), "\(name) rejected reading \(reading)")
            }
            let walk = grid.walk()
            let actual = walk.valuesAsStrings.joined()
            print("[DictionaryOnlyBaseline] \(name): actual=\(actual), expected=\(expected), exact=\(actual == expected), score=\(walk.totalScore)")
            XCTAssertEqual(walk.totalReadings, readings.count)
        }
    }

    func testContextualCharacterNgramCanReselectUnigramAndPreserveManualOverride() {
        let associationKey = (UInt64("乙".unicodeScalars.first!.value) << 32) | UInt64("丙".unicodeScalars.first!.value)
        let lm = ContextualLM(unigrams: [
            "a": [Unigram(value: "甲", score: -0.1), Unigram(value: "乙", score: -2.0)],
            "b": [Unigram(value: "丙", score: -0.1)]
        ], associations: [associationKey: 2.5])
        let grid = ReadingGrid(languageModel: lm)
        grid.readingSeparator = ""
        grid.characterBigramWeight = 1.0
        XCTAssertTrue(grid.insertReading("a"))
        XCTAssertTrue(grid.insertReading("b"))

        let contextualWalk = grid.walk()
        XCTAssertEqual(contextualWalk.valuesAsStrings, ["乙", "丙"])
        XCTAssertEqual(contextualWalk.totalScore, 0.4, accuracy: 1e-9)

        XCTAssertTrue(grid.overrideCandidate(loc: 0, candidateValue: "甲", overrideType: .overrideValueWithHighScore))
        let manuallyOverriddenWalk = grid.walk()
        XCTAssertEqual(manuallyOverriddenWalk.valuesAsStrings, ["甲", "丙"])
        XCTAssertEqual(manuallyOverriddenWalk.totalScore, ReadingGrid.overridingScore - 0.1, accuracy: 1e-9)
    }

    func testUserReportedSelectionsWithCharacterNgramContext() throws {
        let dataPath = repoRootURL.appendingPathComponent("Source/Data/data.txt").path
        let ngramPath = ProcessInfo.processInfo.environment["GG_CHARACTER_NGRAM_PATH"]
            ?? repoRootURL.appendingPathComponent("Source/Data/character-ngrams.txt").path
        guard FileManager.default.fileExists(atPath: dataPath),
              FileManager.default.fileExists(atPath: ngramPath) else {
            throw XCTSkip("Compiled dictionary or character n-gram table is unavailable")
        }

        let lm = EngineLM()
        XCTAssertTrue(lm.loadLanguageModel(path: dataPath))
        XCTAssertTrue(lm.loadCharacterNgramAssociations(path: ngramPath))
        let colloquialPath = repoRootURL.appendingPathComponent("Source/Data/colloquial.txt").path
        if FileManager.default.fileExists(atPath: colloquialPath) {
            _ = lm.loadColloquialPhrases(path: colloquialPath)
        }

        let cases: [(String, [String], String, Bool)] = [
            ("greeting", ["ㄋㄧˇ", "ㄏㄠˇ"], "你好", true),
            ("umbrella", ["ㄉㄞˋ", "ㄧ", "ㄅㄚˇ", "ㄩˇ", "ㄙㄢˇ"], "帶一把雨傘", true),
            ("raincoat", ["ㄒㄧㄚˋ", "ㄩˇ", "ㄊㄧㄢ", "ㄧㄠˋ", "ㄔㄨㄢ", "ㄩˇ", "ㄧ"], "下雨天要穿雨衣", true),
            ("help-me", ["ㄐㄧㄡˋ", "ㄐㄧㄡˋ", "ㄨㄛˇ"], "救救我", true),
            ("borrow", ["ㄐㄧㄝˋ", "ㄨㄛˇ", "ㄎㄢˋ", "ㄧ", "ㄒㄧㄚˋ"], "借我看一下", true)
        ]

        for (name, readings, expected, shouldCorrect) in cases {
            let grid = ReadingGrid(languageModel: lm)
            for reading in readings {
                XCTAssertTrue(grid.insertReading(reading), "\(name) rejected reading \(reading)")
            }
            let walk = grid.walk()
            let actual = walk.valuesAsStrings.joined()
            print("[CharacterNgramContext] \(name): actual=\(actual), expected=\(expected), exact=\(actual == expected), score=\(walk.totalScore)")
            let nodeSummary = walk.nodes.map { node -> String in
                let topCandidates = node.unigrams.prefix(5).map { "\($0.value):\(String(format: "%.3f", $0.score))" }.joined(separator: ",")
                return "\(node.reading)=\(node.value){\(topCandidates)}"
            }.joined(separator: " | ")
            print("[CharacterNgramContextNodes] \(nodeSummary)")
            XCTAssertEqual(walk.totalReadings, readings.count)
            if shouldCorrect {
                XCTAssertEqual(actual, expected, "\(name) should benefit from contextual n-gram scoring")
            }
        }
    }

    func testUserOverrideModel() {
        let lm = SimpleLM(sample: sampleData)
        let grid = ReadingGrid(languageModel: lm)
        grid.readingSeparator = ""

        _ = grid.insertReading("ㄎㄜ")
        let walkBefore = grid.walk()

        let overrideModel = UserOverrideModel(capacity: 10, decayConstant: 300.0)
        _ = grid.overrideCandidate(loc: 0, candidateValue: "顆")
        let walkAfter = grid.walk()

        overrideModel.observe(walkBefore: walkBefore, walkAfter: walkAfter, cursor: 0, timestamp: 1000.0)

        // Reset grid
        grid.clear()
        _ = grid.insertReading("ㄎㄜ")
        let newWalk = grid.walk()

        let suggestion = overrideModel.suggest(currentWalk: newWalk, cursor: 0, timestamp: 1001.0)
        XCTAssertEqual(suggestion.candidate, "顆")
    }

    func testUserOverrideModelPersistenceAndPermissions() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let storageURL = tempDir.appendingPathComponent("user_overrides.json")

        let model = UserOverrideModel(capacity: 2000, storageFileURL: storageURL)
        model.observe(priorWord: "穿", reading: "ㄩˇ-ㄧ", candidate: "雨衣", timestamp: 1000.0)

        // Force immediate save (flush)
        model.saveImmediately()

        // Verify file exists
        XCTAssertTrue(FileManager.default.fileExists(atPath: storageURL.path))

        // Verify POSIX permissions: directory 0700, file 0600
        let dirAttributes = try FileManager.default.attributesOfItem(atPath: tempDir.path)
        let dirPermissions = dirAttributes[.posixPermissions] as? NSNumber
        XCTAssertEqual(dirPermissions?.intValue, 0o700)

        let fileAttributes = try FileManager.default.attributesOfItem(atPath: storageURL.path)
        let filePermissions = fileAttributes[.posixPermissions] as? NSNumber
        XCTAssertEqual(filePermissions?.intValue, 0o600)

        // Simulate crash / restart: create brand new instance loading from same storageURL
        let reloadedModel = UserOverrideModel(capacity: 2000, storageFileURL: storageURL)
        let suggestion = reloadedModel.suggest(priorWord: "穿", reading: "ㄩˇ-ㄧ", timestamp: 1001.0)
        XCTAssertEqual(suggestion.candidate, "雨衣")

        // Test clearHistory
        reloadedModel.clearHistory()
        XCTAssertFalse(FileManager.default.fileExists(atPath: storageURL.path))
        let clearedSuggestion = reloadedModel.suggest(priorWord: "穿", reading: "ㄩˇ-ㄧ", timestamp: 1002.0)
        XCTAssertTrue(clearedSuggestion.isEmpty)

        // Clean up
        try? FileManager.default.removeItem(at: tempDir)
    }

    func testUserOverrideModelEvictionAndDecay() {
        let model = UserOverrideModel(capacity: 3, storageFileURL: nil)

        // Day 0: 0.0 seconds
        model.observe(priorWord: "A", reading: "r1", candidate: "c1", timestamp: 0.0)
        model.observe(priorWord: "B", reading: "r2", candidate: "c2", timestamp: 10.0)
        model.observe(priorWord: "C", reading: "r3", candidate: "c3", timestamp: 20.0)
        XCTAssertEqual(model.recordCount, 3)

        // Adding 4th should evict lowest count / oldest (A)
        model.observe(priorWord: "D", reading: "r4", candidate: "c4", timestamp: 30.0)
        XCTAssertEqual(model.recordCount, 3)
        XCTAssertTrue(model.suggest(priorWord: "A", reading: "r1", timestamp: 35.0).isEmpty)
        XCTAssertEqual(model.suggest(priorWord: "B", reading: "r2", timestamp: 35.0).candidate, "c2")

        // Test 30-day half-life decay: after 120 days (4 half-lives, decay = 0.0625 < 0.20 threshold)
        let after120Days = 120.0 * 86400.0
        XCTAssertTrue(model.suggest(priorWord: "B", reading: "r2", timestamp: after120Days).isEmpty)
    }

    func testWalkScoreConsistencyAndDisconnectedFallback() {
        let lm = SimpleLM(sample: sampleData)
        let grid = ReadingGrid(languageModel: lm)
        grid.readingSeparator = ""

        _ = grid.insertReading("ㄎㄜ")
        _ = grid.overrideCandidate(loc: 0, candidateValue: "顆", overrideType: .overrideValueWithHighScore)
        let walkOverridden = grid.walk()
        XCTAssertEqual(walkOverridden.totalScore, ReadingGrid.overridingScore, accuracy: 1e-6)

        // Simulate a disconnected span gap and verify walk() falls back gracefully without dropping readings
        _ = grid.insertReading("ㄐㄧˋ")
        grid.spans[0].clear()
        let walkDisconnected = grid.walk()
        XCTAssertEqual(walkDisconnected.totalReadings, 2)
        XCTAssertEqual(walkDisconnected.nodes.count, 2)
    }

    func testSemanticPOSHMMDisambiguation() throws {
        let testDir = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let dataPath = testDir.appendingPathComponent("Source/Data/data.txt").path
        let ngramPath = testDir.appendingPathComponent("Source/Data/character-ngrams.txt").path
        let colloquialPath = testDir.appendingPathComponent("Source/Data/colloquial.txt").path

        guard FileManager.default.fileExists(atPath: dataPath) else {
            throw XCTSkip("data.txt not found")
        }

        let lm = EngineLM()
        XCTAssertTrue(lm.loadLanguageModel(path: dataPath))
        if FileManager.default.fileExists(atPath: ngramPath) {
            _ = lm.loadCharacterNgramAssociations(path: ngramPath)
        }
        if FileManager.default.fileExists(atPath: colloquialPath) {
            _ = lm.loadColloquialPhrases(path: colloquialPath)
        }

        let cases: [(readings: [String], expected: String)] = [
            (["ㄉㄞˋ", "ㄧㄠˋ", "ㄕˇ"], "帶鑰匙"),
            (["ㄉㄞˋ", "ㄕㄡˇ", "ㄐㄧ"], "帶手機"),
            (["ㄉㄞˋ", "ㄑㄧㄢˊ", "ㄅㄠ"], "帶錢包"),
            (["ㄉㄞˋ", "ㄕㄨㄟˇ", "ㄏㄨˊ"], "帶水壺"),
            (["ㄉㄞˋ", "ㄅㄧㄢˋ", "ㄉㄤ"], "帶便當"),
            (["ㄉㄞˋ", "ㄅㄧˇ", "ㄐㄧˋ", "ㄅㄣˇ"], "帶筆記本"),
            (["ㄉㄞˋ", "ㄕㄡˇ", "ㄅㄧㄠˇ"], "戴手錶"),
            (["ㄉㄞˋ", "ㄧㄢˇ", "ㄐㄧㄥˋ"], "戴眼鏡"),
            (["ㄉㄞˋ", "ㄢ", "ㄑㄩㄢˊ", "ㄇㄠˋ"], "戴安全帽"),
            (["ㄉㄞˋ", "ㄎㄡˇ", "ㄓㄠˋ"], "戴口罩"),
            (["ㄉㄞˋ", "ㄩˇ", "ㄙㄢˇ"], "帶雨傘"),
            (["ㄔㄨㄢ", "ㄩˇ", "ㄧ"], "穿雨衣"),
            (["ㄗㄞˋ", "ㄊㄞˊ", "ㄅㄟˇ"], "在台北"),
            (["ㄗㄞˋ", "ㄎㄢˋ", "ㄧ", "ㄘˋ"], "再看一次"),
            (["ㄗㄞˋ", "ㄐㄧㄚ", "ㄌㄧˇ"], "在家裡"),
            (["ㄔㄨ", "ㄈㄚ", "ㄑㄧㄢˊ", "ㄗㄞˋ", "ㄑㄩㄝˋ", "ㄖㄣˋ"], "出發前再確認"),
            (["ㄉㄥˇ", "ㄧ", "ㄒㄧㄚˋ", "ㄗㄞˋ", "ㄗㄡˇ"], "等一下再走"),
            (["ㄔㄨ", "ㄈㄚ", "ㄑㄧㄢˊ", "ㄗㄞˋ", "ㄐㄧㄢˇ", "ㄔㄚˊ"], "出發前再檢查")
        ]

        for c in cases {
            let grid = ReadingGrid(languageModel: lm)
            grid.longWordBonusWeight = 0.42
            grid.posTransitionWeight = 0.35
            for r in c.readings {
                _ = grid.insertReading(r)
            }
            let walk = grid.walk()
            let predicted = walk.valuesAsStrings.joined()
            print("[POS HMM Test] readings: \(c.readings.joined(separator: " ")) -> predicted: \(predicted), expected: \(c.expected)")
            XCTAssertEqual(predicted, c.expected)
        }
    }
}
