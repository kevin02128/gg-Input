import Foundation

public struct BopomofoSyllable: Equatable, Hashable, CustomStringConvertible {
    public static let consonantMask: UInt16   = 0x001F // 21 consonants
    public static let middleVowelMask: UInt16 = 0x0060 // 3 middle vowels
    public static let vowelMask: UInt16       = 0x0780 // 13 vowels
    public static let toneMarkerMask: UInt16  = 0x3800 // 5 tones

    // Consonants (1..21)
    public static let b: UInt16 = 0x0001
    public static let p: UInt16 = 0x0002
    public static let m: UInt16 = 0x0003
    public static let f: UInt16 = 0x0004
    public static let d: UInt16 = 0x0005
    public static let t: UInt16 = 0x0006
    public static let n: UInt16 = 0x0007
    public static let l: UInt16 = 0x0008
    public static let g: UInt16 = 0x0009
    public static let k: UInt16 = 0x000A
    public static let h: UInt16 = 0x000B
    public static let j: UInt16 = 0x000C
    public static let q: UInt16 = 0x000D
    public static let x: UInt16 = 0x000E
    public static let zh: UInt16 = 0x000F
    public static let ch: UInt16 = 0x0010
    public static let sh: UInt16 = 0x0011
    public static let r: UInt16 = 0x0012
    public static let z: UInt16 = 0x0013
    public static let c: UInt16 = 0x0014
    public static let s: UInt16 = 0x0015

    // Middle Vowels
    public static let i: UInt16  = 0x0020
    public static let u: UInt16  = 0x0040
    public static let ue: UInt16 = 0x0060 // ㄩ

    // Vowels
    public static let a: UInt16   = 0x0080
    public static let o: UInt16   = 0x0100
    public static let er: UInt16  = 0x0180 // ㄜ
    public static let e: UInt16   = 0x0200 // ㄝ
    public static let ai: UInt16  = 0x0280
    public static let ei: UInt16  = 0x0300
    public static let ao: UInt16  = 0x0380
    public static let ou: UInt16  = 0x0400
    public static let an: UInt16  = 0x0480
    public static let en: UInt16  = 0x0500
    public static let ang: UInt16 = 0x0580
    public static let eng: UInt16 = 0x0600
    public static let err: UInt16 = 0x0680 // ㄦ

    // Tones
    public static let tone1: UInt16 = 0x0000 // 1st tone (no mark)
    public static let tone2: UInt16 = 0x0800 // ˊ
    public static let tone3: UInt16 = 0x1000 // ˇ
    public static let tone4: UInt16 = 0x1800 // ˋ
    public static let tone5: UInt16 = 0x2000 // ˙

    public var rawValue: UInt16 = 0

    public init(rawValue: UInt16 = 0) {
        self.rawValue = rawValue
    }

    public var isEmpty: Bool {
        rawValue == 0
    }

    public mutating func clear() {
        rawValue = 0
    }

    public var hasConsonant: Bool {
        (rawValue & Self.consonantMask) != 0
    }

    public var hasMiddleVowel: Bool {
        (rawValue & Self.middleVowelMask) != 0
    }

    public var hasVowel: Bool {
        (rawValue & Self.vowelMask) != 0
    }

    public var hasToneMarker: Bool {
        (rawValue & Self.toneMarkerMask) != 0
    }

    public var consonantComponent: UInt16 {
        rawValue & Self.consonantMask
    }

    public var middleVowelComponent: UInt16 {
        rawValue & Self.middleVowelMask
    }

    public var vowelComponent: UInt16 {
        rawValue & Self.vowelMask
    }

    public var toneMarkerComponent: UInt16 {
        rawValue & Self.toneMarkerMask
    }

    public mutating func combine(component: UInt16) {
        if (component & Self.consonantMask) != 0 {
            rawValue = (rawValue & ~Self.consonantMask) | (component & Self.consonantMask)
        }
        if (component & Self.middleVowelMask) != 0 {
            rawValue = (rawValue & ~Self.middleVowelMask) | (component & Self.middleVowelMask)
        }
        if (component & Self.vowelMask) != 0 {
            rawValue = (rawValue & ~Self.vowelMask) | (component & Self.vowelMask)
        }
        if (component & Self.toneMarkerMask) != 0 {
            rawValue = (rawValue & ~Self.toneMarkerMask) | (component & Self.toneMarkerMask)
        }
    }

    // Mapping character to component
    public static let charToComponent: [String: UInt16] = [
        "ㄅ": b, "ㄆ": p, "ㄇ": m, "ㄈ": f, "ㄉ": d, "ㄊ": t, "ㄋ": n, "ㄌ": l,
        "ㄍ": g, "ㄎ": k, "ㄏ": h, "ㄐ": j, "ㄑ": q, "ㄒ": x, "ㄓ": zh, "ㄔ": ch,
        "ㄕ": sh, "ㄖ": r, "ㄗ": z, "ㄘ": c, "ㄙ": s,
        "ㄧ": i, "ㄨ": u, "ㄩ": ue,
        "ㄚ": a, "ㄛ": o, "ㄜ": er, "ㄝ": e, "ㄞ": ai, "ㄟ": ei, "ㄠ": ao, "ㄡ": ou,
        "ㄢ": an, "ㄣ": en, "ㄤ": ang, "ㄥ": eng, "ㄦ": err,
        "ˊ": tone2, "ˇ": tone3, "ˋ": tone4, "˙": tone5
    ]

