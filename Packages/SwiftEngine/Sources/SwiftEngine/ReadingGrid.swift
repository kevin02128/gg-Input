import Foundation

public final class ReadingGrid {
    public static let maximumSpanLength: Int = 8
    public static let defaultSeparator: String = "-"
    public static let overridingScore: Double = 42.0

    // MARK: - Node
    public final class Node {
        public enum OverrideType: Equatable {
            case none
            case overrideValueWithHighScore
            case overrideValueWithScoreFromTopUnigram
        }

        public let reading: String
        public let spanningLength: Int
        public let unigrams: [Unigram]
        public private(set) var unigramIndex: Int = 0
        public private(set) var overrideType: OverrideType = .none

        public init(reading: String, spanningLength: Int, unigrams: [Unigram]) {
            self.reading = reading
            self.spanningLength = spanningLength
            self.unigrams = unigrams
            self.unigramIndex = 0
            self.overrideType = .none
        }

        public init(copying other: Node) {
            self.reading = other.reading
            self.spanningLength = other.spanningLength
            self.unigrams = other.unigrams
            self.unigramIndex = other.unigramIndex
            self.overrideType = other.overrideType
        }

        public var currentUnigram: Unigram {
            unigrams.isEmpty ? Unigram() : unigrams[unigramIndex]
        }

        public var value: String {
            unigrams.isEmpty ? "" : unigrams[unigramIndex].value
        }

        public var score: Double {
            if unigrams.isEmpty { return 0.0 }
            switch overrideType {
            case .overrideValueWithHighScore:
                return ReadingGrid.overridingScore
            case .overrideValueWithScoreFromTopUnigram:
                return unigrams[0].score
            case .none:
                return unigrams[unigramIndex].score
            }
        }

        public var isOverridden: Bool {
            overrideType != .none
        }

        public func reset() {
            unigramIndex = 0
            overrideType = .none
        }

        @discardableResult
        public func selectOverrideUnigram(value: String, type: OverrideType) -> Bool {
            assert(type != .none)
            for (idx, u) in unigrams.enumerated() {
                if u.value == value {
                    unigramIndex = idx
                    overrideType = type
                    return true
                }
            }
            return false
        }

        @discardableResult
        public func selectUnigramWithoutOverride(value: String) -> Bool {
            for (idx, u) in unigrams.enumerated() {
                if u.value == value {
                    unigramIndex = idx
                    return true
                }
            }
            return false
        }
    }

    // MARK: - Span
    public final class Span {
        private var nodes: [Node?] = Array(repeating: nil, count: ReadingGrid.maximumSpanLength)
        public private(set) var maxLength: Int = 0

        public init() {}

        public func clear() {
            nodes = Array(repeating: nil, count: ReadingGrid.maximumSpanLength)
            maxLength = 0
        }

        public func add(_ node: Node) {
            assert(node.spanningLength > 0 && node.spanningLength <= ReadingGrid.maximumSpanLength)
            nodes[node.spanningLength - 1] = node
            maxLength = max(maxLength, node.spanningLength)
        }

        public func removeNodesOfOrLongerThan(length: Int) {
            assert(length > 0 && length <= ReadingGrid.maximumSpanLength)
            for i in (length - 1)..<ReadingGrid.maximumSpanLength {
                nodes[i] = nil
            }
            maxLength = 0
            if length == 1 { return }

            var i = length - 2
            while true {
                if nodes[i] != nil {
                    maxLength = i + 1
                    return
                }
                if i == 0 { return }
                i -= 1
            }
        }

        public func nodeOf(length: Int) -> Node? {
            assert(length > 0 && length <= ReadingGrid.maximumSpanLength)
            return nodes[length - 1]
        }
    }

    // MARK: - Candidate
    public struct Candidate: Equatable, Hashable {
        public let reading: String
        public let value: String
        public let rawValue: String

