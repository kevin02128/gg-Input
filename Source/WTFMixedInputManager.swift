// Copyright (c) 2026 wtf. All rights reserved.
// WTFMixedInputManager.swift
// gg 輸入法 (公司: wtf) - 中英混打雙軌引擎

import Cocoa
import Foundation

public class WTFMixedInputManager {
    public static let shared = WTFMixedInputManager()

    // MARK: - 大千注音鍵盤映射
    public struct Daqian {
        public static let initials: [Character: String] = [
            "1": "ㄅ", "q": "ㄆ", "a": "ㄇ", "z": "ㄈ",
            "2": "ㄉ", "w": "ㄊ", "s": "ㄋ", "x": "ㄌ",
            "e": "ㄍ", "d": "ㄎ", "c": "ㄏ",
            "r": "ㄐ", "f": "ㄑ", "v": "ㄒ",
            "5": "ㄓ", "t": "ㄔ", "g": "ㄕ", "b": "ㄖ",
            "y": "ㄗ", "h": "ㄘ", "n": "ㄙ"
        ]
        public static let medials: [Character: String] = [
            "u": "ㄧ", "j": "ㄨ", "m": "ㄩ"
        ]
        public static let finals: [Character: String] = [
            "8": "ㄚ", "i": "ㄛ", "k": "ㄜ", ",": "ㄝ",
            "9": "ㄞ", "o": "ㄟ", "l": "ㄠ", ".": "ㄡ",
            "0": "ㄢ", "p": "ㄣ", ";": "ㄤ", "/": "ㄥ",
            "-": "ㄦ"
        ]
        public static let tones: [Character: String] = [
            " ": " ", "6": "ˊ", "3": "ˇ", "4": "ˋ", "7": "˙"
        ]
    }

    // MARK: - 數字與大千注音鍵盤分類
    public static let toneDigits: Set<Character> = ["3", "4", "6", "7"]
    public static let nonToneDigits: Set<Character> = ["1", "2", "5", "8", "9", "0"]
    public static let bopomofoInitialDigits: Set<Character> = ["1", "2", "5"]
    public static let bopomofoFinalDigits: Set<Character> = ["8", "9", "0"]

    // MARK: - 常見科技短字與縮寫對應表 (Acronyms & Short Tokens)
    public static let knownSpecAcronyms: [String: String] = [
        "4k": "4K", "8k": "8K", "3d": "3D", "5g": "5G", "4g": "4G",
        "3c": "3C", "2b": "2B", "1a": "1A", "m1": "M1", "m2": "M2",
        "m3": "M3", "m4": "M4", "a4": "A4", "b5": "B5", "ps5": "PS5",
        "b2b": "B2B", "b2c": "B2C", "p2p": "P2P", "ai": "AI",
        "ui": "UI", "ux": "UX", "pm": "PM", "api": "API",
        "sdk": "SDK", "app": "App"
    ]

    public static func resolveCommittedEnglish(_ text: String) -> String {
        let lower = text.lowercased()
        if let mapped = knownSpecAcronyms[lower] {
            return mapped
        }
        return text
    }

    public static func isShortTokenOrAcronym(_ text: String) -> Bool {
        let lower = text.lowercased()
        if knownSpecAcronyms[lower] != nil {
            return true
        }
        let hasLetter = text.contains(where: { ($0 >= "a" && $0 <= "z") || ($0 >= "A" && $0 <= "Z") })
        let hasDigit = text.contains(where: { $0 >= "0" && $0 <= "9" })
        return hasLetter && hasDigit
    }

    // MARK: - 屬性
    public let isEnabled: Bool = true
    public let panguSpacingEnabled: Bool = true
    public var lastCommittedChar: Character? = nil
    public var lastCommitWasEnglishWord: Bool = false
    public var associatedSuggestion: String? = nil // 中文 Tab 聯想字
    
    public var currentBuffer: String = ""
    public var predictedWord: String? = nil
    public var isPureEnglishMode: Bool = false

