import Foundation

public struct CLILocator: Sendable {
    public static let fixedDirs = [
        "/opt/homebrew/bin", "/usr/local/bin", "~/.local/bin", "~/.claude/local",
        "~/.npm-global/bin", "~/.bun/bin"
    ]

    public init() {}

    public func locate(_ name: String, loginShellPath: String?, home: URL,
                       isExecutable: (String) -> Bool) -> URL? {
        for directory in Self.searchDirs(loginShellPath: loginShellPath, home: home) {
            let candidate = URL(fileURLWithPath: directory).appendingPathComponent(name)
            if isExecutable(candidate.path) { return candidate }
        }
        return nil
    }

    public static func childPATH(cliDir: URL, loginShellPath: String?, home: URL) -> String {
        let directories = [cliDir.path] + searchDirs(loginShellPath: loginShellPath, home: home)
            + ["/usr/bin", "/bin", "/usr/sbin", "/sbin"]
        var seen = Set<String>()
        return directories.filter { seen.insert($0).inserted }.joined(separator: ":")
    }

    public static func loginShellPATH(shell: String) async -> String? {
        guard let cwd = try? makeRunDirectory() else { return nil }
        defer { try? FileManager.default.removeItem(at: cwd) }
        let inv = CLIInvocation(executable: URL(fileURLWithPath: shell),
                                arguments: ["-lic", "printf %s \"$PATH\""], stdin: "", cwd: cwd,
                                environment: ProcessInfo.processInfo.environment, timeout: 3)
        guard let result = try? await CLIRunner().run(inv), !result.output.isEmpty else { return nil }
        return result.output
    }

    public static func makeRunDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("squai-run-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        return directory
    }

    private static func searchDirs(loginShellPath: String?, home: URL) -> [String] {
        let loginDirs = loginShellPath?.split(separator: ":").map(String.init) ?? []
        return loginDirs + fixedDirs.map {
            $0.hasPrefix("~/") ? home.appendingPathComponent(String($0.dropFirst(2))).path : $0
        }
    }
}