        public init(reading: String, value: String, rawValue: String = "") {
            self.reading = reading
            self.value = value
            self.rawValue = rawValue
        }
    }

    // MARK: - WalkResult
    public struct WalkResult {
        public var nodes: [Node] = []
        public var totalReadings: Int = 0
        public var vertices: Int = 0
        public var edges: Int = 0
        public var elapsedMicroseconds: UInt64 = 0
        public var totalScore: Double = 0.0

        public init() {}

        public init(nodes: [Node], totalReadings: Int, vertices: Int, edges: Int, elapsedMicroseconds: UInt64, totalScore: Double) {
            self.nodes = nodes
            self.totalReadings = totalReadings
            self.vertices = vertices
            self.edges = edges
            self.elapsedMicroseconds = elapsedMicroseconds
            self.totalScore = totalScore
        }

        public func findNodeAt(cursor: Int, outCursorPastNode: inout Int?) -> [Node].Index? {
            if nodes.isEmpty || cursor > totalReadings {
                return nil
            }
            if cursor == 0 {
                outCursorPastNode = nodes[0].spanningLength
                return 0
            }
            if cursor >= totalReadings - 1 {
                outCursorPastNode = totalReadings
                return nodes.count - 1
            }
            var accumulated = 0
            for (idx, node) in nodes.enumerated() {
                accumulated += node.spanningLength
                if accumulated > cursor {
                    outCursorPastNode = accumulated
                    return idx
                }
            }
            return nil
        }

        public var valuesAsStrings: [String] {
            nodes.map { $0.value }
        }

        public var readingsAsStrings: [String] {
            nodes.map { $0.reading }
        }

        public func copyWithFixedNodes() -> WalkResult {
            let copiedNodes = nodes.map { Node(copying: $0) }
            return WalkResult(nodes: copiedNodes,
                              totalReadings: totalReadings,
                              vertices: vertices,
                              edges: edges,
                              elapsedMicroseconds: elapsedMicroseconds,
                              totalScore: totalScore)
        }
    }

    public struct NodeInSpan {
        public let node: Node
        public let spanIndex: Int
    }

    // MARK: - State
    public private(set) var cursor: Int = 0
    public var readingSeparator: String = ReadingGrid.defaultSeparator
    public private(set) var readings: [String] = []
    public private(set) var spans: [Span] = []
    private let lm: ScoreRankedLanguageModel

    public init(languageModel: LanguageModel) {
        self.lm = ScoreRankedLanguageModel(languageModel: languageModel)
    }

    public var length: Int {
        readings.count
    }

    public func setCursor(_ newCursor: Int) {
        assert(newCursor <= readings.count)
        self.cursor = newCursor
    }

    public func clear() {
        cursor = 0
        readings.removeAll()
        spans.removeAll()
    }

    // MARK: - Mutation
    private enum EditType {
        case insertion
        case deletion
    }

    public func insertReading(_ reading: String) -> Bool {
        if reading.isEmpty || reading == readingSeparator {
            return false
        }
        let unigrams = lm.getUnigrams(reading: reading)
        if unigrams.isEmpty {
            return false
        }

        readings.insert(reading, at: cursor)
        expandGridAt(loc: cursor)
        insert(loc: cursor, node: Node(reading: readings[cursor], spanningLength: 1, unigrams: unigrams))
        update(loc: cursor, editType: .insertion)
        cursor += 1
        return true
    }

    public func deleteReadingBeforeCursor() -> Bool {
        if cursor == 0 {
            return false
        }
        readings.remove(at: cursor - 1)
        cursor -= 1
        shrinkGridAt(loc: cursor)
        update(loc: cursor, editType: .deletion)
        return true
    }

    public func deleteReadingAfterCursor() -> Bool {
        if cursor == readings.count {
            return false
        }
        readings.remove(at: cursor)
        shrinkGridAt(loc: cursor)
        update(loc: cursor, editType: .deletion)
        return true
    }

