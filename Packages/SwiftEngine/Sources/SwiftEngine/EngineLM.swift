import Foundation

public final class EngineLM: LanguageModel {
    public static let macroPrefix = "MACRO@"
    public static let macroScore = -8.0

    public struct AssociatedPhrase: Equatable {
        public let value: String
        public let readings: [String]

        public init(value: String, readings: [String]) {
            self.value = value
            self.readings = readings
        }

        public var combinedReading: String {
            readings.joined(separator: "-")
        }
    }

    public enum IssueType: Equatable {
        case missingSecondColumn
        case nullCharacterInText
    }

    public enum UserFileType: Equatable {
        case userPhrases
        case excludedPhrases
        case phraseReplacementMap
    }

    public struct UserFileIssue: Equatable {
        public let fileType: UserFileType
        public let path: String
        public let issueType: IssueType
        public let lineNumber: Int

        public init(fileType: UserFileType, path: String, issueType: IssueType, lineNumber: Int) {
            self.fileType = fileType
            self.path = path
            self.issueType = issueType
            self.lineNumber = lineNumber
        }
    }

    // Databases
    public let primaryDB = PhraseDB()
    public let associatedPhrasesDB = PhraseDB()
    public let puaDB = PhraseDB()
    public let variantsDB = PhraseDB()

    // User data in-memory dictionaries
    public private(set) var userPhrases: [String: [String]] = [:] // reading -> [value]
    public private(set) var excludedPhrases: [String: Set<String>] = [:] // reading -> Set<value>
    public private(set) var phraseReplacementMap: [String: String] = [:] // value -> replacement

    public private(set) var userPhrasesPath: String? = nil
    public private(set) var excludedPhrasesPath: String? = nil
    public private(set) var phraseReplacementPath: String? = nil

    private var userPhrasesIssues: [UserFileIssue] = []
    private var excludedPhrasesIssues: [UserFileIssue] = []
    private var phraseReplacementIssues: [UserFileIssue] = []

    // Settings & Converters
    public var phraseReplacementEnabled: Bool = false
    public var externalConverterEnabled: Bool = false
    public var macroConverter: ((String) -> String)? = nil
    public var externalConverter: ((String) -> String)? = nil

    public init() {}

    // MARK: - Loading
    public func loadLanguageModel(path: String) -> Bool {
        primaryDB.open(path: path)
    }

    public var isDataModelLoaded: Bool {
        primaryDB.isLoaded
    }

    public func loadAssociatedPhrases(path: String) -> Bool {
        associatedPhrasesDB.open(path: path)
    }

    public var isAssociatedPhrasesLoaded: Bool {
        associatedPhrasesDB.isLoaded
    }

    public func loadVariantAnnotator(puaPath: String, variantsPath: String) -> Bool {
        let puaLoaded = puaDB.open(path: puaPath)
        let variantsLoaded = variantsDB.open(path: variantsPath)
        return puaLoaded && variantsLoaded
    }

    public var isVariantAnnotatorLoaded: Bool {
        puaDB.isLoaded && variantsDB.isLoaded
    }

    // MARK: - User Phrases & Replacements
    public func loadUserPhrases(userPhrasesPath: String?, excludedPhrasesPath: String?) {
        self.userPhrasesPath = userPhrasesPath
        self.excludedPhrasesPath = excludedPhrasesPath
        self.userPhrases.removeAll()
        self.userPhrasesIssues.removeAll()
        self.excludedPhrases.removeAll()
        self.excludedPhrasesIssues.removeAll()

        if let path = userPhrasesPath, let content = try? String(contentsOfFile: path, encoding: .utf8) {
            parseUserPhrases(content: content, path: path, fileType: .userPhrases) { key, val in
                self.userPhrases[key, default: []].append(val)
            } issues: { issues in
                self.userPhrasesIssues = issues
            }
        }

        if let path = excludedPhrasesPath, let content = try? String(contentsOfFile: path, encoding: .utf8) {
            parseUserPhrases(content: content, path: path, fileType: .excludedPhrases) { key, val in
                self.excludedPhrases[key, default: []].insert(val)
            } issues: { issues in
                self.excludedPhrasesIssues = issues
            }
        }
    }