    public func enterPureEnglishMode(buffer: String, prediction: String?) {
        self.isPureEnglishMode = true
        self.currentBuffer = buffer
        self.predictedWord = prediction
    }

    // MARK: - 中英自動空格 (Pangu Auto-Spacing) 判斷與格式化
    public static func isCJK(_ ch: Character) -> Bool {
        guard let scalar = ch.unicodeScalars.first, ch.unicodeScalars.count == 1 else {
            return false
        }
        let v = scalar.value
        return (v >= 0x4E00 && v <= 0x9FFF)
            || (v >= 0x3400 && v <= 0x4DBF)
            || (v >= 0xF900 && v <= 0xFAFF)
    }

    public static func isBopomofoOrCJK(_ ch: Character) -> Bool {
        if isCJK(ch) { return true }
        guard let scalar = ch.unicodeScalars.first, ch.unicodeScalars.count == 1 else {
            return false
        }
        let v = scalar.value
        return (v >= 0x3100 && v <= 0x312F) || (v == 0x02CA || v == 0x02C7 || v == 0x02CB || v == 0x02D9)
    }

    public static func isASCIIAlphanumeric(_ ch: Character) -> Bool {
        return (ch >= "a" && ch <= "z")
            || (ch >= "A" && ch <= "Z")
            || (ch >= "0" && ch <= "9")
    }

    public static func needsPanguSpace(left: Character, right: Character) -> Bool {
        if isCJK(left) && isASCIIAlphanumeric(right) {
            return true
        }
        if isASCIIAlphanumeric(left) && isCJK(right) {
            return true
        }
        if (left == "%" || left == "+" || left == "#") && isCJK(right) {
            return true
        }
        return false
    }

    /// 對單一字串內部的中英交界自動補上空格（例如「測試API功能」->「測試 API 功能」）
    public static func formatInternalPanguSpacing(_ text: String) -> String {
        guard text.count >= 2 else { return text }
        let chars = Array(text)
        var result: [Character] = []
        result.reserveCapacity(chars.count + 4)
        result.append(chars[0])

        for i in 1..<chars.count {
            let prev = chars[i - 1]
            let curr = chars[i]
            if needsPanguSpace(left: prev, right: curr) {
                if prev == "%" || prev == "+" || prev == "#" {
                    if i >= 2 && (isASCIIAlphanumeric(chars[i - 2]) || chars[i - 2] == "+") {
                        result.append(" ")
                    }
                } else {
                    result.append(" ")
                }
            }
            result.append(curr)
        }
        return String(result)
    }

    /// 對即將送出的文字套用內部與跨次送出的中英自動空格
    public func applyPanguSpacing(
        to text: String,
        isEnglishWord: Bool = false,
        precedingChar: Character? = nil
    ) -> String {
        guard !text.isEmpty else { return text }
        guard panguSpacingEnabled else {
            lastCommittedChar = text.last
            lastCommitWasEnglishWord = isEnglishWord
            return text
        }

        var formatted = Self.formatInternalPanguSpacing(text)
        let prev = precedingChar ?? lastCommittedChar

        if let prev = prev, let first = formatted.first, first != " " {
            if Self.needsPanguSpace(left: prev, right: first) {
                formatted = " " + formatted
            } else if lastCommitWasEnglishWord && isEnglishWord && Self.isASCIIAlphanumeric(prev) && Self.isASCIIAlphanumeric(first) {
                formatted = " " + formatted
            }
        }

        lastCommittedChar = formatted.last
        lastCommitWasEnglishWord = isEnglishWord
        return formatted
    }

    public func resetCommittedContext() {
        lastCommittedChar = nil
        lastCommitWasEnglishWord = false
    }

    private var englishWordList: [String] = []
    private var lowercasedWordList: [String] = []
    private var exactWordSet: Set<String> = []
    private var wordsByFirstChar: [Character: [Int]] = [:]

