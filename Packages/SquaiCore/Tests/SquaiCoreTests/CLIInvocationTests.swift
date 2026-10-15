import Foundation
import XCTest
@testable import SquaiCore

final class CLIInvocationTests: XCTestCase {
    private let cwd = URL(fileURLWithPath: "/tmp/squai-builder-test", isDirectory: true)
    private let home = URL(fileURLWithPath: "/tmp/squai-test-home", isDirectory: true)
    private let prompt = "PRIVATE selection\n日本語"

    func testClaudeExactInvocation() {
        let executable = URL(fileURLWithPath: "/tmp/shims/claude")
        let inv = CLIBuilders.claude(executable: executable, prompt: prompt, cwd: cwd, path: "/test/bin")
        XCTAssertEqual(CLIBuilders.systemPrompt, "You transform text for the user. Follow the instruction exactly. Output only the result, with no preamble.")
        XCTAssertEqual(inv.arguments, [
            "-p", "--model", "haiku", "--output-format", "text", "--tools", "",
            "--setting-sources", "", "--strict-mcp-config", "--no-session-persistence",
            "--disable-slash-commands", "--system-prompt",
            "You transform text for the user. Follow the instruction exactly. Output only the result, with no preamble."
        ])
        XCTAssertEqual(inv.executable, executable)
        XCTAssertEqual(inv.stdin, prompt)
        XCTAssertFalse(inv.arguments.contains { $0.contains(prompt) })
        XCTAssertEqual(inv.cwd, cwd)
        XCTAssertEqual(inv.environment, expectedEnvironment())
        XCTAssertEqual(inv.timeout, 30)
        XCTAssertNil(inv.outputFile)
    }

    func testCodexExactInvocation() {
        let executable = URL(fileURLWithPath: "/tmp/shims/codex")
        let inv = CLIBuilders.codex(executable: executable, prompt: prompt, cwd: cwd, path: "/test/bin")
        XCTAssertEqual(inv.arguments, [
            "exec", "--skip-git-repo-check", "--ephemeral", "--sandbox", "read-only",
            "--ignore-rules", "--color", "never", "-c", "model_reasoning_effort=\"low\"",
            "-C", cwd.path, "-o", cwd.appendingPathComponent("last-message.txt").path, "-"
        ])
        XCTAssertEqual(inv.executable, executable)
        XCTAssertEqual(inv.stdin, prompt)
        XCTAssertFalse(inv.arguments.contains { $0.contains(prompt) })
        XCTAssertEqual(inv.cwd, cwd)
        XCTAssertEqual(inv.environment, expectedEnvironment())
        XCTAssertEqual(inv.timeout, 60)
        XCTAssertEqual(inv.outputFile, cwd.appendingPathComponent("last-message.txt"))
    }

    func testLocatorUsesLoginPathOrderBeforeFixedDirectories() {
        var checked: [String] = []
        let found = CLILocator().locate("claude", loginShellPath: "/first:/second:/third", home: home) {
            checked.append($0)
            return ["/second/claude", "/third/claude", "/opt/homebrew/bin/claude"].contains($0)
        }
        XCTAssertEqual(found?.path, "/second/claude")
        XCTAssertEqual(checked, ["/first/claude", "/second/claude"])
    }

    func testLocatorFixedOrderAndHomeExpansion() {
        XCTAssertEqual(CLILocator.fixedDirs, [
            "/opt/homebrew/bin", "/usr/local/bin", "~/.local/bin", "~/.claude/local",
            "~/.npm-global/bin", "~/.bun/bin"
        ])
        let fixed = ["/opt/homebrew/bin", "/usr/local/bin", home.path + "/.local/bin",
                     home.path + "/.claude/local", home.path + "/.npm-global/bin", home.path + "/.bun/bin"]
        for (index, directory) in fixed.enumerated() {
            var checked: [String] = []
            let found = CLILocator().locate("codex", loginShellPath: "/missing", home: home) {
                checked.append($0)
                return $0 == directory + "/codex"
            }
            XCTAssertEqual(found?.path, directory + "/codex")
            XCTAssertEqual(checked, ["/missing/codex"] + fixed.prefix(index + 1).map { $0 + "/codex" })
        }
        XCTAssertNil(CLILocator().locate("codex", loginShellPath: nil, home: home) { _ in false })
    }

    func testChildPathOrderAndDeduplication() {
        XCTAssertEqual(CLILocator.childPATH(cliDir: URL(fileURLWithPath: "/cli"),
                                            loginShellPath: "/cli:/login:/usr/bin:/login:/opt/homebrew/bin", home: home),
                       ["/cli", "/login", "/usr/bin", "/opt/homebrew/bin", "/usr/local/bin",
                        home.path + "/.local/bin", home.path + "/.claude/local",
                        home.path + "/.npm-global/bin", home.path + "/.bun/bin",
                        "/bin", "/usr/sbin", "/sbin"].joined(separator: ":"))
        XCTAssertEqual(CLILocator.childPATH(cliDir: URL(fileURLWithPath: "/cli"), loginShellPath: nil, home: home),
                       ["/cli", "/opt/homebrew/bin", "/usr/local/bin", home.path + "/.local/bin",
                        home.path + "/.claude/local", home.path + "/.npm-global/bin", home.path + "/.bun/bin",
                        "/usr/bin", "/bin", "/usr/sbin", "/sbin"].joined(separator: ":"))
    }

    func testRunDirectoriesAreUniqueEmptyAndTemporary() throws {
        let first = try CLILocator.makeRunDirectory()
        defer { try? FileManager.default.removeItem(at: first) }
        let second = try CLILocator.makeRunDirectory()
        defer { try? FileManager.default.removeItem(at: second) }
        XCTAssertNotEqual(first, second)
        for directory in [first, second] {
            XCTAssertTrue(directory.lastPathComponent.hasPrefix("squai-run-"))
            XCTAssertNotNil(UUID(uuidString: String(directory.lastPathComponent.dropFirst("squai-run-".count))))
            XCTAssertEqual(directory.deletingLastPathComponent().standardizedFileURL,
                           FileManager.default.temporaryDirectory.standardizedFileURL)
            XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: directory.path), [])
        }
    }

    func testChildEnvironmentPassesLoginIdentityAndLocaleOnly() {
        let base = ["HOME": "/Users/u", "USER": "u", "LOGNAME": "u", "TMPDIR": "/var/folders/x/T/",
                    "LANG": "ja_JP.UTF-8", "__CF_USER_TEXT_ENCODING": "0x1F5:0x1:0xE",
                    "PATH": "/launchd/path", "ANTHROPIC_API_KEY": "stub-secret", "SHELL": "/bin/zsh"]
        XCTAssertEqual(CLIBuilders.childEnvironment(path: "/test/bin", base: base), [
            "PATH": "/test/bin", "HOME": "/Users/u", "USER": "u", "LOGNAME": "u",
            "TMPDIR": "/var/folders/x/T/", "LANG": "ja_JP.UTF-8", "__CF_USER_TEXT_ENCODING": "0x1F5:0x1:0xE"
        ])
        XCTAssertEqual(CLIBuilders.childEnvironment(path: "/test/bin", base: [:]), ["PATH": "/test/bin"])
    }

    private func expectedEnvironment() -> [String: String] {
        CLIBuilders.childEnvironment(path: "/test/bin", base: ProcessInfo.processInfo.environment)
    }
}
