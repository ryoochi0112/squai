import AppKit
import ApplicationServices

/// Easydict strategy: AX selected text → simulated ⌘C → frontmost app's Edit ▸ Copy menu item.
/// Every stage records what it saw so a failure can be diagnosed from the bubble.
enum SelectionCapture {
    enum CaptureError: Error { case noSelection(detail: String) }

    static var isTrusted: Bool { AXIsProcessTrusted() }

    static func requestAccessibilityIfNeeded() {
        let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(opts)
    }

    static func selectedText() async throws -> String {
        var trace: [String] = []

        let ax = axSelectedText()
        trace.append("ax=\(ax.detail)")
        if let t = ax.text, !t.isEmpty { return t }

        await waitForModifierRelease()

        let viaKey = await copyViaPasteboard(trace: &trace) { postCommandC() }
        if let viaKey, !viaKey.isEmpty { return viaKey }

        var menuTrace: [String] = []
        let viaMenu = await copyViaPasteboard(trace: &trace) { pressEditCopyMenuItem(trace: &menuTrace) }
        trace.append(contentsOf: menuTrace)
        if let viaMenu, !viaMenu.isEmpty { return viaMenu }

        let detail = trace.joined(separator: " | ")
        NSLog("squai: capture failed: %@", detail)
        throw CaptureError.noSelection(detail: detail)
    }

    // MARK: Stage 1 — Accessibility API

    private static func axSelectedText() -> (text: String?, detail: String) {
        guard AXIsProcessTrusted() else { return (nil, "untrusted") }
        let system = AXUIElementCreateSystemWide()
        var focused: AnyObject?
        let fErr = AXUIElementCopyAttributeValue(system, kAXFocusedUIElementAttribute as CFString, &focused)
        guard fErr == .success, let element = focused else { return (nil, "focused:\(fErr.rawValue)") }
        // swiftlint:disable:next force_cast
        let el = element as! AXUIElement
        var role: AnyObject?
        AXUIElementCopyAttributeValue(el, kAXRoleAttribute as CFString, &role)
        var value: AnyObject?
        let sErr = AXUIElementCopyAttributeValue(el, kAXSelectedTextAttribute as CFString, &value)
        let text = value as? String
        return (text, "role=\(role as? String ?? "?") sel:\(sErr.rawValue) len=\(text?.count ?? -1)")
    }

    // MARK: Stage 2/3 — copy into the pasteboard, then restore it

    private static func copyViaPasteboard(trace: inout [String], trigger: () -> Void) async -> String? {
        let pb = NSPasteboard.general
        let saved = pb.pasteboardItems?.compactMap { item -> NSPasteboardItem? in
            let copy = NSPasteboardItem()
            for t in item.types { if let d = item.data(forType: t) { copy.setData(d, forType: t) } }
            return copy
        } ?? []
        let marker = pb.clearContents()

        trigger()
        var changed = false
        for _ in 0..<12 { // up to ~600 ms
            try? await Task.sleep(nanoseconds: 50_000_000)
            if pb.changeCount != marker { changed = true; break }
        }
        let text = pb.string(forType: .string)
        trace.append("pb changed=\(changed) types=\(pb.types?.map(\.rawValue).joined(separator: ",") ?? "-") len=\(text?.count ?? -1)")

        pb.clearContents()
        if !saved.isEmpty { pb.writeObjects(saved) }
        return text
    }

    /// The hotkey fires on key-up of the letter while ⌥⌘ may still be held; wait so the
    /// synthetic ⌘C is not merged with physical modifiers into ⌥⌘C.
    private static func waitForModifierRelease() async {
        for _ in 0..<20 { // up to ~1 s
            let held = NSEvent.modifierFlags.intersection([.option, .shift, .control])
            if held.isEmpty { return }
            try? await Task.sleep(nanoseconds: 50_000_000)
        }
    }

    private static func postCommandC() {
        let src = CGEventSource(stateID: .combinedSessionState)
        let keyC: CGKeyCode = 8
        guard let down = CGEvent(keyboardEventSource: src, virtualKey: keyC, keyDown: true),
              let up = CGEvent(keyboardEventSource: src, virtualKey: keyC, keyDown: false) else { return }
        down.flags = .maskCommand
        up.flags = .maskCommand
        down.post(tap: .cgSessionEventTap)
        up.post(tap: .cgSessionEventTap)
    }

    /// Stage 3: AXPress the frontmost app's Edit ▸ Copy menu item (Easydict "menuBarActionCopy").
    private static func pressEditCopyMenuItem(trace: inout [String]) {
        guard let app = NSWorkspace.shared.frontmostApplication else { trace.append("menu: no frontmost"); return }
        let appEl = AXUIElementCreateApplication(app.processIdentifier)
        var menuBar: AnyObject?
        guard AXUIElementCopyAttributeValue(appEl, kAXMenuBarAttribute as CFString, &menuBar) == .success,
              let bar = menuBar else { trace.append("menu: no menubar for \(app.localizedName ?? "?")"); return }
        // swiftlint:disable:next force_cast
        guard let item = findMenuItem(in: bar as! AXUIElement, titles: ["Copy", "コピー"], depth: 0) else {
            trace.append("menu: Copy item not found in \(app.localizedName ?? "?")"); return
        }
        let err = AXUIElementPerformAction(item, kAXPressAction as CFString)
        trace.append("menu: press=\(err.rawValue)")
    }

    private static func findMenuItem(in element: AXUIElement, titles: [String], depth: Int) -> AXUIElement? {
        guard depth < 4 else { return nil }
        var children: AnyObject?
        guard AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &children) == .success,
              let kids = children as? [AXUIElement] else { return nil }
        for kid in kids {
            var title: AnyObject?
            AXUIElementCopyAttributeValue(kid, kAXTitleAttribute as CFString, &title)
            var cmdChar: AnyObject?
            AXUIElementCopyAttributeValue(kid, kAXMenuItemCmdCharAttribute as CFString, &cmdChar)
            var cmdMods: AnyObject?
            AXUIElementCopyAttributeValue(kid, kAXMenuItemCmdModifiersAttribute as CFString, &cmdMods)
            let t = title as? String ?? ""
            // Prefer the item whose shortcut is plain ⌘C; fall back to title match.
            if (cmdChar as? String) == "C", (cmdMods as? Int ?? 0) == 0 { return kid }
            if titles.contains(t), depth >= 2 { return kid }
            if depth == 0, !["Edit", "編集"].contains(t) { continue } // only descend into Edit at the top level
            if let found = findMenuItem(in: kid, titles: titles, depth: depth + 1) { return found }
        }
        return nil
    }
}
