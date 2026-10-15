import Foundation

public struct HotkeySpec: Hashable, Sendable {
    public enum Modifier: String, Hashable, Sendable {
        case ctrl
        case opt
        case shift
        case cmd
    }

    public let modifiers: Set<Modifier>
    public let key: String

    public init?(_ string: String) {
        let tokens = string.lowercased().split(separator: "+", omittingEmptySubsequences: false)
        guard !tokens.isEmpty else { return nil }

        var parsedModifiers = Set<Modifier>()
        var parsedKey: String?

        for tokenSlice in tokens {
            let token = String(tokenSlice)
            if let modifier = Modifier(rawValue: token) {
                parsedModifiers.insert(modifier)
            } else if Self.isValidKey(token), parsedKey == nil {
                parsedKey = token
            } else {
                return nil
            }
        }

        guard let key = parsedKey else { return nil }
        self.modifiers = parsedModifiers
        self.key = key
    }

    public var normalized: String {
        let orderedModifiers: [Modifier] = [.ctrl, .opt, .shift, .cmd]
        return (orderedModifiers.filter(modifiers.contains).map(\.rawValue) + [key]).joined(separator: "+")
    }

    private static func isValidKey(_ token: String) -> Bool {
        if token == "space" { return true }

        let bytes = Array(token.utf8)
        if bytes.count == 1 {
            return (bytes[0] >= Character("a").asciiValue! && bytes[0] <= Character("z").asciiValue!)
                || (bytes[0] >= Character("0").asciiValue! && bytes[0] <= Character("9").asciiValue!)
        }

        guard token.first == "f", let number = Int(token.dropFirst()), (1...12).contains(number) else {
            return false
        }
        return token == "f\(number)"
    }
}

public enum HotkeyCollision: Sendable {
    /// Returns each duplicated normalized hotkey and its member ids in input order.
    public static func duplicates(_ members: [(id: String, hotkey: String?)]) -> [String: [String]] {
        var idsByHotkey: [String: [String]] = [:]
        var seenIDsByHotkey: [String: Set<String>] = [:]

        for member in members {
            guard let rawHotkey = member.hotkey, let hotkey = HotkeySpec(rawHotkey) else { continue }
            guard seenIDsByHotkey[hotkey.normalized, default: []].insert(member.id).inserted else { continue }
            idsByHotkey[hotkey.normalized, default: []].append(member.id)
        }

        return idsByHotkey.filter { $0.value.count >= 2 }
    }
}
