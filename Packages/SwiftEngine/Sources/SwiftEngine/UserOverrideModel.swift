import Foundation

public final class UserOverrideModel {
    private static let emptyNodeString = "()"

    public struct Suggestion: Equatable {
        public let candidate: String
        public let forceHighScoreOverride: Bool

        public init(candidate: String = "", forceHighScoreOverride: Bool = false) {
            self.candidate = candidate
            self.forceHighScoreOverride = forceHighScoreOverride
        }

        public var isEmpty: Bool {
            candidate.isEmpty
        }
    }

    public struct Record: Codable, Equatable {
        public var priorWord: String
        public var reading: String
        public var candidate: String
        public var count: Int
        public var dayBucket: Int
        public var forceHighScoreOverride: Bool

        public init(priorWord: String, reading: String, candidate: String, count: Int, dayBucket: Int, forceHighScoreOverride: Bool) {
            self.priorWord = priorWord
            self.reading = reading
            self.candidate = candidate
            self.count = count
            self.dayBucket = dayBucket
            self.forceHighScoreOverride = forceHighScoreOverride
        }
    }

    public static func makeKey(priorWord: String, reading: String) -> String {
        "\(priorWord)|\(reading)"
    }

    public static var defaultStorageURL: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        let dir = appSupport.appendingPathComponent("gg", isDirectory: true)
        return dir.appendingPathComponent("user_overrides.json")
    }

    public let capacity: Int
    public var isRecordingEnabled: Bool = true
    public let storageFileURL: URL?

    private var records: [String: Record] = [:]
    private var lastAccessTimes: [String: Double] = [:]
    private let queue = DispatchQueue(label: "org.atelierinukakko.gg.user-overrides", qos: .utility)
    private var saveWorkItem: DispatchWorkItem?

    public init(capacity: Int = 2000, decayConstant: Double = 2592000.0, storageFileURL: URL? = nil) {
        assert(capacity > 0)
        self.capacity = capacity
        self.storageFileURL = storageFileURL
        if let url = storageFileURL {
            loadFromDisk(at: url)
        }
    }

    public var recordCount: Int {
        records.count
    }

    // MARK: - Core Operations
    public func observe(priorWord: String, reading: String, candidate: String, timestamp: Double, forceHighScoreOverride: Bool = false) {
        guard isRecordingEnabled else { return }
        let currentDay = Int(timestamp / 86400.0)
        let key = Self.makeKey(priorWord: priorWord, reading: reading)

        var record = records[key] ?? Record(
            priorWord: priorWord,
            reading: reading,
            candidate: candidate,
            count: 0,
            dayBucket: currentDay,
            forceHighScoreOverride: forceHighScoreOverride
        )

        if record.candidate == candidate {
            record.count += 1
            record.dayBucket = currentDay
            record.forceHighScoreOverride = forceHighScoreOverride || record.forceHighScoreOverride
        } else {
            // User selected an alternative candidate: reset count to 1 and adopt new candidate
            record.candidate = candidate
            record.count = 1
            record.dayBucket = currentDay
            record.forceHighScoreOverride = forceHighScoreOverride
        }

        records[key] = record
        lastAccessTimes[key] = timestamp

        if records.count > capacity {
            evictOne(currentDay: currentDay)
        }

        scheduleDebouncedSave()
    }

    public func suggest(priorWord: String, reading: String, timestamp: Double) -> Suggestion {
        let key = Self.makeKey(priorWord: priorWord, reading: reading)
        return suggest(key: key, timestamp: timestamp)
    }

    public func suggest(key: String, timestamp: Double) -> Suggestion {
        guard let record = records[key] else {
            return Suggestion()
        }

        let currentDay = Int(timestamp / 86400.0)
        let decay = decayMultiplier(forDayBucket: record.dayBucket, currentDay: currentDay)
        let effectiveScore = Double(record.count) * decay

        if effectiveScore < 0.20 {
            return Suggestion()
        }

        lastAccessTimes[key] = timestamp
        return Suggestion(candidate: record.candidate, forceHighScoreOverride: record.forceHighScoreOverride)
    }

    /// Calculates soft score boost directly inside Viterbi walk.
    ///
    /// Principle:
    /// 1. Single character (syllableLength == 1):
    ///    - count <= 1 (Hand-slip protection): gives only 40% of the gap to topScore (capped at 0.30).
    ///      Mathematically guaranteed NEVER to overthrow the top common word on a single accidental selection.
    ///    - count >= 2 (Confirmed user intent): covers gap + 0.35, cleanly flipping the default candidate.
    /// 2. Multi-character phrase (syllableLength >= 2):
    ///    - User deliberately selected a multi-word phrase; covers gap + 0.50 immediately on 1st pick.
    public func scoreBoost(
        priorWord: String,
        reading: String,
        candidate: String,
        syllableLength: Int,
        topScore: Double,
        candidateScore: Double,
        timestamp: Double
    ) -> Double {
        guard isRecordingEnabled else { return 0.0 }
        let key = Self.makeKey(priorWord: priorWord, reading: reading)
        guard let record = records[key], record.candidate == candidate else { return 0.0 }

        let currentDay = Int(timestamp / 86400.0)
        let decay = decayMultiplier(forDayBucket: record.dayBucket, currentDay: currentDay)
        let effectiveCount = Double(record.count) * decay
        if effectiveCount < 0.20 {
            return 0.0
        }

        let gap = max(0.0, topScore - candidateScore)

        if syllableLength == 1 {
            if record.count <= 1 {
                // Hand-slip protection: partial boost, never exceeds top candidate
                return min(gap * 0.40, 0.30) * decay
            } else {
                // Confirmed intent: flips default candidate on 2nd selection
                let extra = min(0.35 + Double(record.count - 2) * 0.15, 0.80)
                return (gap + extra) * decay
            }
        } else {
            // Multi-syllable phrase: immediate adoption
            let extra = min(0.50 + Double(record.count - 1) * 0.25, 1.20)
            return (gap + extra) * decay
        }
    }

    // MARK: - Compatibility API for ReadingGrid.WalkResult
    public func observe(walkBefore: ReadingGrid.WalkResult,
                        walkAfter: ReadingGrid.WalkResult,
                        cursor: Int,
                        timestamp: Double) {
        guard isRecordingEnabled else { return }
        if walkBefore.nodes.isEmpty || walkAfter.nodes.isEmpty {
            return
        }

        var actualCursor: Int? = nil
        guard let currentNodeIdx = walkAfter.findNodeAt(cursor: cursor, outCursorPastNode: &actualCursor),
              let actualPastCursor = actualCursor else {
            return
        }

        let currentNode = walkAfter.nodes[currentNodeIdx]
        if currentNode.spanningLength > 3 {
            return
        }

        let priorWord: String
        if currentNodeIdx > 0 {
            let prevNode = walkAfter.nodes[currentNodeIdx - 1]
            priorWord = prevNode.reading.starts(with: "_") ? "_START_" : prevNode.currentUnigram.value
        } else {
            priorWord = "_START_"
        }

        var forceHighScore = false
        var dummy: Int? = nil
        if actualPastCursor > 0,
           let prevHeadNodeIdx = walkBefore.findNodeAt(cursor: actualPastCursor - 1, outCursorPastNode: &dummy) {
            let prevHeadNode = walkBefore.nodes[prevHeadNodeIdx]
            forceHighScore = currentNode.spanningLength > prevHeadNode.spanningLength
        }

        observe(
            priorWord: priorWord,
            reading: currentNode.reading,
            candidate: currentNode.currentUnigram.value,
            timestamp: timestamp,
            forceHighScoreOverride: forceHighScore
        )
    }

    public func suggest(currentWalk: ReadingGrid.WalkResult, cursor: Int, timestamp: Double) -> Suggestion {
        var dummy: Int? = nil
        guard let nodeIdx = currentWalk.findNodeAt(cursor: cursor, outCursorPastNode: &dummy) else {
            return Suggestion()
        }
        let currentNode = currentWalk.nodes[nodeIdx]
        let priorWord: String
        if nodeIdx > 0 {
            let prevNode = currentWalk.nodes[nodeIdx - 1]
            priorWord = prevNode.reading.starts(with: "_") ? "_START_" : prevNode.currentUnigram.value
        } else {
            priorWord = "_START_"
        }
        return suggest(priorWord: priorWord, reading: currentNode.reading, timestamp: timestamp)
    }

    public func observe(key: String, candidate: String, timestamp: Double, forceHighScoreOverride: Bool = false) {
        guard isRecordingEnabled else { return }
        let (priorWord, reading) = parseKey(key)
        observe(
            priorWord: priorWord,
            reading: reading,
            candidate: candidate,
            timestamp: timestamp,
            forceHighScoreOverride: forceHighScoreOverride
        )
    }

    private func parseKey(_ key: String) -> (priorWord: String, reading: String) {
        if let pipeIndex = key.firstIndex(of: "|") {
            let prior = String(key[..<pipeIndex])
            let reading = String(key[key.index(after: pipeIndex)...])
            return (prior, reading)
        }
        return ("_START_", key)
    }

    // MARK: - Eviction & Decay
    private func decayMultiplier(forDayBucket dayBucket: Int, currentDay: Int) -> Double {
        let deltaDays = max(0, currentDay - dayBucket)
        return pow(0.5, Double(deltaDays) / 30.0)
    }

    private func evictOne(currentDay: Int) {
        guard !records.isEmpty else { return }
        var minScore = Double.greatestFiniteMagnitude
        var oldestAccess = Double.greatestFiniteMagnitude
        var bestCandidateKey: String? = nil

        for (key, record) in records {
            let score = Double(record.count) * decayMultiplier(forDayBucket: record.dayBucket, currentDay: currentDay)
            let access = lastAccessTimes[key] ?? 0.0
            if score < minScore || (score == minScore && access < oldestAccess) {
                minScore = score
                oldestAccess = access
                bestCandidateKey = key
            }
        }

        if let keyToEvict = bestCandidateKey {
            records.removeValue(forKey: keyToEvict)
            lastAccessTimes.removeValue(forKey: keyToEvict)
        }
    }

    // MARK: - Persistence & Privacy
    public func scheduleDebouncedSave() {
        guard storageFileURL != nil else { return }
        queue.async { [weak self] in
            guard let self = self else { return }
            self.saveWorkItem?.cancel()
            let item = DispatchWorkItem { [weak self] in
                self?.performSaveToDisk()
            }
            self.saveWorkItem = item
            self.queue.asyncAfter(deadline: .now() + 1.5, execute: item)
        }
    }

    public func saveImmediately() {
        guard storageFileURL != nil else { return }
        queue.sync { [weak self] in
            self?.saveWorkItem?.cancel()
            self?.performSaveToDisk()
        }
    }

    public func clearHistory() {
        records.removeAll()
        lastAccessTimes.removeAll()
        queue.sync { [weak self] in
            guard let self = self, let fileURL = self.storageFileURL else { return }
            self.saveWorkItem?.cancel()
            if FileManager.default.fileExists(atPath: fileURL.path) {
                try? FileManager.default.removeItem(at: fileURL)
            }
        }
    }

    private func performSaveToDisk() {
        guard let fileURL = storageFileURL else { return }
        let dirURL = fileURL.deletingLastPathComponent()
        do {
            try FileManager.default.createDirectory(
                at: dirURL,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
            try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: dirURL.path)

            let recordList = Array(self.records.values)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(recordList)

            try data.write(to: fileURL, options: .atomic)
            try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
        } catch {
            print("[UserOverrideModel] Failed to save overrides: \(error)")
        }
    }

    private func loadFromDisk(at fileURL: URL) {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
        do {
            let data = try Data(contentsOf: fileURL)
            let decoded = try JSONDecoder().decode([Record].self, from: data)
            for record in decoded {
                let key = Self.makeKey(priorWord: record.priorWord, reading: record.reading)
                self.records[key] = record
                self.lastAccessTimes[key] = Double(record.dayBucket * 86400)
            }
        } catch {
            print("[UserOverrideModel] Failed to load overrides: \(error)")
        }
    }
}
