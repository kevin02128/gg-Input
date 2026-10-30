import XCTest
import Foundation
@testable import SwiftEngine

final class EvaluationBenchmarkTests: XCTestCase {

    private var repoRootURL: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // SwiftEngineTests
            .deletingLastPathComponent() // Tests
            .deletingLastPathComponent() // SwiftEngine
            .deletingLastPathComponent() // Packages
            .deletingLastPathComponent() // gg repo root
    }

    struct BenchmarkItem: Codable {
        let id: Int
        let split: String
        let category: String
        let target: String
        let readings: [String]
    }

    struct BenchmarkRecord: Codable {
        let id: Int
        let split: String
        let category: String
        let target: String
        let predicted: String
        let exact: Bool
        let distance: Int
        let cer: Double
        let latencyMs: Double
    }

    struct BenchmarkSummary: Codable {
        let totalCount: Int
        let exactCount: Int
        let exactAccuracyPct: Double
        let meanCerPct: Double
        let meanLatencyMs: Double
        let devAccuracyPct: Double
        let testAccuracyPct: Double
        let homophoneAccuracyPct: Double
        let colloquialAccuracyPct: Double
        let officialAccuracyPct: Double
    }

    func testGridSearchBetaOnDevSet() throws {
        let dataPath = repoRootURL.appendingPathComponent("Source/Data/data.txt").path
        let ngramPath = repoRootURL.appendingPathComponent("Source/Data/character-ngrams.txt").path
        let benchmarkPath = repoRootURL.appendingPathComponent("TestingData/eval_benchmark.jsonl").path

        guard FileManager.default.fileExists(atPath: dataPath),
              FileManager.default.fileExists(atPath: benchmarkPath) else {
            throw XCTSkip("Required data.txt or eval_benchmark.jsonl not found")
        }

        let lm = EngineLM()
        XCTAssertTrue(lm.loadLanguageModel(path: dataPath))
        _ = lm.loadCharacterNgramAssociations(path: ngramPath)
        let colloquialPath = repoRootURL.appendingPathComponent("Source/Data/colloquial.txt").path
        if FileManager.default.fileExists(atPath: colloquialPath) {
            _ = lm.loadColloquialPhrases(path: colloquialPath)
        }

        let content = try String(contentsOfFile: benchmarkPath, encoding: .utf8)
        let lines = content.components(separatedBy: .newlines).filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }

        var devItems: [BenchmarkItem] = []
        for line in lines {
            if let data = line.data(using: .utf8),
               let item = try? JSONDecoder().decode(BenchmarkItem.self, from: data),
               item.split == "dev" {
                devItems.append(item)
            }
        }
        XCTAssertEqual(devItems.count, 250)

        let betaCandidates = [0.0, 0.10, 0.20, 0.30, 0.35, 0.40, 0.50, 0.60, 0.75]
        print("\n================================================================================")
        print("          BETA GRID SEARCH ON DEVELOPMENT SET (250 SENTENCES)")
        print("================================================================================")
        for beta in betaCandidates {
            var exactCount = 0
            for item in devItems {
                let grid = ReadingGrid(languageModel: lm)
                grid.longWordBonusWeight = beta
                for r in item.readings {
                    _ = grid.insertReading(r)
                }
                let walk = grid.walk()
                if walk.valuesAsStrings.joined() == item.target {
                    exactCount += 1
                }
            }
            let acc = Double(exactCount) / Double(devItems.count) * 100.0
            print(String(format: "Beta: %.2f -> Dev Exact: %d / %d (%.2f%%)", beta, exactCount, devItems.count, acc))
        }
        print("================================================================================\n")
    }

    func testRunFullEvaluationBenchmarkOnSwiftEngine() throws {
        let dataPath = repoRootURL.appendingPathComponent("Source/Data/data.txt").path
        let ngramPath = repoRootURL.appendingPathComponent("Source/Data/character-ngrams.txt").path
        let benchmarkPath = repoRootURL.appendingPathComponent("TestingData/eval_benchmark.jsonl").path
        let outputPath = repoRootURL.appendingPathComponent("TestingData/benchmark_results_swiftengine.json").path

        guard FileManager.default.fileExists(atPath: dataPath),
              FileManager.default.fileExists(atPath: benchmarkPath) else {
            throw XCTSkip("Required data.txt or eval_benchmark.jsonl not found")
        }

        let lm = EngineLM()
        XCTAssertTrue(lm.loadLanguageModel(path: dataPath), "Failed to load data.txt")
        let hasNgram = FileManager.default.fileExists(atPath: ngramPath) && lm.loadCharacterNgramAssociations(path: ngramPath)
        print("[Benchmark] Character N-gram loaded: \(hasNgram)")
        let colloquialPath = repoRootURL.appendingPathComponent("Source/Data/colloquial.txt").path
        if FileManager.default.fileExists(atPath: colloquialPath) {
            let hasColloquial = lm.loadColloquialPhrases(path: colloquialPath)
            print("[Benchmark] Colloquial patch loaded: \(hasColloquial)")
        }

        let content = try String(contentsOfFile: benchmarkPath, encoding: .utf8)
        let lines = content.components(separatedBy: .newlines).filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }

        var items: [BenchmarkItem] = []
        for line in lines {
            if let data = line.data(using: .utf8),
               let item = try? JSONDecoder().decode(BenchmarkItem.self, from: data) {
                items.append(item)
            }
        }
        XCTAssertEqual(items.count, 500, "Expected 500 benchmark items")

        var records: [BenchmarkRecord] = []
        var totalLatencyMs: Double = 0.0

        for item in items {
            let grid = ReadingGrid(languageModel: lm)
            for r in item.readings {
                _ = grid.insertReading(r)
            }

            let start = DispatchTime.now().uptimeNanoseconds
            let walk = grid.walk()
            let end = DispatchTime.now().uptimeNanoseconds
            let latencyMs = Double(end - start) / 1_000_000.0
            totalLatencyMs += latencyMs

            let predicted = walk.valuesAsStrings.joined()
            let exact = (predicted == item.target)
            let distance = levenshteinDistance(predicted, item.target)
            let cer = item.target.isEmpty ? 0.0 : Double(distance) / Double(item.target.count)

            records.append(BenchmarkRecord(
                id: item.id,
                split: item.split,
                category: item.category,
                target: item.target,
                predicted: predicted,
                exact: exact,
                distance: distance,
                cer: cer,
                latencyMs: latencyMs
            ))
        }

        // Output raw records to JSON
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        let outputData = try encoder.encode(records)
        try outputData.write(to: URL(fileURLWithPath: outputPath))

        // Aggregate statistics
        let exactCount = records.filter { $0.exact }.count
        let totalCount = records.count
        let exactAccuracyPct = Double(exactCount) / Double(totalCount) * 100.0
        let meanCerPct = records.map { $0.cer }.reduce(0, +) / Double(totalCount) * 100.0
        let meanLatencyMs = totalLatencyMs / Double(totalCount)

        let canonicalExactCount = records.filter { normalizeCanonicalVariants($0.predicted) == normalizeCanonicalVariants($0.target) }.count
        let canonicalAccuracyPct = Double(canonicalExactCount) / Double(totalCount) * 100.0

        let devRecords = records.filter { $0.split == "dev" }
        let devExact = devRecords.filter { $0.exact }.count
        let devAccuracyPct = Double(devExact) / Double(devRecords.count) * 100.0
        let devCanonicalExact = devRecords.filter { normalizeCanonicalVariants($0.predicted) == normalizeCanonicalVariants($0.target) }.count
        let devCanonicalAccuracyPct = Double(devCanonicalExact) / Double(devRecords.count) * 100.0

        let testRecords = records.filter { $0.split == "test" }
        let testExact = testRecords.filter { $0.exact }.count
        let testAccuracyPct = Double(testExact) / Double(testRecords.count) * 100.0
        let testCanonicalExact = testRecords.filter { normalizeCanonicalVariants($0.predicted) == normalizeCanonicalVariants($0.target) }.count
        let testCanonicalAccuracyPct = Double(testCanonicalExact) / Double(testRecords.count) * 100.0

        let homophoneRecords = records.filter { $0.category == "homophone_ambiguity" }
        let homophoneExact = homophoneRecords.filter { $0.exact }.count
        let homophoneAccuracyPct = Double(homophoneExact) / Double(homophoneRecords.count) * 100.0

        let colloquialRecords = records.filter { $0.category == "colloquial" }
        let colloquialExact = colloquialRecords.filter { $0.exact }.count
        let colloquialAccuracyPct = Double(colloquialExact) / Double(colloquialRecords.count) * 100.0

        let officialRecords = records.filter { $0.category == "official" }
        let officialExact = officialRecords.filter { $0.exact }.count
        let officialAccuracyPct = Double(officialExact) / Double(officialRecords.count) * 100.0

        print("\n================================================================================")
        print("          SWIFTENGINE BENCHMARK RESULTS (500 SENTENCES)")
        print("================================================================================")
        print(String(format: "Strict Exact Accuracy:       %d / %d (%.2f%%)", exactCount, totalCount, exactAccuracyPct))
        print(String(format: "Canonical Variant Accuracy:  %d / %d (%.2f%%)", canonicalExactCount, totalCount, canonicalAccuracyPct))
        print(String(format: "Mean Character Error Rate:   %.2f%%", meanCerPct))
        print(String(format: "Mean Walk Latency:           %.3f ms", meanLatencyMs))
        print("--------------------------------------------------------------------------------")
        print(String(format: "Development Set (Strict):    %d / %d (%.2f%%)", devExact, devRecords.count, devAccuracyPct))
        print(String(format: "Development Set (Canonical): %d / %d (%.2f%%)", devCanonicalExact, devRecords.count, devCanonicalAccuracyPct))
        print(String(format: "Holdout Blind Set (Strict):  %d / %d (%.2f%%)", testExact, testRecords.count, testAccuracyPct))
        print(String(format: "Holdout Blind (Canonical):   %d / %d (%.2f%%)", testCanonicalExact, testRecords.count, testCanonicalAccuracyPct))
        print("--------------------------------------------------------------------------------")
        print(String(format: "Category: Homophone Ambiguity:  %d / %d (%.2f%%)", homophoneExact, homophoneRecords.count, homophoneAccuracyPct))
        print(String(format: "Category: Daily Colloquial:     %d / %d (%.2f%%)", colloquialExact, colloquialRecords.count, colloquialAccuracyPct))
        print(String(format: "Category: Official / News:      %d / %d (%.2f%%)", officialExact, officialRecords.count, officialAccuracyPct))
        print("================================================================================\n")
    }

    private static let canonicalVariantMap: [(String, String)] = [
        ("什麼", "甚麼"),
        ("回覆", "回復"),
        ("交待", "交代"),
        ("計畫", "計劃"),
        ("紀錄", "記錄"),
        ("臺", "台"),
        ("唸", "念"),
        ("麼", "么"),
        ("覆", "復"),
        ("儘", "盡"),
        ("待", "代"),
        ("愈", "越"),
        ("裏", "裡"),
        ("份", "分"),
        ("佔", "占")
    ]

    private func normalizeCanonicalVariants(_ text: String) -> String {
        var s = text
        for (k, v) in Self.canonicalVariantMap {
            s = s.replacingOccurrences(of: k, with: v)
        }
        return s
    }

    private func levenshteinDistance(_ s1: String, _ s2: String) -> Int {
        let a = Array(s1)
        let b = Array(s2)
        var dist = Array(repeating: Array(repeating: 0, count: b.count + 1), count: a.count + 1)

        for i in 0...a.count {
            dist[i][0] = i
        }
        for j in 0...b.count {
            dist[0][j] = j
        }

        for i in 1...a.count {
            for j in 1...b.count {
                if a[i - 1] == b[j - 1] {
                    dist[i][j] = dist[i - 1][j - 1]
                } else {
                    dist[i][j] = min(dist[i - 1][j] + 1, min(dist[i][j - 1] + 1, dist[i - 1][j - 1] + 1))
                }
            }
        }
        return dist[a.count][b.count]
    }

    func testMeasureWalkLatencyDistribution() throws {
        let dataPath = repoRootURL.appendingPathComponent("Source/Data/data.txt").path
        let ngramPath = repoRootURL.appendingPathComponent("Source/Data/character-ngrams.txt").path
        let colloquialPath = repoRootURL.appendingPathComponent("Source/Data/colloquial.txt").path

        let lm = EngineLM()
        XCTAssertTrue(lm.loadLanguageModel(path: dataPath))
        _ = lm.loadCharacterNgramAssociations(path: ngramPath)
        _ = lm.loadColloquialPhrases(path: colloquialPath)

        let sampleReadings = [
            "ㄐㄧㄣ", "ㄊㄧㄢ", "ㄨㄛˇ", "ㄇㄣ˙", "ㄧㄠˋ", "ㄉㄠˋ", "ㄊㄞˊ", "ㄅㄟˇ", "ㄕˋ", "ㄓㄥˋ",
            "ㄈㄨˇ", "ㄉㄜ˙", "ㄉㄚˋ", "ㄌㄡˊ", "ㄎㄞ", "ㄏㄨㄟˋ", "ㄊㄠˇ", "ㄌㄨㄣˋ", "ㄒㄧㄚˋ", "ㄅㄢˋ",
            "ㄋㄧㄢˊ", "ㄉㄜ˙", "ㄓㄨㄥˋ", "ㄉㄚˋ", "ㄍㄨㄥ", "ㄔㄥˊ", "ㄐㄧˋ", "ㄏㄨㄚˋ", "ㄢˋ", "ㄐㄧㄢˋ"
        ]

        print("\n================================================================================")
        print("          WALK LATENCY BENCHMARK BY SYLLABLE LENGTH (RELEASE MODE)")
        print("================================================================================")
        print("Length | Iterations | Min (ms) | P50 (ms) | P90 (ms) | P95 (ms) | Max (ms)")
        print("-------|------------|----------|----------|----------|----------|---------")

        for length in [1, 2, 3, 5, 8, 10, 15, 20, 25, 30] {
            let sub = Array(sampleReadings.prefix(length))
            var latencies: [Double] = []

            let grid = ReadingGrid(languageModel: lm)
            grid.longWordBonusWeight = 0.42
            for r in sub { _ = grid.insertReading(r) }

            // Warmup
            for _ in 0..<5 { _ = grid.walk() }

            // Measure 100 runs
            for _ in 0..<100 {
                let start = DispatchTime.now().uptimeNanoseconds
                _ = grid.walk()
                let end = DispatchTime.now().uptimeNanoseconds
                latencies.append(Double(end - start) / 1_000_000.0)
            }

            latencies.sort()
            let minL = latencies[0]
            let p50 = latencies[latencies.count / 2]
            let p90 = latencies[Int(Double(latencies.count) * 0.9)]
            let p95 = latencies[Int(Double(latencies.count) * 0.95)]
            let maxL = latencies.last!

            print(String(format: "%6d | %10d | %8.3f | %8.3f | %8.3f | %8.3f | %8.3f",
                         length, 100, minL, p50, p90, p95, maxL))
        }
        print("================================================================================\n")
    }
}