    // MARK: - Viterbi Walk
    public func walk() -> WalkResult {
        var result = WalkResult()
        if spans.isEmpty {
            return result
        }
        let startTime = DispatchTime.now()

        struct ViterbiState {
            var fromIndex: Int = 0
            var fromNode: Node? = nil
            var maxScore: Double = -Double.infinity
        }

        let readingLen = readings.count
        var viterbi = Array(repeating: ViterbiState(), count: readingLen + 1)
        viterbi[0].maxScore = 0.0

        var reachableStates = 0
        var evaluatedEdges = 0

        for i in 0..<readingLen {
            reachableStates += 1
            let span = spans[i]
            let maxSpanLen = span.maxLength
            guard maxSpanLen > 0 else {
                continue
            }

            for spanLen in 1...maxSpanLen {
                guard let node = span.nodeOf(length: spanLen) else {
                    continue
                }
                evaluatedEdges += 1
                let score = viterbi[i].maxScore + node.score
                if score > viterbi[i + spanLen].maxScore {
                    viterbi[i + spanLen].maxScore = score
                    viterbi[i + spanLen].fromNode = node
                    viterbi[i + spanLen].fromIndex = i
                }
            }
        }

        result.vertices = reachableStates
        result.edges = evaluatedEdges

        var totalReadingLen = 0
        var rawScoreSum = 0.0
        var curr = readingLen
        while curr > 0 {
            guard let fromNode = viterbi[curr].fromNode else {
                break
            }
            totalReadingLen += fromNode.spanningLength
            rawScoreSum += fromNode.currentUnigram.score
            result.nodes.append(fromNode)
            curr = viterbi[curr].fromIndex
        }

        result.nodes.reverse()
        assert(totalReadingLen == readingLen)
        result.totalReadings = totalReadingLen
        result.totalScore = rawScoreSum

        let endTime = DispatchTime.now()
        let nanos = endTime.uptimeNanoseconds - startTime.uptimeNanoseconds
        result.elapsedMicroseconds = nanos / 1000
        return result
    }

    // MARK: - Candidates
    public func candidatesAt(loc: Int) -> [Candidate] {
        var result: [Candidate] = []
        if readings.isEmpty || loc > readings.count {
            return result
        }

        var nodes = overlappingNodesAt(loc: loc == readings.count ? loc - 1 : loc)
        nodes.sort { $0.node.spanningLength > $1.node.spanningLength }

        for nodeInSpan in nodes {
            for unigram in nodeInSpan.node.unigrams {
                result.append(Candidate(reading: nodeInSpan.node.reading,
                                        value: unigram.value,
                                        rawValue: unigram.rawValue))
            }
        }
        return result
    }

    @discardableResult
    public func overrideCandidate(loc: Int, candidate: Candidate, overrideType: Node.OverrideType = .overrideValueWithHighScore) -> Bool {
        overrideCandidate(loc: loc, reading: candidate.reading, value: candidate.value, overrideType: overrideType)
    }

    @discardableResult
    public func overrideCandidate(loc: Int, candidateValue: String, overrideType: Node.OverrideType = .overrideValueWithHighScore) -> Bool {
        overrideCandidate(loc: loc, reading: nil, value: candidateValue, overrideType: overrideType)
    }

    private func overrideCandidate(loc: Int, reading: String?, value: String, overrideType: Node.OverrideType) -> Bool {
        if loc > readings.count {
            return false
        }
        let overlappingNodes = overlappingNodesAt(loc: loc == readings.count ? loc - 1 : loc)
        var overridden: NodeInSpan? = nil

        for nis in overlappingNodes {
            if let reading = reading, nis.node.reading != reading {
                continue
            }
            if nis.node.selectOverrideUnigram(value: value, type: overrideType) {
                overridden = nis
                break
            }
        }

        guard let overriddenNode = overridden else {
            return false
        }

        let start = overriddenNode.spanIndex
        let end = min(start + overriddenNode.node.spanningLength, spans.count)
        for i in start..<end {
            let nodes = overlappingNodesAt(loc: i)
            for nis in nodes {
                if nis.node !== overriddenNode.node {
                    nis.node.reset()
                }
            }
        }
        return true
    }

