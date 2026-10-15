import Darwin
import Foundation
import XCTest
@testable import SquaiCore

final class CLIRunnerTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        directory = try CLILocator.makeRunDirectory()
    }

    override func tearDownWithError() throws {
        try FileManager.default.removeItem(at: directory)
    }

    func testStdinArgumentsCwdEnvironmentAndTrimmedOutput() async throws {
        let shim = try script("""
        printf '%s\\n' "$@" > args.txt
        printf '%s' "$PWD" > cwd.txt
        printf '%s' "$PATH" > path.txt
        printf '%s' "$HOME" > home.txt
        /bin/cat
        printf 'diagnostic\\n' >&2
        """)
        let inv = invocation(shim, arguments: ["one", "", "two words", "日本語"], stdin: " \nHello 日本語\n ")
        let result = try await CLIRunner().run(inv)
        XCTAssertEqual(result.exitCode, 0)
        XCTAssertEqual(result.stdout, inv.stdin)
        XCTAssertEqual(result.stderr, "diagnostic\n")
        XCTAssertEqual(result.output, "Hello 日本語")
        XCTAssertEqual(try contents("args.txt"), "one\n\ntwo words\n日本語\n")
        let physicalCwd = try XCTUnwrap(realpath(directory.path, nil))
        defer { free(physicalCwd) }
        XCTAssertEqual(try contents("cwd.txt"), String(cString: physicalCwd))
        XCTAssertEqual(try contents("path.txt"), "/usr/bin:/bin")
        XCTAssertEqual(try contents("home.txt"), directory.path)
    }

    func testOutputFilePreferredVerbatimAndMissingFileFallsBack() async throws {
        let shim = try script("printf '  file body\\n' > last-message.txt\nprintf ' stdout body\\n'")
        var inv = invocation(shim)
        inv.outputFile = directory.appendingPathComponent("last-message.txt")
        let result = try await CLIRunner().run(inv)
        XCTAssertEqual(result.stdout, " stdout body\n")
        XCTAssertEqual(result.output, "  file body\n")
        inv.outputFile = directory.appendingPathComponent("missing.txt")
        let fallback = try await CLIRunner().run(inv)
        XCTAssertEqual(fallback.output, "stdout body")
    }

    func testEmptyOutputFileStillWins() async throws {
        let shim = try script(": > last-message.txt\nprintf 'stdout'")
        var inv = invocation(shim)
        inv.outputFile = directory.appendingPathComponent("last-message.txt")
        let result = try await CLIRunner().run(inv)
        XCTAssertEqual(result.output, "")
        XCTAssertEqual(result.stdout, "stdout")
    }

    func testNonzeroExitSurfacesCodeAndStderrEvenWithLargeUnconsumedInput() async throws {
        let shim = try script("printf 'failed\\n' >&2\nexit 23")
        do {
            _ = try await CLIRunner().run(invocation(shim, stdin: String(repeating: "x", count: 1_048_576)))
            XCTFail("Expected nonzero exit")
        } catch let error as CLIError {
            XCTAssertEqual(error, .nonZeroExit(code: 23, stderr: "failed\n"))
        }
    }

    func testLaunchFailure() async throws {
        do {
            _ = try await CLIRunner().run(invocation(directory.appendingPathComponent("missing-shim")))
            XCTFail("Expected launch failure")
        } catch let error as CLIError {
            guard case .launchFailed(let message) = error else { return XCTFail("Unexpected error: \(error)") }
            XCTAssertFalse(message.isEmpty)
        }
    }

    func testOneMegabyteStdinAndConcurrentLargeStdoutStderr() async throws {
        // Fill both output pipes before reading stdin: serial IO would deadlock here.
        let shim = try script("""
        /usr/bin/head -c 1048576 /dev/zero
        /usr/bin/head -c 1048576 /dev/zero >&2
        /bin/cat
        """)
        let input = String(repeating: "x", count: 1_048_576)
        let result = try await CLIRunner().run(invocation(shim, stdin: input))
        XCTAssertEqual(result.stdout.utf8.count, 2_097_152)
        XCTAssertEqual(result.stderr.utf8.count, 1_048_576)
        XCTAssertEqual(String(result.stdout.suffix(input.count)), input)
        XCTAssertEqual(result.exitCode, 0)
    }

    func testTimeoutTerminatesSleepAndReapsPID() async throws {
        try await assertTimeout(scriptBody: "echo $$ > pid.txt\nexec /bin/sleep 60")
    }

    func testTimeoutForceKillsChildIgnoringSIGTERM() async throws {
        try await assertTimeout(scriptBody: "trap '' TERM\necho $$ > pid.txt\nexec /bin/sleep 60")
    }

    func testLoginShellPathExactArgumentsAndFailures() async throws {
        let shim = try script("""
        [ "$#" -eq 2 ] || exit 11
        [ "$1" = '-lic' ] || exit 12
        [ "$2" = 'printf %s "$PATH"' ] || exit 13
        printf '/shim/bin:/usr/bin'
        """)
        let path = await CLILocator.loginShellPATH(shell: shim.path)
        XCTAssertEqual(path, "/shim/bin:/usr/bin")
        let failure = try script("exit 7")
        let failedPath = await CLILocator.loginShellPATH(shell: failure.path)
        XCTAssertNil(failedPath)
        let empty = try script("exit 0")
        let emptyPath = await CLILocator.loginShellPATH(shell: empty.path)
        XCTAssertNil(emptyPath)
        let missingPath = await CLILocator.loginShellPATH(shell: directory.appendingPathComponent("absent").path)
        XCTAssertNil(missingPath)
    }

    func testLoginShellPathTimesOutAtThreeSecondsAndReapsChild() async throws {
        let shim = try script("echo $$ > \"$0.pid\"\nexec /bin/sleep 60")
        let started = ProcessInfo.processInfo.systemUptime
        let path = await CLILocator.loginShellPATH(shell: shim.path)
        let elapsed = ProcessInfo.processInfo.systemUptime - started
        XCTAssertNil(path)
        XCTAssertGreaterThanOrEqual(elapsed, 3)
        XCTAssertLessThan(elapsed, 6)
        let text = try String(contentsOfFile: shim.path + ".pid", encoding: .utf8)
        let pid = try XCTUnwrap(Int32(text.trimmingCharacters(in: .whitespacesAndNewlines)))
        XCTAssertEqual(kill(pid, 0), -1)
        XCTAssertEqual(errno, ESRCH)
    }

    private func assertTimeout(scriptBody: String) async throws {
        let shim = try script(scriptBody)
        var inv = invocation(shim)
        inv.timeout = 1
        let started = ProcessInfo.processInfo.systemUptime
        do {
            _ = try await CLIRunner().run(inv)
            XCTFail("Expected timeout")
        } catch let error as CLIError {
            XCTAssertEqual(error, .timedOut(seconds: 1))
        }
        XCTAssertLessThan(ProcessInfo.processInfo.systemUptime - started, 4)
        let pid = try XCTUnwrap(Int32(contents("pid.txt").trimmingCharacters(in: .whitespacesAndNewlines)))
        XCTAssertEqual(kill(pid, 0), -1, "Child must be gone when run returns")
        XCTAssertEqual(errno, ESRCH)
    }

    private func script(_ body: String) throws -> URL {
        let url = directory.appendingPathComponent("shim-\(UUID().uuidString)")
        try ("#!/bin/sh\n" + body + "\n").write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: url.path)
        return url
    }

    private func invocation(_ executable: URL, arguments: [String] = [], stdin: String = "") -> CLIInvocation {
        CLIInvocation(executable: executable, arguments: arguments, stdin: stdin, cwd: directory,
                      environment: ["PATH": "/usr/bin:/bin", "HOME": directory.path], timeout: 10)
    }

    private func contents(_ name: String) throws -> String {
        try String(contentsOf: directory.appendingPathComponent(name), encoding: .utf8)
    }
}
