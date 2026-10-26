import Foundation

public enum UTF8Helper {
    public static func codePointCount(_ s: String) -> Int {
        s.unicodeScalars.count
    }

    public static func substringToCodePoints(_ s: String, _ cp: Int) -> String {
        guard cp > 0 else { return "" }
        let scalars = s.unicodeScalars
        if cp >= scalars.count { return s }
        let idx = scalars.index(scalars.startIndex, offsetBy: cp)
        return String(scalars[..<idx])
    }

    public static func getCodePoint(_ s: String, _ cp: Int) -> String {
        let scalars = s.unicodeScalars
        guard cp >= 0, cp < scalars.count else { return "" }
        let idx = scalars.index(scalars.startIndex, offsetBy: cp)
        return String(scalars[idx])
    }

    public static func split(_ s: String) -> [String] {
        s.unicodeScalars.map { String($0) }
    }
}
