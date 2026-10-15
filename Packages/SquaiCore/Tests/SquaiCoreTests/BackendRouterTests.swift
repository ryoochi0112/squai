import XCTest
@testable import SquaiCore

private struct RouterRunner: CLIRunning {
    var handler: @Sendable (CLIInvocation) throws -> CLIResult = { _ in
        XCTFail("Unexpected CLI run")
        return CLIResult(exitCode: 0, stdout: "", stderr: "", output: "")
    }

    func run(_ invocation: CLIInvocation) async throws -> CLIResult {
        try handler(invocation)
    }
}

private struct RouterTransport: HTTPTransport {
    var status = 200
    var body = #"{"content":[{"type":"text","text":" API result\n"}]}"#
    var capture: @Sendable (URLRequest) throws -> Void = { _ in XCTFail("Unexpected HTTP request") }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        try capture(request)
        return (Data(body.utf8), HTTPURLResponse(url: request.url!, statusCode: status,
                                               httpVersion: nil, headerFields: nil)!)
    }
}

final class BackendRouterTests: XCTestCase {
    private let prompt = "Rewrite politely\n\n明日来れる？"

    private func router(locate: @escaping @Sendable (Backend) -> URL? = { _ in nil },
                        key: @escaping @Sendable () -> String? = { nil },
                        runner: RouterRunner = RouterRunner(),
                        transport: RouterTransport = RouterTransport(),
                        directory: @escaping @Sendable () throws -> URL = {
                            XCTFail("Unexpected run directory creation")
                            return URL(fileURLWithPath: "/private/tmp/unused-router-directory")
                        }) -> BackendRouter {
        BackendRouter(locateCLI: locate, childPATH: { url in
            "\(url.deletingLastPathComponent().path):/usr/bin:/bin"
        }, claudeKey: key, runner: runner, transport: transport, makeRunDirectory: directory)
    }

    private func assertError(_ router: BackendRouter, backend: Backend, expected: BackendError,
                             file: StaticString = #filePath, line: UInt = #line) async {
        do {
            _ = try await router.run(backend: backend, prompt: prompt)
            XCTFail("Expected \(expected)", file: file, line: line)
        } catch {
            XCTAssertEqual(error as? BackendError, expected, file: file, line: line)
        }
    }

    func testCLIWinsWithoutReadingKeyAndUsesExactBuilders() async throws {
        for backend in [Backend.claude, .chatgpt] {
            let cli = URL(fileURLWithPath: "/stub/bin/\(backend == .claude ? "claude" : "codex")")
            let directory = try CLILocator.makeRunDirectory()
            defer { try? FileManager.default.removeItem(at: directory) }
            let prompt = self.prompt
            let expected = backend == .claude
                ? CLIBuilders.claude(executable: cli, prompt: prompt, cwd: directory, path: "/stub/bin:/usr/bin:/bin")
                : CLIBuilders.codex(executable: cli, prompt: prompt, cwd: directory, path: "/stub/bin:/usr/bin:/bin")
            let router = router(locate: {
                XCTAssertEqual($0, backend)
                return cli
            }, key: { XCTFail("CLI must win without reading key"); return "stub-key" },
            runner: RouterRunner(handler: { invocation in
                XCTAssertTrue(FileManager.default.fileExists(atPath: invocation.cwd.path))
                XCTAssertEqual(invocation, expected)
                XCTAssertEqual(invocation.arguments, expected.arguments)
                XCTAssertEqual(invocation.stdin, prompt)
                try Data("stray CLI write".utf8).write(to: directory.appendingPathComponent("stray.txt"))
                return CLIResult(exitCode: 0, stdout: "ignored", stderr: "", output: " \nCLI result\t ")
            }), directory: { directory })
            let output = try await router.run(backend: backend, prompt: prompt)
            XCTAssertEqual(output, "CLI result")
            XCTAssertFalse(FileManager.default.fileExists(atPath: directory.path))
        }
    }

    func testClaudeFallsBackToGenericAPIRequestWithoutRunDirectory() async throws {
        let prompt = self.prompt
        let router = router(locate: { XCTAssertEqual($0, .claude); return nil }, key: { "stub-key" },
                            transport: RouterTransport(capture: { request in
            XCTAssertEqual(request.url, ClaudeAPI.endpoint)
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertEqual(request.value(forHTTPHeaderField: "x-api-key"), "stub-key")
            XCTAssertEqual(request.value(forHTTPHeaderField: "anthropic-version"), ClaudeAPI.version)
            XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")
            let body = try JSONDecoder().decode(ClaudeAPI.Request.self, from: XCTUnwrap(request.httpBody))
            XCTAssertEqual(body.system, CLIBuilders.systemPrompt)
            XCTAssertEqual(body.model, ClaudeAPI.defaultModel)
            XCTAssertEqual(body.max_tokens, 1024)
            XCTAssertEqual(body.output_config?.effort, "low")
            XCTAssertEqual(body.messages.count, 1)
            XCTAssertEqual(body.messages.first?.role, "user")
            XCTAssertEqual(body.messages.first?.content, prompt)
        }))
        let output = try await router.run(backend: .claude, prompt: prompt)
        XCTAssertEqual(output, "API result")
    }

    func testMissingSetupAndChatGPTNeverReadsClaudeKey() async {
        await assertError(router(), backend: .claude, expected: .notSetUp(.claude))
        await assertError(router(key: { "" }), backend: .claude, expected: .notSetUp(.claude))
        await assertError(router(locate: { XCTAssertEqual($0, .chatgpt); return nil }, key: {
            XCTFail("ChatGPT must not read Claude key")
            return "stub-key"
        }), backend: .chatgpt, expected: .notSetUp(.chatgpt))
    }

