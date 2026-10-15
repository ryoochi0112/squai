import AppKit

/// Copy and Replace for a member's result (design §3.4).
///
/// Replace pastes with a synthetic ⌘V into the app the selection came from, then puts the user's
/// clipboard back. It never pastes into a different app: if focus moved, the body stays on the
/// pasteboard (the user can paste it manually) and the caller shows "Copied — could not replace".
@MainActor
enum ReplaceService {
    /// How long the target app gets to read the pasteboard before the snapshot is restored.
    static let restoreDelay: UInt64 = 400_000_000

    static func copy(_ body: String) {
        copy(body, to: .general)
    }

    static func copy(_ body: String, to pb: NSPasteboard) {
        pb.clearContents()
        pb.setString(body, forType: .string)
    }

    /// Returns true when ⌘V was posted to `ctx`'s app and the prior clipboard was restored.
    /// On false the body is left on the pasteboard; the pasteboard is never cleared.
    static func replace(_ body: String, into ctx: CaptureContext) async -> Bool {
        await replace(body, into: ctx, pasteboard: .general,
                      frontmostPID: { NSWorkspace.shared.frontmostApplication?.processIdentifier },
                      postPaste: postCommandV, restoreDelay: restoreDelay)
    }

    /// Testable core: the frontmost-app lookup, the key event, and the delay are injected.
    static func replace(_ body: String, into ctx: CaptureContext, pasteboard pb: NSPasteboard,
                        frontmostPID: () -> pid_t?, postPaste: () -> Void,
                        restoreDelay: UInt64) async -> Bool {
        // Never paste into squai itself (e.g. the selection came from Settings).
        func isTarget() -> Bool {
            guard let pid = frontmostPID() else { return false }
            return pid == ctx.pid && pid != ProcessInfo.processInfo.processIdentifier
        }
        // (1) pid guard. Failure path: body on the pasteboard, nothing pasted.
        guard isTarget() else {
            copy(body, to: pb)
            return false
        }
        // (2) snapshot every type of every item, (3) write the body.
        let snapshot = PasteboardSnapshot.take(from: pb)
        copy(body, to: pb)
        let bodyChange = pb.changeCount
        // (4) wait so held ⌥/⇧/⌃ do not turn ⌘V into another shortcut.
        await SelectionCapture.waitForModifierRelease()
        // Focus may have moved during the wait; re-check right before posting the key.
        guard isTarget() else { return false }
        postPaste()
        // (5) give the app time to read the pasteboard, then restore the user's clipboard.
        try? await Task.sleep(nanoseconds: restoreDelay)
        // If something else wrote the pasteboard meanwhile (the user copied), that is newer than
        // the snapshot: keep it rather than overwrite it.
        if pb.changeCount == bodyChange {
            snapshot.restore(to: pb)
        }
        return true
    }

    private static func postCommandV() {
        let src = CGEventSource(stateID: .combinedSessionState)
        let keyV: CGKeyCode = 9
        guard let down = CGEvent(keyboardEventSource: src, virtualKey: keyV, keyDown: true),
              let up = CGEvent(keyboardEventSource: src, virtualKey: keyV, keyDown: false) else { return }
        down.flags = .maskCommand
        up.flags = .maskCommand
        down.post(tap: .cgSessionEventTap)
        up.post(tap: .cgSessionEventTap)
    }
}