    public static let componentToChar: [UInt16: String] = {
        var map: [UInt16: String] = [:]
        for (char, comp) in charToComponent {
            map[comp] = char
        }
        return map
    }()

    public var composedString: String {
        var res = ""
        let cc = consonantComponent
        if cc != 0, let ch = Self.componentToChar[cc] { res += ch }
        let mvc = middleVowelComponent
        if mvc != 0, let ch = Self.componentToChar[mvc] { res += ch }
        let vc = vowelComponent
        if vc != 0, let ch = Self.componentToChar[vc] { res += ch }
        let tmc = toneMarkerComponent
        if tmc != 0, let ch = Self.componentToChar[tmc] { res += ch }
        return res
    }

    public var description: String {
        composedString
    }

    public static func fromComposed(string: String) -> BopomofoSyllable {
        var syllable = BopomofoSyllable()
        for ch in string {
            if let comp = charToComponent[String(ch)] {
                syllable.combine(component: comp)
            }
        }
        return syllable
    }

    public func toHanyuPinyin(includesTone: Bool = false, useVForUUmlaut: Bool = false) -> String {
        var consonant = ""
        var middle = ""
        var vowel = ""
        var tone = ""

        let cc = consonantComponent
        let mvc = middleVowelComponent
        let vc = vowelComponent
        let hasNoMVCOrVC = (mvc == 0 && vc == 0)

        switch cc {
        case Self.b: consonant = "b"
        case Self.p: consonant = "p"
        case Self.m: consonant = "m"
        case Self.f: consonant = "f"
        case Self.d: consonant = "d"
        case Self.t: consonant = "t"
        case Self.n: consonant = "n"
        case Self.l: consonant = "l"
        case Self.g: consonant = "g"
        case Self.k: consonant = "k"
        case Self.h: consonant = "h"
        case Self.j:
            consonant = "j"
            if hasNoMVCOrVC { middle = "i" }
        case Self.q:
            consonant = "q"
            if hasNoMVCOrVC { middle = "i" }
        case Self.x:
            consonant = "x"
            if hasNoMVCOrVC { middle = "i" }
        case Self.zh:
            consonant = "zh"
            if hasNoMVCOrVC { middle = "i" }
        case Self.ch:
            consonant = "ch"
            if hasNoMVCOrVC { middle = "i" }
        case Self.sh:
            consonant = "sh"
            if hasNoMVCOrVC { middle = "i" }
        case Self.r:
            consonant = "r"
            if hasNoMVCOrVC { middle = "i" }
        case Self.z:
            consonant = "z"
            if hasNoMVCOrVC { middle = "i" }
        case Self.c:
            consonant = "c"
            if hasNoMVCOrVC { middle = "i" }
        case Self.s:
            consonant = "s"
            if hasNoMVCOrVC { middle = "i" }
        default: break
        }

        switch mvc {
        case Self.i:
            if cc == 0 { consonant = "y" }
            middle = (vc == 0 || cc != 0) ? "i" : ""
        case Self.u:
            if cc == 0 { consonant = "w" }
            middle = (vc == 0 || cc != 0) ? "u" : ""
        case Self.ue:
            if cc == 0 { consonant = "y" }
            if (cc == Self.n || cc == Self.l) && vc != Self.e {
                middle = useVForUUmlaut ? "v" : "ü"
            } else {
                middle = "u"
            }
        default: break
        }

        switch vc {
        case Self.a: vowel = "a"
        case Self.o: vowel = "o"
        case Self.er: vowel = "e"
        case Self.e: vowel = "e"
        case Self.ai: vowel = "ai"
        case Self.ei: vowel = "ei"
        case Self.ao: vowel = "ao"
        case Self.ou: vowel = "ou"
        case Self.an: vowel = "an"
        case Self.en: vowel = "en"
        case Self.ang: vowel = "ang"
        case Self.eng: vowel = "eng"
        case Self.err: vowel = "er"
        default: break
        }

        // Combination rules
        // ueng -> ong, but note "weng"
        if (mvc == Self.u || mvc == Self.ue) && vc == Self.eng {
            middle = ""
            vowel = (cc == Self.j || cc == Self.q || cc == Self.x)
                ? "iong"
                : ((cc == 0 && mvc == Self.u) ? "eng" : "ong")
        }

        // ien, uen, üen -> in, un, ün; but note "wen", "yin" and "yun"
        if mvc != 0 && vc == Self.en {
            if cc != 0 {
                vowel = "n"
            } else {
                if mvc == Self.ue {
                    vowel = "n" // yun
                } else if mvc == Self.u {
                    vowel = "en" // wen
                } else {
                    vowel = "in" // yin
                }
            }
        }

        // iou -> iu
        if cc != 0 && mvc == Self.i && vc == Self.ou {
            middle = ""
            vowel = "iu"
        }

        // ieng -> ing
        if mvc == Self.i && vc == Self.eng {
            middle = ""
            vowel = "ing"
        }

        // uei -> ui
        if cc != 0 && mvc == Self.u && vc == Self.ei {
            middle = ""
            vowel = "ui"
        }

        if includesTone {
            switch toneMarkerComponent {
            case Self.tone2: tone = "2"
            case Self.tone3: tone = "3"
            case Self.tone4: tone = "4"
            case Self.tone5: tone = "5"
            default: break
            }
        }

        return consonant + middle + vowel + tone
    }
}