    func testCLIThrownErrorsAndCleanupForBothBackends() async throws {
        let longMessage = String(repeating: "界", count: 301)
        let cases: [(CLIError, (Backend) -> BackendError)] = [
            (.timedOut(seconds: 17), { .timedOut($0, seconds: 17) }),
            (.nonZeroExit(code: 1, stderr: "not logged in"), { .notLoggedIn($0) }),
            (.nonZeroExit(code: 1, stderr: "Not logged in"), { .notLoggedIn($0) }),
            (.nonZeroExit(code: 1, stderr: "please /login"), { .notLoggedIn($0) }),
            (.nonZeroExit(code: 1, stderr: "LOGIN required"), { .notLoggedIn($0) }),
            (.nonZeroExit(code: 1, stderr: "Please LOG IN"), { .notLoggedIn($0) }),
            (.nonZeroExit(code: 9, stderr: " \nproblem\t "), { .failed($0, "problem") }),
            (.nonZeroExit(code: 7, stderr: " \n "), { .failed($0, "exit 7") }),
            (.nonZeroExit(code: 1, stderr: " \n\(longMessage)\n "), { .failed($0, String(longMessage.prefix(300))) }),
            (.launchFailed("Please log in"), { .notLoggedIn($0) }),
            (.launchFailed("could not launch"), { .failed($0, "could not launch") })
        ]
        for backend in [Backend.claude, .chatgpt] {
            for (error, expected) in cases {
                let directory = try CLILocator.makeRunDirectory()
                defer { try? FileManager.default.removeItem(at: directory) }
                let router = router(locate: { _ in URL(fileURLWithPath: "/stub/cli") }, key: {
                    XCTFail("CLI failures must not fall back to key"); return "stub-key"
                }, runner: RouterRunner(handler: { _ in throw error }), directory: { directory })
                await assertError(router, backend: backend, expected: expected(backend))
                XCTAssertFalse(FileManager.default.fileExists(atPath: directory.path), "\(error)")
            }
        }
    }

    func testCLIResultAuthEmptyAndNonzeroErrorsCleanUp() async throws {
        let cases: [(CLIResult, (Backend) -> BackendError)] = [
            (CLIResult(exitCode: 0, stdout: "", stderr: "", output: " \n\t "), { _ in .empty }),
            (CLIResult(exitCode: 2, stdout: "LOGIN required", stderr: "", output: ""), { .notLoggedIn($0) }),
            (CLIResult(exitCode: 2, stdout: "", stderr: "", output: "Please log in"), { .notLoggedIn($0) }),
            (CLIResult(exitCode: 2, stdout: "", stderr: " /login", output: ""), { .notLoggedIn($0) }),
            (CLIResult(exitCode: 2, stdout: "", stderr: " failure\n", output: ""), { .failed($0, "failure") }),
            (CLIResult(exitCode: 3, stdout: "", stderr: "", output: ""), { .failed($0, "exit 3") })
        ]
        for backend in [Backend.claude, .chatgpt] {
            for (result, expected) in cases {
                let directory = try CLILocator.makeRunDirectory()
                defer { try? FileManager.default.removeItem(at: directory) }
                let router = router(locate: { _ in URL(fileURLWithPath: "/stub/cli") },
                                    runner: RouterRunner(handler: { _ in result }), directory: { directory })
                await assertError(router, backend: backend, expected: expected(backend))
                XCTAssertFalse(FileManager.default.fileExists(atPath: directory.path))
            }
        }
    }

    func testExitZeroOutputMentioningLoginIsReturnedAsResult() async throws {
        for backend in [Backend.claude, .chatgpt] {
            for text in ["I am not logged in", "Please log in to continue", "/login"] {
                let directory = try CLILocator.makeRunDirectory()
                defer { try? FileManager.default.removeItem(at: directory) }
                let router = router(locate: { _ in URL(fileURLWithPath: "/stub/cli") },
                                    runner: RouterRunner(handler: { _ in
                    CLIResult(exitCode: 0, stdout: text, stderr: "", output: text)
                }), directory: { directory })
                let output = try await router.run(backend: backend, prompt: prompt)
                XCTAssertEqual(output, text)
            }
        }
    }

    func testAPIHTTPErrorTruncatesBodyAndRejectsNon2xx() async {
        let body = String(repeating: "界", count: 301)
        for status in [199, 300, 401, 500] {
            let router = router(key: { "stub-key" }, transport: RouterTransport(
                status: status, body: body, capture: { _ in }))
            await assertError(router, backend: .claude,
                              expected: .failed(.claude, "HTTP \(status): \(body.prefix(300))"))
        }
    }

    func testAPISuccessBoundaryEmptyAndRefusal() async throws {
        for status in [200, 299] {
            let router = router(key: { "stub-key" }, transport: RouterTransport(status: status, capture: { _ in }))
            let output = try await router.run(backend: .claude, prompt: prompt)
            XCTAssertEqual(output, "API result")
        }
        for (body, expected) in [
            (#"{"content":[{"type":"text","text":" \n "}]}"#, BackendError.empty),
            (#"{"content":[],"stop_reason":"refusal"}"#, BackendError.failed(.claude, "refused"))
        ] {
            await assertError(router(key: { "stub-key" }, transport: RouterTransport(body: body, capture: { _ in })),
                              backend: .claude, expected: expected)
        }
    }
}
