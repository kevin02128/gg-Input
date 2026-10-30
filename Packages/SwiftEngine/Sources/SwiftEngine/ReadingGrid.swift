import Foundation

public final class ReadingGrid {
    public static let maximumSpanLength: Int = 8
    public static let defaultSeparator: String = "-"
    public static let overridingScore: Double = 42.0
    public static let maximumContextCandidatesPerNode: Int = 32

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

        public var originalTopValue: String {
            unigrams.isEmpty ? "" : unigrams[0].value
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
                    return selectUnigramWithoutOverride(at: idx)
                }
            }
            return false
        }

        @discardableResult
        func selectUnigramWithoutOverride(at index: Int) -> Bool {
            guard overrideType == .none, unigrams.indices.contains(index) else { return false }
            unigramIndex = index
            return true
        }

        func contextWalkCandidateIndices(limit: Int) -> [Int] {
            guard !unigrams.isEmpty else { return [] }
            if overrideType != .none {
                return unigrams.indices.contains(unigramIndex) ? [unigramIndex] : [0]
            }

            let boundedLimit = max(1, min(limit, unigrams.count))
            var indices = Array(0..<boundedLimit)
            if unigramIndex >= boundedLimit && unigramIndex < unigrams.count {
                indices.append(unigramIndex)
            }
            return indices
        }

        func contextWalkBaseScore(candidateIndex: Int) -> Double {
            guard !unigrams.isEmpty, unigrams.indices.contains(candidateIndex) else { return 0.0 }
            switch overrideType {
            case .overrideValueWithHighScore:
                return ReadingGrid.overridingScore
            case .overrideValueWithScoreFromTopUnigram:
                return unigrams[0].score
            case .none:
                return unigrams[candidateIndex].score
            }
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
    public var characterBigramWeight: Double = 0.55
    public var characterTrigramWeight: Double = 1.0
    public var longWordBonusWeight: Double = 0.42
    public var posTransitionWeight: Double = 0.35
    public var posTransitionMatrix: POSTransitionMatrix = .default
    public var userOverrideModel: UserOverrideModel? = nil
    public private(set) var readings: [String] = []
    public private(set) var spans: [Span] = []
    private let lm: ScoreRankedLanguageModel

    public init(languageModel: LanguageModel, userOverrideModel: UserOverrideModel? = nil) {
        self.lm = ScoreRankedLanguageModel(languageModel: languageModel)
        self.userOverrideModel = userOverrideModel
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
            let previousStateID: Int?
            var fromNode: Node? = nil
            var unigramIndex: Int = 0
            var priorHanScalar: UInt32? = nil
            var lastHanScalar: UInt32? = nil
            var primaryPOS: POSTag = .none
            var secondaryPOS: POSTag = .none
            var score: Double = -Double.infinity
        }

        let readingLen = readings.count
        var statePool = [ViterbiState(
            previousStateID: nil,
            fromNode: nil,
            unigramIndex: 0,
            priorHanScalar: nil,
            lastHanScalar: nil,
            primaryPOS: .none,
            secondaryPOS: .none,
            score: 0.0
        )]
        var stateIDsAtPosition = Array(repeating: [Int](), count: readingLen + 1)
        var bestStateByLastScalarAtPosition = Array(repeating: [UInt64: Int](), count: readingLen + 1)
        stateIDsAtPosition[0] = [0]
        bestStateByLastScalarAtPosition[0][Self.contextStateKey(nil, nil)] = 0

        var reachableStates = 0
        var evaluatedEdges = 0

        for i in 0..<readingLen {
            guard !stateIDsAtPosition[i].isEmpty else { continue }
            reachableStates += 1
            let span = spans[i]
            let maxSpanLen = span.maxLength
            var edges: [(Node, Int)] = []
            if maxSpanLen > 0 {
                for spanLen in 1...maxSpanLen {
                    if let node = span.nodeOf(length: spanLen) {
                        edges.append((node, spanLen))
                    }
                }
            }

            // Preserve every reading even if a malformed or partially edited grid has a gap.
            if edges.isEmpty {
                let rawReading = readings[i]
                let fallback = Node(reading: rawReading, spanningLength: 1, unigrams: [Unigram(value: rawReading)])
                edges.append((fallback, 1))
            }

            for (node, spanLen) in edges {
                evaluatedEdges += 1
                let candidateIndices = node.contextWalkCandidateIndices(limit: Self.maximumContextCandidatesPerNode)
                for stateID in stateIDsAtPosition[i] {
                    let previousState = statePool[stateID]
                    guard bestStateByLastScalarAtPosition[i][Self.contextStateKey(previousState.priorHanScalar, previousState.lastHanScalar)] == stateID else {
                        continue
                    }
                    for candidateIndex in candidateIndices {
                        let unigram = node.unigrams[candidateIndex]
                        let characterContext = Self.characterContextScore(
                            for: unigram.value,
                            priorHanScalar: previousState.priorHanScalar,
                            previousHanScalar: previousState.lastHanScalar,
                            languageModel: lm
                        )
                        let longWordBonus: Double
                        if node.overrideType != .none {
                            longWordBonus = 0.0
                        } else {
                            longWordBonus = longWordBonusWeight * min(Double(max(0, node.spanningLength - 1)), 2.0)
                        }
                        let posScore: Double
                        if previousState.primaryPOS != .none && unigram.primaryPOS != .none {
                            let rawPos = posTransitionMatrix.maxTransitionScore(
                                prevPrimary: previousState.primaryPOS,
                                prevSecondary: previousState.secondaryPOS,
                                currPrimary: unigram.primaryPOS,
                                currSecondary: unigram.secondaryPOS
                            )
                            posScore = Double(rawPos) * posTransitionWeight
                        } else {
                            posScore = 0.0
                        }
                        let userBoost: Double
                        if let overrideModel = userOverrideModel {
                            let topScore = node.unigrams.first?.score ?? 0.0
                            let priorWord = previousState.fromNode?.value ?? "_START_"
                            userBoost = overrideModel.scoreBoost(
                                priorWord: priorWord,
                                reading: node.reading,
                                candidate: unigram.value,
                                syllableLength: node.spanningLength,
                                topScore: topScore,
                                candidateScore: unigram.score,
                                timestamp: Date().timeIntervalSince1970
                            )
                        } else {
                            userBoost = 0.0
                        }

                        let score = previousState.score
                            + node.contextWalkBaseScore(candidateIndex: candidateIndex)
                            + longWordBonus
                            + characterContext.bigramScore * characterBigramWeight
                            + characterContext.trigramScore * characterTrigramWeight
                            + posScore
                            + userBoost
                        let nextPosition = i + spanLen
                        let stateKey = Self.contextStateKey(characterContext.priorHanScalar, characterContext.lastHanScalar)

                        if let existingID = bestStateByLastScalarAtPosition[nextPosition][stateKey],
                           score <= statePool[existingID].score {
                            continue
                        }

                        let newStateID = statePool.count
                        statePool.append(ViterbiState(
                            previousStateID: stateID,
                            fromNode: node,
                            unigramIndex: candidateIndex,
                            priorHanScalar: characterContext.priorHanScalar,
                            lastHanScalar: characterContext.lastHanScalar,
                            primaryPOS: unigram.primaryPOS,
                            secondaryPOS: unigram.secondaryPOS,
                            score: score
                        ))
                        bestStateByLastScalarAtPosition[nextPosition][stateKey] = newStateID
                        stateIDsAtPosition[nextPosition].append(newStateID)
                    }
                }
            }
        }

        result.vertices = reachableStates
        result.edges = evaluatedEdges

        let endStateID = stateIDsAtPosition[readingLen].max { lhs, rhs in
            statePool[lhs].score < statePool[rhs].score
        }
        if let endStateID = endStateID {
            var selectedStates: [ViterbiState] = []
            var currentStateID: Int? = endStateID
            while let stateID = currentStateID, stateID != 0 {
                let state = statePool[stateID]
                selectedStates.append(state)
                currentStateID = state.previousStateID
            }
            selectedStates.reverse()

            for state in selectedStates {
                guard let node = state.fromNode else { continue }
                if node.overrideType == .none {
                    _ = node.selectUnigramWithoutOverride(at: state.unigramIndex)
                }
                result.nodes.append(node)
            }
            result.totalReadings = result.nodes.reduce(0) { $0 + $1.spanningLength }
            result.totalScore = statePool[endStateID].score
        }

        let endTime = DispatchTime.now()
        let nanos = endTime.uptimeNanoseconds - startTime.uptimeNanoseconds
        result.elapsedMicroseconds = nanos / 1000
        return result
    }

    private static func contextStateKey(_ first: UInt32?, _ second: UInt32?) -> UInt64 {
        let sentinel: UInt64 = 0x1FFFFF
        let firstValue = first.map(UInt64.init) ?? sentinel
        let secondValue = second.map(UInt64.init) ?? sentinel
        return (firstValue << 21) | secondValue
    }

    private static func isHanScalar(_ value: UInt32) -> Bool {
        (0x3400...0x4DBF).contains(value)
            || (0x4E00...0x9FFF).contains(value)
            || (0xF900...0xFAFF).contains(value)
            || (0x20000...0x323AF).contains(value)
    }

    private static func characterContextScore(
        for value: String,
        priorHanScalar: UInt32?,
        previousHanScalar: UInt32?,
        languageModel: ScoreRankedLanguageModel
    ) -> (bigramScore: Double, trigramScore: Double, priorHanScalar: UInt32?, lastHanScalar: UInt32?) {
        var bigramScore = 0.0
        var trigramScore = 0.0
        var priorScalar = priorHanScalar
        var previousScalar = previousHanScalar
        var lastHanScalar: UInt32?

        for scalar in value.unicodeScalars {
            let current = scalar.value
            guard isHanScalar(current) else {
                priorScalar = nil
                previousScalar = nil
                lastHanScalar = nil
                continue
            }

            if let previousScalar = previousScalar {
                bigramScore += languageModel.characterBigramAssociationScore(previous: previousScalar, next: current)
            }
            if let priorScalar = priorScalar, let previousScalar = previousScalar {
                trigramScore += languageModel.characterTrigramAssociationScore(first: priorScalar, second: previousScalar, next: current)
            }
            priorScalar = previousScalar
            previousScalar = current
            lastHanScalar = current
        }

        return (bigramScore, trigramScore, priorScalar, lastHanScalar)
    }

    // MARK: - Candidates
    public func nodeAt(loc: Int, length: Int) -> Node? {
        guard loc >= 0, loc < spans.count, length >= 1, length <= ReadingGrid.maximumSpanLength else {
            return nil
        }
        return spans[loc].nodeOf(length: length)
    }

    public func candidatesAt(loc: Int) -> [Candidate] {
        var result: [Candidate] = []
        if readings.isEmpty || loc > readings.count {
            return result
        }

        var nodes = overlappingNodesAt(loc: loc == readings.count ? loc - 1 : loc)
        nodes.sort { $0.node.spanningLength > $1.node.spanningLength }

        for nodeInSpan in nodes {
            let node = nodeInSpan.node
            for unigram in node.unigrams {
                result.append(Candidate(reading: node.reading,
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
