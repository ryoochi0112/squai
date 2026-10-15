import Foundation

public struct CLIInvocation: Equatable, Sendable {
    public var executable: URL
    public var arguments: [String]
    public var stdin: String
    public var cwd: URL
    public var environment: [String: String]
    public var timeout: TimeInterval
    public var outputFile: URL?

    public init(executable: URL, arguments: [String], stdin: String, cwd: URL,
                environment: [String: String], timeout: TimeInterval, outputFile: URL? = nil) {
        self.executable = executable
        self.arguments = arguments
        self.stdin = stdin
        self.cwd = cwd
        self.environment = environment
        self.timeout = timeout
        self.outputFile = outputFile
    }
}

public enum CLIBuilders {
    public static let systemPrompt = "You transform text for the user. Follow the instruction exactly. Output only the result, with no preamble."

    public static func claude(executable: URL, prompt: String, cwd: URL, path: String) -> CLIInvocation {
        CLIInvocation(executable: executable, arguments: [
            "-p", "--model", "haiku", "--output-format", "text", "--tools", "",
            "--setting-sources", "", "--strict-mcp-config", "--no-session-persistence",
            "--disable-slash-commands", "--system-prompt", systemPrompt
        ], stdin: prompt, cwd: cwd, environment: environment(path: path), timeout: 30)
    }

    public static func codex(executable: URL, prompt: String, cwd: URL, path: String) -> CLIInvocation {
        let outputFile = cwd.appendingPathComponent("last-message.txt")
        return CLIInvocation(executable: executable, arguments: [
            "exec", "--skip-git-repo-check", "--ephemeral", "--sandbox", "read-only",
            "--ignore-rules", "--color", "never", "-c", "model_reasoning_effort=\"low\"",
            "-C", cwd.path, "-o", outputFile.path, "-"
        ], stdin: prompt, cwd: cwd, environment: environment(path: path), timeout: 60,
        outputFile: outputFile)
    }

    /// Variables copied from the app into every CLI child. `claude` reads its login from the
    /// Keychain by `USER`; without it the CLI reports "Not logged in".
    public static let passthroughVariables = ["HOME", "USER", "LOGNAME", "TMPDIR", "LANG",
                                              "__CF_USER_TEXT_ENCODING"]

    public static func childEnvironment(path: String,
                                        base: [String: String] = ProcessInfo.processInfo.environment)
        -> [String: String] {
        var result = ["PATH": path]
        for name in passthroughVariables {
            if let value = base[name] { result[name] = value }
        }
        return result
    }

    private static func environment(path: String) -> [String: String] {
        childEnvironment(path: path)
    }
}