    private init() {
        loadEnglishDictionary()
    }

    // MARK: - 載入英文詞典 (按詞頻降序排列)
    private func loadEnglishDictionary() {
        var dictPath: String? = Bundle(for: WTFMixedInputManager.self).path(forResource: "english-words", ofType: "txt")
        if dictPath == nil {
            dictPath = Bundle.main.path(forResource: "english-words", ofType: "txt")
        }
        if dictPath == nil, let resourcePath = Bundle.main.resourcePath {
            let direct = (resourcePath as NSString).appendingPathComponent("english-words.txt")
            if FileManager.default.fileExists(atPath: direct) {
                dictPath = direct
            }
        }
        if dictPath == nil {
            let bundleResource = Bundle.main.bundlePath + "/Contents/Resources/english-words.txt"
            if FileManager.default.fileExists(atPath: bundleResource) {
                dictPath = bundleResource
            }
        }
        
        var words: [String] = []
        if let path = dictPath, let content = try? String(contentsOfFile: path, encoding: .utf8) {
            words.reserveCapacity(60000)
            content.enumerateLines { line, stop in
                let parts = line.split(separator: "\t")
                if let first = parts.first {
                    words.append(String(first))
                }
                if words.count >= 60000 {
                    stop = true
                }
            }
        } else {
            words = [
                "the", "be", "to", "of", "and", "a", "in", "that", "have", "i",
                "it", "for", "not", "on", "with", "he", "as", "you", "do", "at",
                "this", "but", "his", "by", "from", "they", "we", "say", "her",
                "she", "or", "an", "will", "my", "one", "all", "would", "there",
                "their", "what", "so", "up", "out", "if", "about", "who", "get",
                "which", "go", "me", "when", "make", "can", "like", "time", "no",
                "just", "him", "know", "take", "people", "into", "year", "your",
                "good", "some", "could", "them", "see", "other", "than", "then",
                "now", "look", "only", "come", "its", "over", "think", "also",
                "back", "after", "use", "two", "how", "our", "work", "first",
                "well", "way", "even", "new", "want", "because", "any", "these",
                "give", "day", "most", "us", "hello", "quality", "such", "test",
                "useState", "useEffect", "useReducer", "update", "function"
            ]
        }

        self.englishWordList = words
        let lowerWords = words.map { $0.lowercased() }
        self.lowercasedWordList = lowerWords
        self.exactWordSet = Set(lowerWords)

        var byFirst: [Character: [Int]] = [:]
        for (idx, word) in lowerWords.enumerated() {
            if let first = word.first {
                byFirst[first, default: []].append(idx)
            }
        }
        self.wordsByFirstChar = byFirst
    }

    // MARK: - 注音合法性檢測 (單一音節智慧容錯狀態機)
    public func validateBopomofo(input: String) -> (isValid: Bool, bopomofoStr: String) {
        if input.isEmpty {
            return (true, "")
        }
        if input.contains(where: { $0.isUppercase }) {
            return (false, "")
        }

        var initCharStr = ""
        var medCharStr = ""
        var finCharStr = ""
        var toneCharStr = ""

        for char in input.lowercased() {
            if !toneCharStr.isEmpty {
                return (false, initCharStr + medCharStr + finCharStr + toneCharStr)
            }

            if let initChar = Daqian.initials[char] {
                if !initCharStr.isEmpty || !medCharStr.isEmpty || !finCharStr.isEmpty {
                    return (false, initCharStr + medCharStr + finCharStr + toneCharStr)
                }
                initCharStr = initChar
            } else if let medChar = Daqian.medials[char] {
                if !medCharStr.isEmpty {
                    return (false, initCharStr + medCharStr + finCharStr + toneCharStr)
                }
                medCharStr = medChar
            } else if let finChar = Daqian.finals[char] {
                if !finCharStr.isEmpty {
                    return (false, initCharStr + medCharStr + finCharStr + toneCharStr)
                }
                finCharStr = finChar
            } else if let toneChar = Daqian.tones[char] {
                toneCharStr = toneChar
            } else {
                return (false, initCharStr + medCharStr + finCharStr + toneCharStr)
            }
        }
        let canonicalBpmf = initCharStr + medCharStr + finCharStr + toneCharStr
        // 聲調符號不能單獨存在作為音節，必須伴隨聲母、介音或韻母
        if !toneCharStr.isEmpty && initCharStr.isEmpty && medCharStr.isEmpty && finCharStr.isEmpty {
            return (false, canonicalBpmf)
        }
        return (true, canonicalBpmf)
    }

