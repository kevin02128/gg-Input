import Foundation

public protocol LanguageModel: AnyObject {
    func getUnigrams(reading: String) -> [Unigram]
    func hasUnigrams(reading: String) -> Bool
    func characterBigramAssociationScore(previous: UInt32, next: UInt32) -> Double
    func characterTrigramAssociationScore(first: UInt32, second: UInt32, next: UInt32) -> Double
}

public extension LanguageModel {
    func characterBigramAssociationScore(previous: UInt32, next: UInt32) -> Double {
        0.0
    }

    func characterTrigramAssociationScore(first: UInt32, second: UInt32, next: UInt32) -> Double {
        0.0
    }
}

public struct Unigram: Equatable, Hashable, Sendable {
    public let value: String
    public let score: Double
    public let rawValue: String
    public let primaryPOS: POSTag
    public let secondaryPOS: POSTag

    public init(
        value: String = "",
        score: Double = 0.0,
        rawValue: String = "",
        primaryPOS: POSTag = .none,
        secondaryPOS: POSTag = .none
    ) {
        self.value = value
        self.score = score
        self.rawValue = rawValue
        self.primaryPOS = primaryPOS
        self.secondaryPOS = secondaryPOS
    }
}

public final class ScoreRankedLanguageModel: LanguageModel {
    private let lm: LanguageModel

    public init(languageModel: LanguageModel) {
        self.lm = languageModel
    }

    public func getUnigrams(reading: String) -> [Unigram] {
        var unigrams = lm.getUnigrams(reading: reading)
        unigrams.sort { $0.score > $1.score }
        return unigrams
    }

    public func hasUnigrams(reading: String) -> Bool {
        lm.hasUnigrams(reading: reading)
    }

    public func characterBigramAssociationScore(previous: UInt32, next: UInt32) -> Double {
        lm.characterBigramAssociationScore(previous: previous, next: next)
    }

    public func characterTrigramAssociationScore(first: UInt32, second: UInt32, next: UInt32) -> Double {
        lm.characterTrigramAssociationScore(first: first, second: second, next: next)
    }
}
