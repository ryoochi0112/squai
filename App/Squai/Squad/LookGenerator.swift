import Foundation
import SquaiCore

/// Generates a look with Codex's hatch-pet skill inside `hatch/<run-id>/`, then moves the validated
/// result to `looks/<id>/`. Never writes to ~/.codex or a bundled look.
@MainActor
final class LookGenerator: ObservableObject {
    enum State {
        case idle
        case preflightFailed([String])
        case running(started: Date)
        case failed(String)
        case done(Look)

        var isRunning: Bool {
            if case .running = self { return true }
            return false
        }
    }

    /// One generator for the app, so a run survives the Settings form being rebuilt and can be
    /// terminated at quit.
    static let shared = LookGenerator()

    @Published private(set) var state: State = .idle

    /// `~/Library/Application Support/squai`; AppDelegate sets it at launch.
    var supportRoot: URL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("squai", isDirectory: true)
    /// Called after a look landed in `looks/` so the library rescans (picker shows it).
    var onLookAdded: () -> Void = {}

    private var runID: UUID?
    private var task: Task<Void, Never>?
    /// Generation tasks that have not yet returned (a cancelled one stays counted until its child is reaped).
    private var liveTasks = 0
    private let runner = CLIRunner()

    private var hatchRoot: URL { supportRoot.appendingPathComponent("hatch", isDirectory: true) }
    private var looksRoot: URL { supportRoot.appendingPathComponent("looks", isDirectory: true) }

    // MARK: Preflight

    /// `runID` ties the probes to one generation: after every await, a cancelled task or a superseded
    /// run stops here, so no probe launches after cancel/quit.
    func preflight(for run: UUID? = nil) async -> HatchPreflight {
        func stale() -> Bool { Task.isCancelled || (run != nil && runID != run) }
        let aborted = HatchPreflight(codexFound: false, loggedInWithChatGPT: false,
                                     hatchSkillPresent: false, pillowPresent: false)
        if stale() { return aborted }
        let probe = await CLIProbe.current()
        if stale() { return aborted }
        let codex = probe.locate("codex")
        var loggedIn = false
        var pillow = false
        let environment = codex.map { ["PATH": probe.childPATH(for: $0)] }
            ?? ["PATH": CLILocator.childPATH(cliDir: URL(fileURLWithPath: "/usr/bin"),
                                             loginShellPath: probe.loginShellPath, home: probe.home)]
        if let cwd = try? CLILocator.makeRunDirectory() {
            defer { try? FileManager.default.removeItem(at: cwd) }
            if let codex {
                let inv = CLIInvocation(executable: codex, arguments: ["login", "status"], stdin: "", cwd: cwd,
                                        environment: Self.withHome(environment), timeout: 10)
                if let result = try? await runner.run(inv) {
                    loggedIn = (result.stdout + result.stderr).localizedCaseInsensitiveContains("chatgpt")
                }
                if stale() { return aborted }
            }
            let python = CLIInvocation(executable: URL(fileURLWithPath: "/usr/bin/env"),
                                       arguments: ["python3", "-c", "import PIL"], stdin: "", cwd: cwd,
                                       environment: Self.withHome(environment), timeout: 15)
            pillow = (try? await runner.run(python)) != nil
            if stale() { return aborted }
        }
        let skill = probe.home.appendingPathComponent(".codex/skills/hatch-pet/SKILL.md")
        return HatchPreflight(codexFound: codex != nil, loggedInWithChatGPT: loggedIn,
                              hatchSkillPresent: FileManager.default.fileExists(atPath: skill.path),
                              pillowPresent: pillow)
    }

    private static func withHome(_ environment: [String: String]) -> [String: String] {
        var result = environment
        if let home = ProcessInfo.processInfo.environment["HOME"] { result["HOME"] = home }
        return result
    }

    // MARK: Run