    // MARK: - 英數混打相衝偵測 (Dual-Track Alphanumeric Collision Detection)
    public func checkAlphanumericCollision(buffer: String, nextChar: Character) -> Bool {
        if isPureEnglishMode {
            return false
        }
        guard !buffer.isEmpty else {
            return false
        }

        let lowerNext = Character(String(nextChar).lowercased())
        let isNextLetter = (lowerNext >= "a" && lowerNext <= "z")
        let isNextDigit = (nextChar >= "0" && nextChar <= "9")

        // Rule A: 聲調起首短字 (Isolated Tone Prefix Collision)
        // 若目前 buffer 為單獨聲調數字 (3, 4, 6, 7)，下一個鍵按字母 (a-z)
        // 注音語法絕不可能以聲調開頭後接字母 -> 判定為相衝 (如 4k, 3d, 3c)
        if buffer.count == 1, let firstChar = buffer.first, Self.toneDigits.contains(firstChar), isNextLetter {
            return true
        }

        // Rule B: 注音數字起首相衝 (Digit-Bopomofo Collision)
        // 若目前 buffer 開頭為非聲調數字 (1, 2, 5, 8, 9, 0)，下一個鍵為字母：
        // 1. 聲母數字 (5=ㄓ, 1=ㄅ, 2=ㄉ) 後接聲母字母 (如 5+g = ㄓ+ㄕ 雙聲母相衝，如 5g)
        // 2. 韻母數字 (8=ㄚ, 9=ㄞ, 0=ㄢ) 後接韻母字母 (如 8+k = ㄚ+ㄜ 雙韻母相衝，如 8k)
        // 3. 任何無法組成單一合法注音之組合
        if buffer.count == 1, let firstChar = buffer.first, Self.nonToneDigits.contains(firstChar), isNextLetter {
            let combined = buffer + String(lowerNext)
            if !validateBopomofo(input: combined).isValid {
                return true
            }
        }

        // Rule C: 字母接非聲調數字相衝 (Letter Followed by Non-Tone Digit)
        // 若目前 buffer 含有字母，下一個鍵按非聲調數字 (1, 2, 5, 8, 9, 0)：
        // 數字 1(ㄅ), 2(ㄉ), 5(ㄓ) 為聲母，絕不可能接在韻母後面 (如 m(ㄩ)+1(ㄅ) 變 M1)
        // 數字 8(ㄚ), 9(ㄞ), 0(ㄢ) 為韻母，若無法與前面字母組合成合法注音音節，判定相衝
        // (注意：若下一個鍵為 3, 4, 6, 7 聲調數字，且前面字母可拼出合法注音，如 m+4=玉，則此函數回傳 false，維持中文！)
        if isNextDigit {
            if Self.nonToneDigits.contains(nextChar) {
                let combined = buffer + String(nextChar)
                if !validateBopomofo(input: combined).isValid {
                    return true
                }
            } else if Self.toneDigits.contains(nextChar) {
                // 如果是聲調數字，但前面字母根本無法拼成合法注音 (例如 ps + 5)，也判定相衝
                let combined = buffer + String(nextChar)
                if !validateBopomofo(input: combined).isValid {
                    return true
                }
            }
        }

        return false
    }

