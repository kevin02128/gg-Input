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
}
