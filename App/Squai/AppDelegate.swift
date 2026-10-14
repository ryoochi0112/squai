import AppKit
import SquaiCore
import KeyboardShortcuts

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: StatusItemController!
    private var squad: SquadController!
    private var bubbleStore: BubbleController?
    private var bubbleAnchor: PetController?
    private var settings: SettingsWindowController?
    let registry = SkillRegistry()

    func applicationDidFinishLaunching(_ notification: Notification) {
        registry.register(TranslateSkill(
            onDevice: AppleTranslationBackend(),
            premium: ClaudeBackend(apiKeyProvider: { Keychain.read(service: Keychain.anthropicService) })
        ))

        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("squai", isDirectory: true)
        let memberRoot = support.appendingPathComponent("pets", isDirectory: true)
        try? FileManager.default.createDirectory(at: memberRoot, withIntermediateDirectories: true)
        var lookRoots: [(URL, Look.Source)] = [(support.appendingPathComponent("looks", isDirectory: true), .squai)]
        if let bundled = Bundle.main.resourceURL?.appendingPathComponent("Pets", isDirectory: true) {
            lookRoots.append((bundled, .bundled))
        }
        lookRoots.append((FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex/pets", isDirectory: true), .codex))
        squad = SquadController(library: SquadLibrary(memberRoot: memberRoot, lookRoots: lookRoots))
        squad.onLeftClick = { [weak self] _ in self?.bubble?.showLast() }
        statusItem = StatusItemController(
            onTranslate: { [weak self] in self?.runTranslate(premium: false) },
            onSettings: { [weak self] in self?.showSettings() },
            onReloadSquad: { [weak self] in self?.squad.reload() },
            onPickPet: { [weak self] in self?.pet?.load(pet: $0) },
            pets: { PetLibrary(searchPaths: Self.petSearchPaths).scan() }
        )

        KeyboardShortcuts.onKeyUp(for: .translateSelection) { [weak self] in self?.runTranslate(premium: false) }
        KeyboardShortcuts.onKeyUp(for: .translateSelectionPremium) { [weak self] in self?.runTranslate(premium: true) }

        squad.reload()
        SelectionCapture.requestAccessibilityIfNeeded()
    }

    static var petSearchPaths: [URL] {
        var paths = PetLibrary.defaultSearchPaths
        if let bundled = Bundle.main.resourceURL?.appendingPathComponent("Pets", isDirectory: true) {
            paths.append(bundled)
        }
        return paths
    }

    /// v1 translate anchors to the first visible member's pet (T6 removes v1 translate).
    private var pet: PetController? {
        guard let first = squad.members.first(where: { $0.skill.visible }) else { return nil }
        return squad.pet(for: first.id)
    }

    private var bubble: BubbleController? {
        guard let pet else { return nil }
        if bubbleAnchor !== pet || bubbleStore == nil {
            bubbleStore = BubbleController(anchor: pet)
            bubbleAnchor = pet
        }
        return bubbleStore
    }

    func runTranslate(premium: Bool) {
        guard let pet, let bubble else {
            NSLog("squai: translate hotkey ignored: no squad members")
            return
        }
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
        guard let pet, let bubble else { return }
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
