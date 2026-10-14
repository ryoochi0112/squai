import AppKit
import SwiftUI
import SquaiCore

/// Speech bubble panel positioned next to the pet. Auto-hides after `autoHide` seconds.
@MainActor
final class BubbleController {
    private let panel: NSPanel
    private let host = NSHostingView(rootView: AnyView(EmptyView()))
    /// Resolved at show time, so a reloaded or hidden member never leaves a stale pet reference.
    private let anchorFrame: () -> NSRect
    private var hideWork: DispatchWorkItem?
    private var clickMonitor: Any?
    var autoHide: TimeInterval = 12

    var onReplace: (String) -> Void = { _ in }
    var onOpenSettings: () -> Void = {}

    init(anchorFrame: @escaping () -> NSRect) {
        self.anchorFrame = anchorFrame
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
        host.rootView = AnyView(BubbleView(
            content: content,
            onCopy: { [weak self] in
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString($0, forType: .string)
                self?.hide()
            },
            onReplace: { [weak self] in self?.onReplace($0) },
            onOpenSettings: { [weak self] in
                self?.hide()
                self?.onOpenSettings()
            },
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

    func hide() {
        hideWork?.cancel()
        panel.orderOut(nil)
        if let m = clickMonitor { NSEvent.removeMonitor(m); clickMonitor = nil }
    }

    private func position(size: NSSize) {
        let pet = anchorFrame()
        let center = NSPoint(x: pet.midX, y: pet.midY)
        let screen = (NSScreen.screens.first { $0.frame.contains(center) } ?? NSScreen.main)?.visibleFrame ?? .zero
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
}