    public func loadPhraseReplacementMap(path: String?) {
        self.phraseReplacementPath = path
        self.phraseReplacementMap.removeAll()
        self.phraseReplacementIssues.removeAll()

        guard let path = path, let content = try? String(contentsOfFile: path, encoding: .utf8) else {
            return
        }

        var issues: [UserFileIssue] = []
        let lines = content.components(separatedBy: "\n")
        for (idx, line) in lines.enumerated() {
            let lineNum = idx + 1
            if line.contains("\0") {
                issues.append(UserFileIssue(fileType: .phraseReplacementMap, path: path, issueType: .nullCharacterInText, lineNumber: lineNum))
                continue
            }
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty || trimmed.hasPrefix("#") {
                continue
            }

            // Key-then-value mode: first word is key, rest is value
            let parts = trimmed.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true)
            if parts.count < 2 {
                issues.append(UserFileIssue(fileType: .phraseReplacementMap, path: path, issueType: .missingSecondColumn, lineNumber: lineNum))
                continue
            }
            let key = String(parts[0])
            let val = String(parts[1]).trimmingCharacters(in: .whitespaces)
            self.phraseReplacementMap[key] = val
        }
        self.phraseReplacementIssues = issues
    }

    private func parseUserPhrases(content: String, path: String, fileType: UserFileType, addPair: (String, String) -> Void, issues: ([UserFileIssue]) -> Void) {
        var collectedIssues: [UserFileIssue] = []
        let lines = content.components(separatedBy: "\n")
        for (idx, line) in lines.enumerated() {
            let lineNum = idx + 1
            if line.contains("\0") {
                collectedIssues.append(UserFileIssue(fileType: fileType, path: path, issueType: .nullCharacterInText, lineNumber: lineNum))
                continue
            }
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty || trimmed.hasPrefix("#") {
                continue
            }

            // Value-then-key mode: last token is key, everything before is value
            guard let lastSpace = trimmed.lastIndex(where: { $0 == " " || $0 == "\t" }) else {
                collectedIssues.append(UserFileIssue(fileType: fileType, path: path, issueType: .missingSecondColumn, lineNumber: lineNum))
                continue
            }
            let val = String(trimmed[..<lastSpace]).trimmingCharacters(in: .whitespaces)
            let key = String(trimmed[trimmed.index(after: lastSpace)...]).trimmingCharacters(in: .whitespaces)
            if val.isEmpty || key.isEmpty {
                collectedIssues.append(UserFileIssue(fileType: fileType, path: path, issueType: .missingSecondColumn, lineNumber: lineNum))
                continue
            }
            addPair(key, val)
        }
        issues(collectedIssues)
    }

    public func getUserFileIssues() -> [UserFileIssue] {
        userPhrasesIssues + excludedPhrasesIssues + phraseReplacementIssues
    }

    // MARK: - Unigram Lookups
    public func getUnigrams(reading: String) -> [Unigram] {
        if reading == " " {
            return [Unigram(value: " ", score: 0.0)]
        }

        var allUnigrams: [Unigram] = []
        var userUnigramList: [Unigram] = []

        let excludedSet = excludedPhrases[reading] ?? []
        var insertedValues = Set<String>()

        if let rawUserVals = userPhrases[reading] {
            let rawUnigrams = rawUserVals.map { Unigram(value: $0, score: 0.0) }
            userUnigramList = filterAndTransformUnigrams(unigrams: rawUnigrams, excludedValues: excludedSet, insertedValues: &insertedValues)
        }

        let rawGlobalUnigrams = primaryDB.getUnigrams(reading: reading)
        if !rawGlobalUnigrams.isEmpty {
            allUnigrams = filterAndTransformUnigrams(unigrams: rawGlobalUnigrams, excludedValues: excludedSet, insertedValues: &insertedValues)
        }

        let isKeyMultiSyllable = reading.contains("-")

        if isKeyMultiSyllable || allUnigrams.isEmpty {
            allUnigrams.insert(contentsOf: userUnigramList, at: 0)
        } else if !userUnigramList.isEmpty {
            var topScore = -Double.greatestFiniteMagnitude
            for u in allUnigrams {
                topScore = max(topScore, u.score)
            }
            let epsilon = 0.000000001
            let boostedScore = topScore + epsilon
            let rewrittenUserUnigrams = userUnigramList.map {
                Unigram(value: $0.value, score: boostedScore, rawValue: $0.rawValue)
            }
            allUnigrams.insert(contentsOf: rewrittenUserUnigrams, at: 0)
        }

        return allUnigrams
    }

    public func hasUnigrams(reading: String) -> Bool {
        if reading == " " {
            return true
        }
        if excludedPhrases[reading] == nil {
            return userPhrases[reading] != nil || primaryDB.hasUnigrams(reading: reading)
        }
        return !getUnigrams(reading: reading).isEmpty
    }

    private func filterAndTransformUnigrams(unigrams: [Unigram], excludedValues: Set<String>, insertedValues: inout Set<String>) -> [Unigram] {
        var results: [Unigram] = []

        for unigram in unigrams {
            let rawValue = unigram.value
            if excludedValues.contains(rawValue) {
                continue
            }

            var value = rawValue
            if phraseReplacementEnabled, let replacement = phraseReplacementMap[value], !replacement.isEmpty {
                value = replacement
            }

            if let macroConverter = macroConverter {
                let replaced = macroConverter(value)
                if replaced != value {
                    value = replaced
                }
            }

            // Check if string is an unsupported macro
            if unigram.score == Self.macroScore && value.hasPrefix(Self.macroPrefix) {
                continue
            }

            if externalConverterEnabled, let externalConverter = externalConverter {
                let replaced = externalConverter(value)
                if replaced != value {
                    value = replaced
                }
            }

            if !insertedValues.contains(value) {
                results.append(Unigram(value: value, score: unigram.score, rawValue: rawValue))
                insertedValues.insert(value)
            }
        }
        return results
    }

    // MARK: - Reverse Lookup
    public func getReading(for phrase: String) -> String? {
        let results = primaryDB.reverseFindRows(value: phrase)
        var topScore = -Double.greatestFiniteMagnitude
        var topReading: String? = nil
        for r in results {
            if r.score > topScore {
                topScore = r.score
                topReading = r.reading
            }
        }
        return topReading
    }

    // MARK: - Associated Phrases
    public func findAssociatedPhrases(prefixValue: String, prefixReadings: [String]) -> [AssociatedPhrase] {
        guard !prefixValue.isEmpty, associatedPhrasesDB.isLoaded else {
            return []
        }

        let internalPrefix: String
        if prefixReadings.isEmpty {
            internalPrefix = prefixValue + "-"
        } else {
            let chars = prefixValue.map { String($0) }
            if chars.count != prefixReadings.count {
                return []
            }
            var s = ""
            for i in 0..<chars.count {
                s += chars[i] + "-" + prefixReadings[i] + "-"
            }
            internalPrefix = s
        }

        let rows = associatedPhrasesDB.findRows(prefix: internalPrefix)
        if rows.isEmpty {
            return []
        }

        // Pair of (row, score)
        var scoredRows: [(row: String, score: Double)] = []
        for row in rows {
            var score = -Double.greatestFiniteMagnitude
            if let lastSpace = row.lastIndex(of: " ") {
                let scoreStr = row[row.index(after: lastSpace)...]
                score = Double(scoreStr) ?? score
            }
            scoredRows.append((row, score))
        }

        scoredRows.sort { $0.score > $1.score }

        var dedupSet = Set<String>()
        var phrases: [AssociatedPhrase] = []

        for item in scoredRows {
            guard let parsed = parseAssociatedPhraseRow(item.row) else {
                continue
            }
            if dedupSet.contains(parsed.value) {
                continue
            }
            dedupSet.insert(parsed.value)
            phrases.append(parsed)
        }

        return phrases
    }

    private func parseAssociatedPhraseRow(_ row: String) -> AssociatedPhrase? {
        // Cut off score
        let content: Substring
        if let lastSpace = row.lastIndex(of: " ") {
            content = row[..<lastSpace]
        } else {
            content = Substring(row)
        }

        var fullValue = ""
        var readings: [String] = []

        let tokens = content.split(separator: "-")
        var i = 0
        while i + 1 < tokens.count {
            fullValue += tokens[i]
            readings.append(String(tokens[i + 1]))
            i += 2
        }

        if fullValue.isEmpty {
            return nil
        }
        return AssociatedPhrase(value: fullValue, readings: readings)
    }

    // MARK: - Variant Annotation
    public func annotateVariant(characters: [String], readings: [String]) -> (annotatedString: String, hasVariants: Bool, hasPUAs: Bool, accumulatedLengths: [Int]) {
        guard characters.count == readings.count, isVariantAnnotatorLoaded else {
            let joined = characters.joined()
            return (annotatedString: joined, hasVariants: false, hasPUAs: false, accumulatedLengths: [0, joined.utf8.count])
        }

        var accumulatedLengths: [Int] = [0]
        var annotatedString = ""
        var hasVariants = false
        var hasPUAs = false

        for i in 0..<characters.count {
            let val = characters[i]
            let reading = readings[i]

            let res = annotateSingleCharacter(value: val, reading: reading)
            annotatedString += res.annotated
            if res.hasVariants { hasVariants = true }
            if res.hasPUAs { hasPUAs = true }
            accumulatedLengths.append(annotatedString.utf8.count)
        }

        return (annotatedString, hasVariants, hasPUAs, accumulatedLengths)
    }

    private func annotateSingleCharacter(value: String, reading: String) -> (annotated: String, hasVariants: Bool, hasPUAs: Bool) {
        // 1. Try default or annotated variant
        let key1 = value + "-" + reading + " "
        let rows1 = variantsDB.findRows(prefix: key1)
        if let first = rows1.first, let secondCol = getSecondColumn(row: first) {
            let selectorUsed = (secondCol != value)
            return (secondCol, selectorUsed, false)
        }

        // 2. Try unannotated fallback
        let key2 = value + "-na "
        let rows2 = variantsDB.findRows(prefix: key2)
        if let first = rows2.first, let secondCol = getSecondColumn(row: first) {
            if secondCol == value {
                return (value, false, false)
            }
            // Look up PUA block
            let puaKey = reading + " "
            let puaRows = puaDB.findRows(prefix: puaKey)
            if let puaFirst = puaRows.first, let puaCol = getSecondColumn(row: puaFirst) {
                return (secondCol + puaCol, true, true)
            }
            return (secondCol, true, false)
        }

        return (value, false, false)
    }

    private func getSecondColumn(row: String) -> String? {
        guard let firstSpace = row.firstIndex(of: " ") else { return nil }
        return String(row[row.index(after: firstSpace)...]).trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
