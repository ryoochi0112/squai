import AppKit
import SwiftUI

@MainActor
final class SettingsWindowController: NSWindowController {
    convenience init(store: MemberStore, onReload: @escaping () -> Void) {
        let window = NSWindow(contentRect: .zero, styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "squai Settings"
        window.contentViewController = NSHostingController(rootView: SettingsView(store: store, onReload: onReload))
        window.isReleasedWhenClosed = false
        window.center()
        self.init(window: window)
    }
}
