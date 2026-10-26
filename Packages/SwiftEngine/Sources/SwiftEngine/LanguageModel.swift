import Foundation

public protocol LanguageModel: AnyObject {
    func getUnigrams(reading: String) -> [Unigram]
    func hasUnigrams(reading: String) -> Bool
}

public struct Unigram: Equatable, Hashable, Sendable {
    public let value: String
    public let score: Double
    public let rawValue: String

    public init(value: String = "", score: Double = 0.0, rawValue: String = "") {
        self.value = value
        self.score = score
        self.rawValue = rawValue
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
}
