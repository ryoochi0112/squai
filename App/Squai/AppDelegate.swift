import AppKit
import SquaiCore

/// Everything resolved once at launch: where the CLIs live and the PATH they need.
private struct CLICache: Sendable {
    var executables: [Backend: URL]
    var loginShellPath: String?
    var home: URL
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: StatusItemController!
    private var squad: SquadController!
    private var settings: SettingsWindowController?
    private let hotkeys = HotkeyRegistry()
    private var routerTask: Task<BackendRouter, Never>!
    /// Per-member state keyed by id. All of it is pruned to the current members on reload.
    private var bubbles: [String: BubbleController] = [:]
    private var lastResult: [String: String] = [:]
    /// Identity of the in-flight run per member; reload drops it when the member vanishes or changes.
    private var runs: [String: UUID] = [:]

    func applicationDidFinishLaunching(_ notification: Notification) {
        routerTask = Task { await Self.makeRouter() }

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
        squad.onLeftClick = { [weak self] member in self?.run(memberID: member.id) }
        squad.onRightClick = { [weak self] member in self?.showLast(memberID: member.id) }
        hotkeys.onHotkey = { [weak self] id in self?.run(memberID: id) }
        statusItem = StatusItemController(
            onSettings: { [weak self] in self?.showSettings() },
            onReloadSquad: { [weak self] in self?.reloadSquad() },
            onPickPet: { [weak self] in self?.firstVisiblePet?.load(pet: $0) },
            pets: { PetLibrary(searchPaths: Self.petSearchPaths).scan() }
        )

        reloadSquad()
        SelectionCapture.requestAccessibilityIfNeeded()
    }

    static var petSearchPaths: [URL] {
        var paths = PetLibrary.defaultSearchPaths
        if let bundled = Bundle.main.resourceURL?.appendingPathComponent("Pets", isDirectory: true) {
            paths.append(bundled)
        }
        return paths
    }

    // MARK: Router

    private static func makeRouter() async -> BackendRouter {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let shell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
        let loginPath = await CLILocator.loginShellPATH(shell: shell)
        var executables: [Backend: URL] = [:]
        for (backend, name) in [(Backend.claude, "claude"), (Backend.chatgpt, "codex")] {
            executables[backend] = CLILocator().locate(name, loginShellPath: loginPath, home: home,
                                                       isExecutable: { FileManager.default.isExecutableFile(atPath: $0) })
        }
        let cache = CLICache(executables: executables, loginShellPath: loginPath, home: home)
        return BackendRouter(
            locateCLI: { cache.executables[$0] },
            childPATH: { CLILocator.childPATH(cliDir: $0.deletingLastPathComponent(),
                                              loginShellPath: cache.loginShellPath, home: cache.home) },
            claudeKey: { Keychain.read(service: Keychain.anthropicService) },
            runner: CLIRunner(),
            transport: URLSessionTransport(),
            makeRunDirectory: { try CLILocator.makeRunDirectory() })
    }

    // MARK: Squad

    private var firstVisiblePet: PetController? {
        guard let first = squad.members.first(where: { $0.skill.visible }) else { return nil }
        return squad.pet(for: first.id)
    }

    func reloadSquad() {
        let before = squad.members
        squad.reload()
        for old in before {
            let current = squad.members.first(where: { $0.id == old.id })
            if current == nil || current?.folder != old.folder || current?.skill != old.skill {
                runs[old.id] = nil
            }
        }
        hotkeys.sync(members: squad.members)
        let ids = Set(squad.members.map(\.id))
        for id in bubbles.keys where !ids.contains(id) {
            bubbles[id]?.hide()
            bubbles[id] = nil
        }
        lastResult = lastResult.filter { ids.contains($0.key) }
    }

    /// One bubble per member, anchored to that member's pet (or the default spot when hidden).
    private func bubble(for id: String) -> BubbleController {
        if let existing = bubbles[id] { return existing }
        let bubble = BubbleController(anchorFrame: { [weak self] in
            if let pet = self?.squad.pet(for: id) { return pet.panel.frame }
            return NSRect(origin: PetController.defaultOrigin(), size: PetController.displaySize)
        })
        bubble.onOpenSettings = { [weak self] in self?.showSettings() }
        bubbles[id] = bubble
        return bubble
    }

    // MARK: Run

    private func showLast(memberID id: String) {
        guard squad.members.contains(where: { $0.id == id }) else { return }
        if let last = lastResult[id] {
            bubble(for: id).show(.result(last))
        } else {
            bubble(for: id).show(.info("No result yet"))
        }
    }

    private func run(memberID id: String) {
        guard let member = squad.members.first(where: { $0.id == id }) else { return }
        guard runs[id] == nil else { return }
        guard SelectionCapture.isTrusted else {
            NSLog("squai: Accessibility not granted for this build")
            squad.pet(for: id)?.set(state: .waiting)
            bubble(for: id).show(.error("Accessibility access is off for this build of squai. Ad-hoc signed Debug builds lose the grant on every rebuild: open System Settings → Privacy & Security → Accessibility, remove squai, and add it again."))
            SelectionCapture.requestAccessibilityIfNeeded()
            return
        }
        let token = UUID()
        runs[id] = token
        squad.pet(for: id)?.set(state: .running, revertAfter: nil)
        Task { @MainActor in
            defer { if runs[id] == token { runs[id] = nil } }
            do {
                let selection = try await SelectionCapture.selectedText()
                guard runs[id] == token else { return }
                let prompt = PromptAssembler.assemble(prompt: member.skill.prompt, selection: selection)
                let router = await routerTask.value
                guard runs[id] == token else { return }
                let body = try await router.run(backend: member.skill.backend, prompt: prompt)
                guard runs[id] == token else { return }
                lastResult[id] = body
                squad.pet(for: id)?.set(state: .review)
                bubble(for: id).show(.result(body))
            } catch {
                guard runs[id] == token else { return }
                if case BackendError.notSetUp(let backend) = error {
                    squad.pet(for: id)?.set(state: .waiting)
                    bubble(for: id).show(.notSetUp(backendName: Self.name(backend)))
                    return
                }
                NSLog("squai: member %@ run failed: %@", id, String(describing: error))
                squad.pet(for: id)?.set(state: .failed)
                bubble(for: id).show(.error(Self.describe(error)))
            }
        }
    }

    static func name(_ backend: Backend) -> String {
        backend == .claude ? "Claude" : "ChatGPT"
    }

    static func describe(_ error: Error) -> String {
        switch error {
        case SelectionCapture.CaptureError.noSelection(let detail):
            return "No selected text was found. Select text first, then click a pet or press its hotkey.\n\nDiagnostics: \(detail)"
        case BackendError.notSetUp(let backend):
            return "\(name(backend)) is not set up."
        case BackendError.notLoggedIn(let backend):
            let command = backend == .claude ? "`claude`" : "`codex login`"
            return "\(name(backend)) is not logged in. Run \(command) once in Terminal."
        case BackendError.timedOut(let backend, let seconds):
            return "\(name(backend)) took too long (\(Int(seconds)) s). Try again."
        case BackendError.failed(_, let message):
            return message
        case BackendError.empty:
            return "The response came back empty."
        default:
            return String(describing: error)
        }
    }

    func showSettings() {
        if settings == nil { settings = SettingsWindowController() }
        settings?.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