// MARK: - BopomofoBuffer / ReadingBuffer
public final class BopomofoBuffer {
    // Daqian keyboard layout character mappings
    public static let daqianKeyToComponent: [Character: UInt16] = [
        "1": BopomofoSyllable.b,
        "q": BopomofoSyllable.p,
        "a": BopomofoSyllable.m,
        "z": BopomofoSyllable.f,
        "2": BopomofoSyllable.d,
        "w": BopomofoSyllable.t,
        "s": BopomofoSyllable.n,
        "x": BopomofoSyllable.l,
        "e": BopomofoSyllable.g,
        "d": BopomofoSyllable.k,
        "c": BopomofoSyllable.h,
        "r": BopomofoSyllable.j,
        "f": BopomofoSyllable.q,
        "v": BopomofoSyllable.x,
        "5": BopomofoSyllable.zh,
        "t": BopomofoSyllable.ch,
        "g": BopomofoSyllable.sh,
        "b": BopomofoSyllable.r,
        "y": BopomofoSyllable.z,
        "h": BopomofoSyllable.c,
        "n": BopomofoSyllable.s,
        "u": BopomofoSyllable.i,
        "j": BopomofoSyllable.u,
        "m": BopomofoSyllable.ue,
        "8": BopomofoSyllable.a,
        "i": BopomofoSyllable.o,
        "k": BopomofoSyllable.er, // ㄜ
        ",": BopomofoSyllable.e,  // ㄝ
        "9": BopomofoSyllable.ai,
        "o": BopomofoSyllable.ei,
        "l": BopomofoSyllable.ao,
        ".": BopomofoSyllable.ou,
        "0": BopomofoSyllable.an,
        "p": BopomofoSyllable.en,
        ";": BopomofoSyllable.ang,
        "/": BopomofoSyllable.eng,
        "-": BopomofoSyllable.err, // ㄦ
        "3": BopomofoSyllable.tone3,
        "4": BopomofoSyllable.tone4,
        "6": BopomofoSyllable.tone2,
        "7": BopomofoSyllable.tone5
    ]

    public static let daqianComponentToKey: [UInt16: Character] = {
        var map: [UInt16: Character] = [:]
        for (k, comp) in daqianKeyToComponent {
            if k != " " {
                map[comp] = k
            }
        }
        return map
    }()

    public private(set) var keySequence: String = ""
    public private(set) var syllable: BopomofoSyllable = BopomofoSyllable()

    public init() {}

    public var isEmpty: Bool {
        syllable.isEmpty
    }

    public var reading: String {
        syllable.composedString
    }

    public var composedString: String {
        syllable.composedString
    }

    public var hasToneMarker: Bool {
        syllable.hasToneMarker
    }

    public var hasToneMarkerOnly: Bool {
        syllable.hasToneMarker && !syllable.hasConsonant && !syllable.hasMiddleVowel && !syllable.hasVowel
    }

    public func isValidKey(_ char: Character) -> Bool {
        Self.daqianKeyToComponent[char] != nil
    }

    public func isValidKey(charCode: Int) -> Bool {
        guard let scalar = UnicodeScalar(charCode), charCode < 128 else {
            return false
        }
        return isValidKey(Character(scalar))
    }

    @discardableResult
    public func combineKey(_ char: Character) -> Bool {
        guard let comp = Self.daqianKeyToComponent[char] else {
            return false
        }
        keySequence.append(char)
        syllable.combine(component: comp)
        return true
    }

    public func backspace() {
        if keySequence.isEmpty {
            return
        }
        keySequence.removeLast()
        // Rebuild syllable from key sequence
        var newSyllable = BopomofoSyllable()
        for ch in keySequence {
            if let comp = Self.daqianKeyToComponent[ch] {
                newSyllable.combine(component: comp)
            }
        }
        self.syllable = newSyllable
    }

    public func clear() {
        keySequence = ""
        syllable.clear()
    }

    public static func keySequence(from syllable: BopomofoSyllable) -> String {
        var seq = ""
        let cc = syllable.consonantComponent
        if cc != 0, let k = daqianComponentToKey[cc] { seq.append(k) }
        let mvc = syllable.middleVowelComponent
        if mvc != 0, let k = daqianComponentToKey[mvc] { seq.append(k) }
        let vc = syllable.vowelComponent
        if vc != 0, let k = daqianComponentToKey[vc] { seq.append(k) }
        let tmc = syllable.toneMarkerComponent
        if tmc != 0, let k = daqianComponentToKey[tmc] { seq.append(k) }
        return seq
    }
}
