import AppKit
import Carbon.HIToolbox
import KeyboardShortcuts
import SquaiCore

extension KeyboardShortcuts.Name {
    static func member(_ id: String) -> Self { Self("member.\(id)") }
}

/// Keeps one `KeyboardShortcuts.Name("member.<id>")` per member in sync with `skill.json`.
/// The file is the source of truth; UserDefaults is only the cache KeyboardShortcuts needs.
@MainActor
final class HotkeyRegistry {
    /// Looks the member up at event time, so a handler never holds a stale member.
    var onHotkey: (String) -> Void = { _ in }
    /// Names that already have a key-up handler. KeyboardShortcuts has no per-name handler
    /// removal, so each name gets exactly one handler for the life of the process.
    private var handled: Set<String> = []
    /// Names whose shortcut is currently set, so vanished members can be cleared.
    private var active: Set<String> = []

    func sync(members: [SquadMember]) {
        let duplicates = HotkeyCollision.duplicates(members.map { (id: $0.id, hotkey: $0.skill.hotkey) })
        var wanted: [String: KeyboardShortcuts.Shortcut] = [:]
        var claimed: Set<String> = []
        for member in members {
            guard let raw = member.skill.hotkey else { continue }
            guard let spec = HotkeySpec(raw), let shortcut = Self.shortcut(for: spec) else {
                NSLog("squai: member %@ hotkey '%@' is invalid; disabled", member.id, raw)
                continue
            }
            if duplicates[spec.normalized] != nil, !claimed.insert(spec.normalized).inserted {
                NSLog("squai: member %@ hotkey %@ duplicates an earlier member; disabled", member.id, spec.normalized)
                continue
            }
            wanted[member.id] = shortcut
        }

        // Clear every previously active name and every member's name first: setShortcut unregisters
        // the name's old combination globally, which would otherwise undo a combination just assigned
        // to a swap partner. Member names cover shortcuts persisted in UserDefaults by a previous launch.
        for id in active.union(members.map(\.id)) {
            KeyboardShortcuts.setShortcut(nil, for: .member(id))
        }
        for (id, shortcut) in wanted {
            let name = KeyboardShortcuts.Name.member(id)
            KeyboardShortcuts.setShortcut(shortcut, for: name)
            if handled.insert(id).inserted {
                KeyboardShortcuts.onKeyUp(for: name) { [weak self] in
                    MainActor.assumeIsolated { self?.onHotkey(id) }
                }
            }
        }
        active = Set(wanted.keys)
    }

    static func shortcut(for spec: HotkeySpec) -> KeyboardShortcuts.Shortcut? {
        guard let code = keyCodes[spec.key] else { return nil }
        var flags: NSEvent.ModifierFlags = []
        if spec.modifiers.contains(.ctrl) { flags.insert(.control) }
        if spec.modifiers.contains(.opt) { flags.insert(.option) }
        if spec.modifiers.contains(.shift) { flags.insert(.shift) }
        if spec.modifiers.contains(.cmd) { flags.insert(.command) }
        return KeyboardShortcuts.Shortcut(KeyboardShortcuts.Key(rawValue: code), modifiers: flags)
    }

    private static let keyCodes: [String: Int] = [
        "a": kVK_ANSI_A, "b": kVK_ANSI_B, "c": kVK_ANSI_C, "d": kVK_ANSI_D, "e": kVK_ANSI_E,
        "f": kVK_ANSI_F, "g": kVK_ANSI_G, "h": kVK_ANSI_H, "i": kVK_ANSI_I, "j": kVK_ANSI_J,
        "k": kVK_ANSI_K, "l": kVK_ANSI_L, "m": kVK_ANSI_M, "n": kVK_ANSI_N, "o": kVK_ANSI_O,
        "p": kVK_ANSI_P, "q": kVK_ANSI_Q, "r": kVK_ANSI_R, "s": kVK_ANSI_S, "t": kVK_ANSI_T,
        "u": kVK_ANSI_U, "v": kVK_ANSI_V, "w": kVK_ANSI_W, "x": kVK_ANSI_X, "y": kVK_ANSI_Y,
        "z": kVK_ANSI_Z,
        "0": kVK_ANSI_0, "1": kVK_ANSI_1, "2": kVK_ANSI_2, "3": kVK_ANSI_3, "4": kVK_ANSI_4,
        "5": kVK_ANSI_5, "6": kVK_ANSI_6, "7": kVK_ANSI_7, "8": kVK_ANSI_8, "9": kVK_ANSI_9,
        "space": kVK_Space,
        "f1": kVK_F1, "f2": kVK_F2, "f3": kVK_F3, "f4": kVK_F4, "f5": kVK_F5, "f6": kVK_F6,
        "f7": kVK_F7, "f8": kVK_F8, "f9": kVK_F9, "f10": kVK_F10, "f11": kVK_F11, "f12": kVK_F12
    ].mapValues { Int($0) }
}
