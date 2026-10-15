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

/// The one CLI lookup shared by runs and Settings → Backends. The login-shell PATH costs a shell
/// launch, so it is cached and only re-read by `refresh()` (launch and Recheck). The executable
/// itself is located again on every call, so a CLI removed after launch is never handed to a run.
public final class CLIResolver: @unchecked Sendable {
    private let lock = NSLock()
    private var loginShellPath: String?
    private let home: URL
    private let isExecutable: @Sendable (String) -> Bool
    private let fetchLoginShellPath: @Sendable () async -> String?

    public init(home: URL,
                isExecutable: @escaping @Sendable (String) -> Bool = { FileManager.default.isExecutableFile(atPath: $0) },
                fetchLoginShellPath: @escaping @Sendable () async -> String?) {
        self.home = home
        self.isExecutable = isExecutable
        self.fetchLoginShellPath = fetchLoginShellPath
    }

    public func refresh() async {
        let path = await fetchLoginShellPath()
        lock.withLock { loginShellPath = path }
    }

    public func locate(_ backend: Backend) -> URL? {
        let name = backend == .claude ? "claude" : "codex"
        return CLILocator().locate(name, loginShellPath: lock.withLock { loginShellPath }, home: home,
                                   isExecutable: isExecutable)
    }

    public func childPATH(for cli: URL) -> String {
        CLILocator.childPATH(cliDir: cli.deletingLastPathComponent(),
                             loginShellPath: lock.withLock { loginShellPath }, home: home)
    }
}
