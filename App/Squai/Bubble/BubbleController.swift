import AppKit
import SwiftUI
import SquaiCore
import Translation

/// Speech bubble panel positioned next to the pet. Auto-hides after `autoHide` seconds.
@MainActor
final class BubbleController {
    private let panel: NSPanel
    private let host = NSHostingView(rootView: AnyView(EmptyView()))
    private unowned let anchor: PetController
    private var last: BubbleContent?
    private var hideWork: DispatchWorkItem?
    private var clickMonitor: Any?
    var autoHide: TimeInterval = 12

    init(anchor: PetController) {
        self.anchor = anchor
        panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 300, height: 120),
                        styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.level = .screenSaver
        panel.collectionBehavior = [.canJoinAllSpaces, .canJoinAllApplications, .fullScreenAuxiliary, .stationary]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.contentView = host
    }

    func show(_ content: BubbleContent) {
        last = content
        host.rootView = AnyView(BubbleView(
            content: content,
            onCopy: { [weak self] in
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString($0, forType: .string)
                self?.hide()
            },
            onAskClaude: { [weak self] source in
                self?.hide()
                (NSApp.delegate as? AppDelegate)?.rerunPremium(source: source)
            },
            onDownloadPack: { [weak self] in self?.downloadPack(content) },
            onClose: { [weak self] in self?.hide() }
        ))
        host.layoutSubtreeIfNeeded()
        let size = host.fittingSize
        panel.setContentSize(size)
        position(size: size)
        panel.orderFrontRegardless()
        scheduleHide()
        installClickMonitor()
    }

    func showLast() {
        if let last { show(last) }
    }

    func hide() {
        hideWork?.cancel()
        panel.orderOut(nil)
        if let m = clickMonitor { NSEvent.removeMonitor(m); clickMonitor = nil }
    }

    private func position(size: NSSize) {
        let pet = anchor.panel.frame
        let screen = anchor.panel.screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? .zero
        var origin = NSPoint(x: pet.minX - size.width - 8, y: pet.maxY - size.height)
        if origin.x < screen.minX { origin.x = pet.maxX + 8 }
        origin.y = max(screen.minY, min(origin.y, screen.maxY - size.height))
        panel.setFrameOrigin(origin)
    }

    private func scheduleHide() {
        hideWork?.cancel()
        let w = DispatchWorkItem { [weak self] in self?.hide() }
        hideWork = w
        DispatchQueue.main.asyncAfter(deadline: .now() + autoHide, execute: w)
    }

    private func installClickMonitor() {
        if clickMonitor != nil { return }
        clickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            Task { @MainActor in self?.hide() }
        }
    }

    private func downloadPack(_ content: BubbleContent) {
        guard case .languagePackMissing(let s, let t) = content else { return }
        hide()
        Task {
            // Triggers the system download sheet; see AppleTranslationBackend for the session variant.
            await AppleTranslationBackend.prepare(source: s, target: t)
        }
    }
}
