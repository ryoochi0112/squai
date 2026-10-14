import Foundation

public enum LanguageDirection: Equatable, Sendable {
    case jaToEn
    case enToJa

    public var source: String { self == .jaToEn ? "ja" : "en" }
    public var target: String { self == .jaToEn ? "en" : "ja" }
}

public enum LanguageDetector {
    /// Japanese if the text contains any kana or CJK ideograph; otherwise English.
    public static func detect(_ text: String) -> LanguageDirection {
        for scalar in text.unicodeScalars {
            switch scalar.value {
            case 0x3040...0x309F, // Hiragana
                 0x30A0...0x30FF, // Katakana
                 0x31F0...0x31FF, // Katakana phonetic ext
                 0xFF66...0xFF9F, // Half-width katakana
                 0x4E00...0x9FFF, // CJK unified
                 0x3400...0x4DBF: // CJK ext A
                return .jaToEn
            default:
                continue
            }
        }
        return .enToJa
    }
}
