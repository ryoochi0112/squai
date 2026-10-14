import AppKit
import SquaiCore
import KeyboardShortcuts

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: StatusItemController!
    private var pet: PetController!
    private var bubble: BubbleController!
    private var settings: SettingsWindowController?
    let registry = SkillRegistry()

    func applicationDidFinishLaunching(_ notification: Notification) {
        registry.register(TranslateSkill(
            onDevice: AppleTranslationBackend(),
            premium: ClaudeBackend(apiKeyProvider: { Keychain.read(service: Keychain.anthropicService) })
        ))

        pet = PetController()
        bubble = BubbleController(anchor: pet)
        statusItem = StatusItemController(
            onTranslate: { [weak self] in self?.runTranslate(premium: false) },
            onSettings: { [weak self] in self?.showSettings() },
            onPickPet: { [weak self] in self?.pet.load(pet: $0) },
            pets: { PetLibrary(searchPaths: Self.petSearchPaths).scan() }
        )
        pet.onClick = { [weak self] in self?.bubble.showLast() }

        KeyboardShortcuts.onKeyUp(for: .translateSelection) { [weak self] in self?.runTranslate(premium: false) }
        KeyboardShortcuts.onKeyUp(for: .translateSelectionPremium) { [weak self] in self?.runTranslate(premium: true) }

        pet.show()
        SelectionCapture.requestAccessibilityIfNeeded()
    }

    static var petSearchPaths: [URL] {
        var paths = PetLibrary.defaultSearchPaths
        if let bundled = Bundle.main.resourceURL?.appendingPathComponent("Pets", isDirectory: true) {
            paths.append(bundled)
        }
        return paths
    }

    func runTranslate(premium: Bool) {
        guard let skill = registry.skill(id: "translate.ja-en") else { return }
        guard SelectionCapture.isTrusted else {
            NSLog("squai: Accessibility not granted for this build")
            pet.set(state: .waiting)
            bubble.show(.error("Accessibility access is off for this build of squai. Ad-hoc signed Debug builds lose the grant on every rebuild: open System Settings → Privacy & Security → Accessibility, remove squai, and add it again."))
            SelectionCapture.requestAccessibilityIfNeeded()
            return
        }
        Task { @MainActor in
            pet.set(state: .running)
            do {
                let text = try await SelectionCapture.selectedText()
                let out = try await skill.run(SkillInput(text: text, preferPremium: premium))
                pet.set(state: out.state)
                bubble.show(.result(out, source: text))
            } catch TranslationError.languagePackMissing(let s, let t) {
                pet.set(state: .waiting)
                bubble.show(.languagePackMissing(source: s, target: t))
            } catch TranslationError.missingAPIKey {
                pet.set(state: .waiting)
                showSettings()
            } catch {
                NSLog("squai: translate failed: %@", String(describing: error))
                pet.set(state: .failed)
                bubble.show(.error(Self.describe(error)))
            }
        }
    }

    static func describe(_ error: Error) -> String {
        switch error {
        case SelectionCapture.CaptureError.noSelection(let detail):
            return "No selected text was found. Select text first, then press the hotkey.\n\nDiagnostics: \(detail)"
        case TranslationError.unsupported(let s, let t):
            return "Apple Translation does not support \(s)→\(t) on this Mac."
        case TranslationError.http(let status, let body):
            return "Claude API error \(status): \(body.prefix(200))"
        case TranslationError.empty:
            return "The translation came back empty."
        default:
            return String(describing: error)
        }
    }

    func rerunPremium(source: String) {
        guard let skill = registry.skill(id: "translate.ja-en") else { return }
        Task { @MainActor in
            pet.set(state: .running)
            do {
                let out = try await skill.run(SkillInput(text: source, preferPremium: true))
                pet.set(state: out.state)
                bubble.show(.result(out, source: source))
            } catch TranslationError.missingAPIKey {
                showSettings()
            } catch {
                NSLog("squai: premium translate failed: %@", String(describing: error))
                pet.set(state: .failed)
                bubble.show(.error(Self.describe(error)))
            }
        }
    }

    func showSettings() {
        if settings == nil { settings = SettingsWindowController() }
        settings?.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