    // MARK: - 多音節連續注音檢測
    public func validateMultiSyllableBopomofo(input: String) -> Bool {
        if input.isEmpty {
            return true
        }
        if input.contains(where: { $0.isUppercase }) {
            return false
        }
        let single = validateBopomofo(input: input)
        if single.isValid {
            return true
        }
        let chars = Array(input.lowercased())
        return canSegmentAsBopomofo(chars: chars, startIndex: 0)
    }

    private func canSegmentAsBopomofo(chars: [Character], startIndex: Int) -> Bool {
        if startIndex == chars.count {
            return true
        }
        let maxLen = min(4, chars.count - startIndex)
        for len in (1...maxLen).reversed() {
            let slice = String(chars[startIndex..<(startIndex + len)])
            let (isValid, _) = validateBopomofo(input: slice)
            if isValid {
                let nextIndex = startIndex + len
                if nextIndex == chars.count {
                    return true
                }
                let lastChar = chars[nextIndex - 1]
                let hasTone = (Daqian.tones[lastChar] != nil && lastChar != " ")
                let nextChar = chars[nextIndex]
                let nextIsInitial = (Daqian.initials[nextChar] != nil)
                let lastHasVowel = (Daqian.finals[lastChar] != nil || Daqian.medials[lastChar] != nil)

                if hasTone || (nextIsInitial && lastHasVowel) {
                    if canSegmentAsBopomofo(chars: chars, startIndex: nextIndex) {
                        return true
                    }
                }
            }
        }
        return false
    }

    // MARK: - 英文預測查找 (保持原始大小寫風格，基於前綴索引極速檢索)
    public func predictEnglish(prefix: String) -> String? {
        guard !prefix.isEmpty else { return nil }
        let lower = prefix.lowercased()
        if let exactAcronym = Self.knownSpecAcronyms[lower] {
            return exactAcronym
        }
        for (k, v) in Self.knownSpecAcronyms {
            if k.hasPrefix(lower) && k != lower {
                return v
            }
        }
        guard let firstChar = lower.first else { return nil }
        let indices = wordsByFirstChar[firstChar] ?? []
        for idx in indices {
            let candidateLower = lowercasedWordList[idx]
            if candidateLower.hasPrefix(lower) {
                let matched = englishWordList[idx]
                if let first = prefix.first, first.isUppercase {
                    return matched.prefix(1).uppercased() + matched.dropFirst()
                }
                return matched
            }
        }
        return nil
    }

    public func hasExactWord(_ word: String) -> Bool {
        guard !word.isEmpty else { return false }
        let lower = word.lowercased()
        return exactWordSet.contains(lower)
    }

    // MARK: - 按鍵追蹤與狀態更新
    public func appendKey(_ char: Character) {
        currentBuffer.append(char)
        predictedWord = predictEnglish(prefix: currentBuffer)
    }

    public func removeLastKey() {
        if !currentBuffer.isEmpty {
            currentBuffer.removeLast()
            if currentBuffer.isEmpty {
                clear()
            } else {
                predictedWord = predictEnglish(prefix: currentBuffer)
            }
        }
    }

    public func clear() {
        currentBuffer = ""
        predictedWord = nil
        isPureEnglishMode = false
        associatedSuggestion = nil
    }

    // MARK: - 浮動提示文字
    public var tooltipDisplay: String? {
        if !currentBuffer.isEmpty {
            let display = predictedWord ?? Self.resolveCommittedEnglish(currentBuffer)
            if let prediction = predictedWord {
                if isPureEnglishMode {
                    return "英: \(prediction)  [Tab 補全]  [Enter 送出]"
                } else {
                    return "英: \(prediction) [Tab] | 中: 聲調"
                }
            }
            return isPureEnglishMode ? "英: \(display)  [Enter 送出]" : nil
        }
        if let suggestion = associatedSuggestion {
            return "聯想: \(suggestion)  [Tab 補全]"
        }
        return nil
    }
}
