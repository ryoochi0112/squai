import Foundation

public enum BackendError: Error, Equatable {
    case notSetUp(Backend)
    case notLoggedIn(Backend)
    case timedOut(Backend, seconds: TimeInterval)
    case failed(Backend, String)
    case empty
}

public protocol CLIRunning: Sendable {
    func run(_ invocation: CLIInvocation) async throws -> CLIResult
}

public struct BackendRouter: Sendable {
    public let locateCLI: @Sendable (Backend) -> URL?
    public let childPATH: @Sendable (URL) -> String
    public let claudeKey: @Sendable () -> String?
    public let runner: any CLIRunning
    public let transport: any HTTPTransport
    public let makeRunDirectory: @Sendable () throws -> URL

    public init(locateCLI: @escaping @Sendable (Backend) -> URL?,
                childPATH: @escaping @Sendable (URL) -> String,
                claudeKey: @escaping @Sendable () -> String?,
                runner: any CLIRunning, transport: any HTTPTransport,
                makeRunDirectory: @escaping @Sendable () throws -> URL) {
        self.locateCLI = locateCLI
        self.childPATH = childPATH
        self.claudeKey = claudeKey
        self.runner = runner
        self.transport = transport
        self.makeRunDirectory = makeRunDirectory
    }

    public func run(backend: Backend, prompt: String) async throws -> String {
        if let executable = locateCLI(backend) {
            let directory = try makeRunDirectory()
            defer { try? FileManager.default.removeItem(at: directory) }
            let invocation = backend == .claude
                ? CLIBuilders.claude(executable: executable, prompt: prompt, cwd: directory,
                                     path: childPATH(executable))
                : CLIBuilders.codex(executable: executable, prompt: prompt, cwd: directory,
                                    path: childPATH(executable))
            let result: CLIResult
            do {
                result = try await runner.run(invocation)
            } catch let error as CLIError {
                switch error {
                case .timedOut(let seconds):
                    throw BackendError.timedOut(backend, seconds: seconds)
                case .nonZeroExit(let code, let stderr):
                    throw Self.exitError(backend: backend, code: code, stderr: stderr)
                case .launchFailed(let message):
                    if Self.hasAuthHint(message) { throw BackendError.notLoggedIn(backend) }
                    throw BackendError.failed(backend, message)
                }
            }
            if result.exitCode != 0 {
                if Self.hasAuthHint(result.stdout) || Self.hasAuthHint(result.output) {
                    throw BackendError.notLoggedIn(backend)
                }
                throw Self.exitError(backend: backend, code: result.exitCode, stderr: result.stderr)
            }
            // Exit 0 is a real result, even when the text mentions logging in.
            let output = result.output.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !output.isEmpty else { throw BackendError.empty }
            return output
        }

        guard backend == .claude, let key = claudeKey(), !key.isEmpty else {
            throw BackendError.notSetUp(backend)
        }
        let body = ClaudeAPI.makePromptRequest(system: CLIBuilders.systemPrompt, user: prompt,
                                              model: ClaudeAPI.defaultModel)
        let request = try ClaudeAPI.makeURLRequest(body, apiKey: key)
        let (data, response) = try await transport.send(request)
        guard (200..<300).contains(response.statusCode) else {
            let body = String(decoding: data, as: UTF8.self)
            throw BackendError.failed(.claude, "HTTP \(response.statusCode): \(body.prefix(300))")
        }
        return try ClaudeAPI.parseText(data)
    }

    private static func hasAuthHint(_ text: String) -> Bool {
        let lower = text.lowercased()
        return lower.contains("not logged in") || lower.contains("login") || lower.contains("log in")
    }

    private static func exitError(backend: Backend, code: Int32, stderr: String) -> BackendError {
        if hasAuthHint(stderr) { return .notLoggedIn(backend) }
        let message = stderr.trimmingCharacters(in: .whitespacesAndNewlines)
        return .failed(backend, message.isEmpty ? "exit \(code)" : String(message.prefix(300)))
    }
}