    /// `onDone` runs once, only if this run produced a look and was not cancelled.
    func start(description: String, onDone: ((Look) -> Void)? = nil) {
        guard !state.isRunning, task == nil else { return }
        let text = description.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            state = .failed("Describe the look first")
            return
        }
        let id = UUID()
        runID = id
        state = .running(started: Date())
        liveTasks += 1
        task = Task { [weak self] in
            await self?.perform(id: id, description: text, onDone: onDone)
            self?.liveTasks -= 1
        }
    }

    /// True while a generation child may still be alive, including one already cancelled.
    var hasLiveChild: Bool { liveTasks > 0 }

    /// Quit path: cancels (SIGTERM, then the runner's SIGKILL after 2 s) and waits until the child is
    /// reaped. Bounded at 6 s so quit never hangs.
    func terminateAndWait() async {
        cancel()
        let deadline = Date().addingTimeInterval(6)
        while liveTasks > 0, Date() < deadline {
            try? await Task.sleep(nanoseconds: 50_000_000)
        }
    }

    /// Terminates the child (also used at app quit). The run directory is removed by the task.
    func cancel() {
        runID = nil
        task?.cancel()
        task = nil
        if case .running = state { state = .idle }
    }

    private func current(_ id: UUID) -> Bool { runID == id && !Task.isCancelled }

    private func finish(_ id: UUID, _ newState: State) {
        guard runID == id else { return }
        runID = nil
        task = nil
        state = newState
    }

    private func perform(id: UUID, description: String, onDone: ((Look) -> Void)?) async {
        let pre = await preflight(for: id)
        guard current(id) else { return }
        if !pre.missing.isEmpty {
            finish(id, .preflightFailed(pre.missing))
            return
        }
        let probe = await CLIProbe.current()
        guard current(id) else { return }
        guard let codex = probe.locate("codex") else {
            finish(id, .failed(HatchPreflight.codexNotFoundMessage))
            return
        }
        guard let runDir = makeRunDirectory() else {
            finish(id, .failed("Could not create the working folder for generation"))
            return
        }
        let invocation = HatchInvocation.make(codex: codex, description: description, runDir: runDir,
                                              path: probe.childPATH(for: codex))
        do {
            _ = try await runner.run(invocation)
        } catch {
            if !current(id) {
                removeRunDirectory(runDir) // cancelled: nothing to inspect
                return
            }
            let message: String
            switch error {
            case CLIError.timedOut: message = "Generation took too long (40 min) and was stopped."
            case CLIError.nonZeroExit(let code, let stderr):
                let tail = String(stderr.suffix(300)).trimmingCharacters(in: .whitespacesAndNewlines)
                message = "Codex exited with code \(code)." + (tail.isEmpty ? "" : " \(tail)")
            case CLIError.launchFailed(let detail): message = "Could not start Codex: \(detail)"
            default: message = String(describing: error)
            }
            finish(id, .failed(message)) // run dir kept for diagnosis
            return
        }
        guard current(id) else { removeRunDirectory(runDir); return }

        let out = HatchInvocation.outputDirectory(runDir: runDir)
        let outcome = await Task.detached { Self.validate(out: out) }.value
        guard current(id) else { removeRunDirectory(runDir); return }
        switch outcome {
        case .failure(let problem):
            finish(id, .failed("Generation finished but the sheet is invalid: \(problem)")) // run dir kept
        case .success(let manifest):
            do {
                let look = try install(out: out, manifest: manifest)
                removeRunDirectory(runDir)
                finish(id, .done(look))
                onLookAdded()
                onDone?(look)
            } catch {
                finish(id, .failed("Generation finished but the look could not be saved: \(error.localizedDescription)"))
            }
        }
    }

    // MARK: Validation (no actor state)

    private struct Invalid: Error, CustomStringConvertible { var description: String }

    nonisolated private static func validate(out: URL) -> Result<PetManifest, Invalid> {
        let fm = FileManager.default
        guard Self.isRealDirectory(out) else { return .failure(Invalid(description: "no out/ folder was produced")) }
        // A symlink anywhere in out/ could smuggle a file from outside the run folder into a look.
        if let walker = fm.enumerator(at: out, includingPropertiesForKeys: [.isSymbolicLinkKey]) {
            for case let url as URL in walker {
                if (try? url.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) == true {
                    return .failure(Invalid(description: "out/ contains a symbolic link"))
                }
            }
        }
        guard let manifest = try? PetManifest.load(from: out) else {
            return .failure(Invalid(description: "out/pet.json is missing or unreadable"))
        }
        let sheet = out.appendingPathComponent(manifest.spritesheetPath)
        guard contained(sheet, in: out), fm.fileExists(atPath: sheet.path) else {
            return .failure(Invalid(description: "the spritesheet named in pet.json is missing"))
        }
        switch SpriteSheetValidator.validate(fileAt: sheet) {
        case .success: return .success(manifest)
        case .failure(.wrongSize(let w, let h)): return .failure(Invalid(description: "wrong size \(w)×\(h)"))
        case .failure(.emptyRow(let name)): return .failure(Invalid(description: "row \"\(name)\" is empty"))
        case .failure(.unreadable): return .failure(Invalid(description: "the image could not be read"))
        }
    }

    // MARK: Disk (symlink-safe)

    nonisolated private static func isRealDirectory(_ url: URL) -> Bool {
        guard let values = try? url.resourceValues(forKeys: [.isSymbolicLinkKey, .isDirectoryKey]) else { return false }
        return values.isSymbolicLink != true && values.isDirectory == true
    }

    nonisolated private static func isSymlink(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) == true
    }

    /// True when the symlink-resolved `child` is strictly under the symlink-resolved `root`.
    nonisolated private static func contained(_ child: URL, in root: URL) -> Bool {
        let rootPath = root.resolvingSymlinksInPath().standardizedFileURL.path
        let childPath = child.resolvingSymlinksInPath().standardizedFileURL.path
        return childPath.hasPrefix(rootPath.hasSuffix("/") ? rootPath : rootPath + "/")
    }

    /// False when `supportRoot` is a symlink, or when it (or its nearest existing ancestor) resolves
    /// somewhere other than its own standardized path, i.e. is redirected by any path component.
    private func supportRootIsSafe() -> Bool {
        let fm = FileManager.default
        var url = supportRoot.standardizedFileURL
        if Self.isSymlink(url) { return false }
        while !fm.fileExists(atPath: url.path), url.path != "/" {
            if Self.isSymlink(url) { return false } // dangling link
            url = url.deletingLastPathComponent()
        }
        return url.resolvingSymlinksInPath().path == url.standardizedFileURL.path
    }

    /// Creates `hatch/<run-id>/`, refusing a symlinked `hatch/` or a redirected `support/`.
    private func makeRunDirectory() -> URL? {
        let fm = FileManager.default
        guard supportRootIsSafe() else { return nil }
        do {
            try fm.createDirectory(at: supportRoot, withIntermediateDirectories: true)
            guard supportRootIsSafe() else { return nil }
            if !fm.fileExists(atPath: hatchRoot.path) {
                try fm.createDirectory(at: hatchRoot, withIntermediateDirectories: false)
            }
            guard Self.isRealDirectory(hatchRoot) else { return nil }
            let dir = hatchRoot.appendingPathComponent(UUID().uuidString, isDirectory: true)
            try fm.createDirectory(at: dir, withIntermediateDirectories: false)
            guard Self.contained(dir, in: hatchRoot), Self.isRealDirectory(dir) else {
                if runDirectoryIsSafe(dir) { try? fm.removeItem(at: dir) }
                return nil
            }
            return dir
        } catch {
            return nil
        }
    }

    /// Full guard run immediately before any delete/move touching a run dir: support/ not redirected,
    /// hatch/ a real directory, the run dir a real (non-symlink) directory inside hatch/.
    private func runDirectoryIsSafe(_ dir: URL) -> Bool {
        supportRootIsSafe() && Self.isRealDirectory(hatchRoot)
            && Self.isRealDirectory(dir) && Self.contained(dir, in: hatchRoot)
    }

    private func removeRunDirectory(_ dir: URL) {
        guard runDirectoryIsSafe(dir) else { return }
        try? FileManager.default.removeItem(at: dir)
    }

    private func install(out: URL, manifest: PetManifest) throws -> Look {
        let fm = FileManager.default
        guard supportRootIsSafe() else { throw CocoaError(.fileWriteInvalidFileName) }
        try fm.createDirectory(at: supportRoot, withIntermediateDirectories: true)
        guard supportRootIsSafe() else { throw CocoaError(.fileWriteInvalidFileName) }
        if !fm.fileExists(atPath: looksRoot.path) {
            try fm.createDirectory(at: looksRoot, withIntermediateDirectories: false)
        }
        guard Self.isRealDirectory(looksRoot), Self.isRealDirectory(out) else {
            throw CocoaError(.fileWriteInvalidFileName)
        }
        let taken = Set((try? fm.contentsOfDirectory(atPath: looksRoot.path)) ?? [])
        let lookID = MemberID.make(name: manifest.displayName.isEmpty ? manifest.id : manifest.displayName,
                                   existing: taken)
        let dest = looksRoot.appendingPathComponent(lookID, isDirectory: true)
        guard !fm.fileExists(atPath: dest.path), !Self.isSymlink(dest),
              Self.contained(dest, in: looksRoot) else {
            throw CocoaError(.fileWriteFileExists)
        }
        // Re-check everything immediately before the move: looks/ and the source chain hatch/ > run > out/.
        let runDir = out.deletingLastPathComponent()
        guard supportRootIsSafe(), Self.isRealDirectory(looksRoot), Self.isRealDirectory(hatchRoot),
              Self.isRealDirectory(runDir), Self.contained(runDir, in: hatchRoot),
              Self.isRealDirectory(out), Self.contained(out, in: runDir),
              Self.contained(dest, in: looksRoot), !Self.isSymlink(dest) else {
            throw CocoaError(.fileWriteInvalidFileName)
        }
        try fm.moveItem(at: out, to: dest)
        let pet = try PetManifest.load(from: dest)
        return Look(id: lookID, folder: dest, pet: pet, source: .squai)
    }

    // MARK: Launch cleanup

    /// Deletes `hatch/*` entries older than 24 h (leftovers from failed or interrupted runs).
    /// Symlinks are never followed or removed through.
    func sweepStaleRuns(now: Date = Date()) {
        let fm = FileManager.default
        guard supportRootIsSafe(), Self.isRealDirectory(hatchRoot),
              let entries = try? fm.contentsOfDirectory(at: hatchRoot, includingPropertiesForKeys: nil) else { return }
        for entry in entries {
            guard !Self.isSymlink(entry), Self.contained(entry, in: hatchRoot),
                  let modified = (try? fm.attributesOfItem(atPath: entry.path))?[.modificationDate] as? Date,
                  now.timeIntervalSince(modified) > 24 * 3600 else { continue }
            guard supportRootIsSafe(), Self.isRealDirectory(hatchRoot), !Self.isSymlink(entry),
                  Self.contained(entry, in: hatchRoot) else { continue }
            try? fm.removeItem(at: entry)
        }
    }
}
