import AppKit
import ApplicationServices

/// Easydict strategy: AX selected text first, then simulated ⌘C with clipboard restore.
enum SelectionCapture {
    enum CaptureError: Error { case noSelection, accessibilityDenied }

    static func requestAccessibilityIfNeeded() {
        let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(opts)
    }

    static func selectedText() async throws -> String {
        if let ax = axSelectedText(), !ax.isEmpty { return ax }
        return try await copyFallback()
    }

    private static func axSelectedText() -> String? {
        guard AXIsProcessTrusted() else { return nil }
        let system = AXUIElementCreateSystemWide()
        var focused: AnyObject?
        guard AXUIElementCopyAttributeValue(system, kAXFocusedUIElementAttribute as CFString, &focused) == .success,
              let element = focused else { return nil }
        var value: AnyObject?
        // swiftlint:disable:next force_cast
        let el = element as! AXUIElement
        guard AXUIElementCopyAttributeValue(el, kAXSelectedTextAttribute as CFString, &value) == .success else { return nil }
        return value as? String
    }

    private static func copyFallback() async throws -> String {
        let pb = NSPasteboard.general
        let saved = pb.pasteboardItems?.compactMap { item -> NSPasteboardItem? in
            let copy = NSPasteboardItem()
            for t in item.types { if let d = item.data(forType: t) { copy.setData(d, forType: t) } }
            return copy
        } ?? []
        let before = pb.changeCount
        pb.clearContents()

        postCommandC()
        for _ in 0..<10 {
            try await Task.sleep(nanoseconds: 50_000_000)
            if pb.changeCount != before + 1 { break }
        }
        let text = pb.string(forType: .string)

        pb.clearContents()
        if !saved.isEmpty { pb.writeObjects(saved) }

        guard let text, !text.isEmpty else { throw CaptureError.noSelection }
        return text
    }

    private static func postCommandC() {
        let src = CGEventSource(stateID: .combinedSessionState)
        let keyC: CGKeyCode = 8
        guard let down = CGEvent(keyboardEventSource: src, virtualKey: keyC, keyDown: true),
              let up = CGEvent(keyboardEventSource: src, virtualKey: keyC, keyDown: false) else { return }
        down.flags = .maskCommand
        up.flags = .maskCommand
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
    }
}