    public func findInSpan(cursor: Int, predicate: (Node) -> Bool) -> Node? {
        assert(cursor <= readings.count)
        let nodes = overlappingNodesAt(loc: cursor == readings.count ? cursor - 1 : cursor)
        return nodes.first { predicate($0.node) }?.node
    }

    // MARK: - Internal Helpers
    private func expandGridAt(loc: Int) {
        if loc == 0 || loc == spans.count {
            spans.insert(Span(), at: loc)
            return
        }
        spans.insert(Span(), at: loc)
        removeAffectedNodes(loc: loc)
    }

    private func shrinkGridAt(loc: Int) {
        if loc == spans.count {
            return
        }
        spans.remove(at: loc)
        removeAffectedNodes(loc: loc)
    }

    private func removeAffectedNodes(loc: Int) {
        if spans.isEmpty || loc == 0 {
            return
        }
        let affectedLength = ReadingGrid.maximumSpanLength - 1
        let begin = loc <= affectedLength ? 0 : loc - affectedLength
        let end = loc >= 1 ? loc - 1 : 0
        for i in begin...end {
            spans[i].removeNodesOfOrLongerThan(length: loc - i + 1)
        }
    }

    private func insert(loc: Int, node: Node) {
        assert(loc < spans.count)
        spans[loc].add(node)
    }

    private func combineReading(from begin: Int, to end: Int) -> String {
        readings[begin..<end].joined(separator: readingSeparator)
    }

    private func hasNodeAt(loc: Int, readingLen: Int, reading: String) -> Bool {
        if loc >= spans.count {
            return false
        }
        guard let n = spans[loc].nodeOf(length: readingLen) else {
            return false
        }
        return n.reading == reading
    }

    private func update(loc: Int, editType: EditType) {
        let affectedLength = ReadingGrid.maximumSpanLength - 1
        let begin = loc <= affectedLength ? 0 : loc - affectedLength
        var end = editType == .insertion ? loc + 1 : loc
        end = min(end, readings.count)

        if begin >= end { return }

        for pos in begin..<end {
            let minimumLength = loc - pos + 1
            let maximumLength = min(ReadingGrid.maximumSpanLength, readings.count - pos)
            if minimumLength > maximumLength { continue }
            for len in minimumLength...maximumLength {
                let combined = combineReading(from: pos, to: pos + len)
                if !hasNodeAt(loc: pos, readingLen: len, reading: combined) {
                    let unigrams = lm.getUnigrams(reading: combined)
                    if unigrams.isEmpty {
                        continue
                    }
                    insert(loc: pos, node: Node(reading: combined, spanningLength: len, unigrams: unigrams))
                }
            }
        }
    }

    public func overlappingNodesAt(loc: Int) -> [NodeInSpan] {
        var results: [NodeInSpan] = []
        if spans.isEmpty || loc >= spans.count {
            return results
        }

        // Span at loc
        let maxLen = spans[loc].maxLength
        if maxLen > 0 {
            for i in 1...maxLen {
                if let ptr = spans[loc].nodeOf(length: i) {
                    results.append(NodeInSpan(node: ptr, spanIndex: loc))
                }
            }
        }

        // Previous spans overlapping loc
        let begin = loc - min(loc, ReadingGrid.maximumSpanLength - 1)
        if begin < loc {
            for i in begin..<loc {
                let beginLen = loc - i + 1
                let endLen = spans[i].maxLength
                if beginLen <= endLen {
                    for j in beginLen...endLen {
                        if let ptr = spans[i].nodeOf(length: j) {
                            results.append(NodeInSpan(node: ptr, spanIndex: i))
                        }
                    }
                }
            }
        }
        return results
    }
}
