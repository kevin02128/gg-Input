import Foundation

public final class UserOverrideModel {
    private static let decayThreshold = 1.0 / 1048576.0
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

    private struct Override {
        var count: Int = 0
        var timestamp: Double = 0.0
        var forceHighScoreOverride: Bool = false
    }

    private struct Observation {
        var count: Int = 0
        var overrides: [String: Override] = [:]

        mutating func update(candidate: String, timestamp: Double, forceHighScoreOverride: Bool) {
            count += 1
            var o = overrides[candidate] ?? Override()
            o.timestamp = timestamp
            o.count += 1
            o.forceHighScoreOverride = forceHighScoreOverride
            overrides[candidate] = o
        }
    }

    private let capacity: Int
    private let decayExponent: Double
    private var lruKeys: [String] = []
    private var map: [String: Observation] = [:]

    public init(capacity: Int = 500, decayConstant: Double = 300.0) {
        assert(capacity > 0)
        self.capacity = capacity
        self.decayExponent = log(0.5) / decayConstant
    }

    public func observe(walkBefore: ReadingGrid.WalkResult,
                        walkAfter: ReadingGrid.WalkResult,
                        cursor: Int,
                        timestamp: Double) {
        if walkBefore.nodes.isEmpty || walkAfter.nodes.isEmpty {
            return
        }
        if walkBefore.totalReadings != walkAfter.totalReadings {
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

        if actualPastCursor == 0 {
            return
        }
        let prevCursor = actualPastCursor - 1

        var dummy: Int? = nil
        guard let prevHeadNodeIdx = walkBefore.findNodeAt(cursor: prevCursor, outCursorPastNode: &dummy) else {
            return
        }
        let prevHeadNode = walkBefore.nodes[prevHeadNodeIdx]

        let forceHighScoreOverride = currentNode.spanningLength > prevHeadNode.spanningLength
        let breakingUp = (currentNode.spanningLength == 1 && prevHeadNode.spanningLength > 1)

        let nodes = breakingUp ? walkAfter.nodes : walkBefore.nodes
        let headIdx = breakingUp ? currentNodeIdx : prevHeadNodeIdx

        let key = formObservationKey(nodes: nodes, headIndex: headIdx)
        observe(key: key, candidate: currentNode.currentUnigram.value, timestamp: timestamp, forceHighScoreOverride: forceHighScoreOverride)
    }

    public func suggest(currentWalk: ReadingGrid.WalkResult, cursor: Int, timestamp: Double) -> Suggestion {
        var dummy: Int? = nil
        guard let nodeIdx = currentWalk.findNodeAt(cursor: cursor, outCursorPastNode: &dummy) else {
            return Suggestion()
        }
        let key = formObservationKey(nodes: currentWalk.nodes, headIndex: nodeIdx)
        return suggest(key: key, timestamp: timestamp)
    }

    public func observe(key: String, candidate: String, timestamp: Double, forceHighScoreOverride: Bool = false) {
        var observation = map[key] ?? Observation()
        observation.update(candidate: candidate, timestamp: timestamp, forceHighScoreOverride: forceHighScoreOverride)
        map[key] = observation

        // Update LRU order
        if let existingIdx = lruKeys.firstIndex(of: key) {
            lruKeys.remove(at: existingIdx)
        }
        lruKeys.insert(key, at: 0)

        if lruKeys.count > capacity {
            let removedKey = lruKeys.removeLast()
            map.removeValue(forKey: removedKey)
        }
    }

    public func suggest(key: String, timestamp: Double) -> Suggestion {
        guard let observation = map[key] else {
            return Suggestion()
        }

        var bestCandidate = ""
        var bestForceHighScore = false
        var bestScore = 0.0

        for (cand, overrideObj) in observation.overrides {
            let score = calculateScore(eventCount: overrideObj.count,
                                       totalCount: observation.count,
                                       eventTimestamp: overrideObj.timestamp,
                                       timestamp: timestamp,
                                       lambda: decayExponent)
            if score == 0.0 {
                continue
            }
            if score > bestScore {
                bestCandidate = cand
                bestForceHighScore = overrideObj.forceHighScoreOverride
                bestScore = score
            }
        }

        return Suggestion(candidate: bestCandidate, forceHighScoreOverride: bestForceHighScore)
    }

    private func calculateScore(eventCount: Int, totalCount: Int, eventTimestamp: Double, timestamp: Double, lambda: Double) -> Double {
        let decay = exp((timestamp - eventTimestamp) * lambda)
        if decay < Self.decayThreshold {
            return 0.0
        }
        let prob = Double(eventCount) / Double(totalCount)
        return prob * decay
    }

    private func combineReadingValue(reading: String, value: String) -> String {
        "(\(reading),\(value))"
    }

    private func isPunctuation(node: ReadingGrid.Node) -> Bool {
        node.reading.starts(with: "_")
    }

    private func formObservationKey(nodes: [ReadingGrid.Node], headIndex: Int) -> String {
        let headNode = nodes[headIndex]
        let headStr = combineReadingValue(reading: headNode.reading, value: headNode.unigrams.first?.value ?? "")

        var prevStr = Self.emptyNodeString
        var prevIsPunctuation = false

        if headIndex > 0 {
            let prevNode = nodes[headIndex - 1]
            prevIsPunctuation = isPunctuation(node: prevNode)
            if !prevIsPunctuation {
                prevStr = combineReadingValue(reading: prevNode.reading, value: prevNode.currentUnigram.value)
            }
        }

        var anteriorStr = Self.emptyNodeString
        if headIndex > 1 && !prevIsPunctuation {
            let anteriorNode = nodes[headIndex - 2]
            if !isPunctuation(node: anteriorNode) {
                anteriorStr = combineReadingValue(reading: anteriorNode.reading, value: anteriorNode.currentUnigram.value)
            }
        }

        return "\(anteriorStr)-\(prevStr)-\(headStr)"
    }
}
