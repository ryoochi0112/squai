import Foundation

public struct HatchPreflight: Equatable {
    public var codexFound: Bool
    public var loggedInWithChatGPT: Bool
    public var hatchSkillPresent: Bool
    public var pillowPresent: Bool

    public static let codexNotFoundMessage = "Look generation needs the Codex CLI (`codex`), which was not found."
    public static let notLoggedInMessage = "Look generation needs Codex logged in with ChatGPT: run `codex login` in Terminal."
    public static let hatchSkillMissingMessage = "Look generation needs the hatch-pet Codex skill (~/.codex/skills/hatch-pet)."
    public static let pillowMissingMessage = "Look generation needs Python Pillow: run `python3 -m pip install --user pillow` in Terminal."
    public static let makeInCodexMessage = "Make one in Codex with /hatch — it appears here automatically"

    public init(codexFound: Bool, loggedInWithChatGPT: Bool, hatchSkillPresent: Bool,
                pillowPresent: Bool) {
        self.codexFound = codexFound
        self.loggedInWithChatGPT = loggedInWithChatGPT
        self.hatchSkillPresent = hatchSkillPresent
        self.pillowPresent = pillowPresent
    }

    public var missing: [String] {
        var lines: [String] = []
        if !codexFound { lines.append(Self.codexNotFoundMessage) }
        if !loggedInWithChatGPT { lines.append(Self.notLoggedInMessage) }
        if !hatchSkillPresent { lines.append(Self.hatchSkillMissingMessage) }
        if !pillowPresent { lines.append(Self.pillowMissingMessage) }
        if !lines.isEmpty { lines.append(Self.makeInCodexMessage) }
        return lines
    }
}

public enum HatchInvocation {
    public static let timeout: TimeInterval = 2400

    public static func make(codex: URL, description: String, runDir: URL, path: String) -> CLIInvocation {
        let prompt = "Use $hatch-pet to create a pet. Description: \(description). Package the final `pet.json` and spritesheet into ./out/ (the staging dir) instead of ~/.codex/pets. Do not write anywhere else."
        return CLIInvocation(executable: codex,
                             arguments: ["exec", "--skip-git-repo-check", "--sandbox", "workspace-write",
                                         "--color", "never", "-C", runDir.path, "-"],
                             stdin: prompt,
                             cwd: runDir,
                             environment: CLIBuilders.childEnvironment(path: path),
                             timeout: timeout)
    }

    public static func outputDirectory(runDir: URL) -> URL {
        runDir.appendingPathComponent("out", isDirectory: true)
    }
}
