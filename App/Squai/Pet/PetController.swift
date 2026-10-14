import AppKit
import SquaiCore

/// Owns the panel, the loaded sprite sheet, and the animation loop.
@MainActor
final class PetController {
    static let displaySize = NSSize(width: 96, height: 104) // 192x208 @ 0.5

    let panel: PetPanel
    private let view: PetSpriteView
    private var sheet: SpriteSheet?
    private(set) var state: PetState = .idle
    private var frameIndex = 0
    private var timer: Timer?
    private var revertWork: DispatchWorkItem?
    var onClick: (() -> Void)?

    init() {
        let origin = Preferences.petOrigin ?? Self.defaultOrigin()
        panel = PetPanel(contentRect: NSRect(origin: origin, size: Self.displaySize))
        view = PetSpriteView(frame: NSRect(origin: .zero, size: Self.displaySize))
        panel.contentView = view
        view.onClick = { [weak self] in self?.onClick?() }
        view.onDragEnd = { Preferences.petOrigin = $0 }

        let pets = PetLibrary(searchPaths: AppDelegate.petSearchPaths).scan()
        let chosen = pets.first { $0.manifest.id == Preferences.selectedPetID } ?? pets.first
        if let chosen { load(pet: chosen) }
    }

    private static func defaultOrigin() -> NSPoint {
        let screen = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1280, height: 800)
        return NSPoint(x: screen.maxX - displaySize.width - 24, y: screen.minY + 24)
    }

    func load(pet: InstalledPet) {
        guard let src = CGImageSourceCreateWithURL(pet.spritesheetURL as CFURL, nil),
              let atlas = CGImageSourceCreateImageAtIndex(src, 0, nil),
              let sheet = try? SpriteSheet(atlas: atlas) else {
            NSLog("squai: failed to load pet %@ at %@", pet.manifest.id, pet.spritesheetURL.path)
            return
        }
        self.sheet = sheet
        Preferences.selectedPetID = pet.manifest.id
        frameIndex = 0
        render()
    }

    func show() {
        panel.orderFrontRegardless()
        startTimer()
    }

    /// Transient states revert to idle after `revertAfter` seconds; `nil` keeps the state.
    func set(state: PetState, revertAfter: TimeInterval? = 6) {
        self.state = state
        frameIndex = 0
        render()
        revertWork?.cancel()
        guard let revertAfter else { return }
        let work = DispatchWorkItem { [weak self] in self?.set(state: .idle, revertAfter: nil) }
        revertWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + revertAfter, execute: work)
    }

    private func startTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1.0 / Preferences.frameRate, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.frameIndex &+= 1
                self.render()
            }
        }
        RunLoop.main.add(timer!, forMode: .common)
    }

    private func render() {
        view.frameImage = sheet?.frame(state, index: frameIndex)
    }
}
