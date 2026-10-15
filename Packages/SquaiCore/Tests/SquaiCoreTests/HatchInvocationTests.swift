import Foundation
import XCTest
@testable import SquaiCore

final class HatchInvocationTests: XCTestCase {
    private let codex = URL(fileURLWithPath: "/test/bin/codex")
    private let runDir = URL(fileURLWithPath: "/tmp/squai-hatch-test", isDirectory: true)
    private let petDescription = "A tiny blue fox with a scarf"

    func testBuildsExactHatchInvocation() {
        let invocation = HatchInvocation.make(codex: codex, description: petDescription, runDir: runDir, path: "/test/bin:/usr/bin")

        XCTAssertEqual(invocation.executable, codex)
        XCTAssertEqual(invocation.arguments, [
            "exec", "--skip-git-repo-check", "--sandbox", "workspace-write", "--color", "never",
            "-C", runDir.path, "-"
        ])
        XCTAssertEqual(invocation.arguments[invocation.arguments.firstIndex(of: "--sandbox")! + 1], "workspace-write")
        XCTAssertFalse(invocation.arguments.contains("--add-dir"))
        XCTAssertEqual(invocation.stdin,
                       "Use $hatch-pet to create a pet. Description: A tiny blue fox with a scarf. Package the final `pet.json` and spritesheet into ./out/ (the staging dir) instead of ~/.codex/pets. Do not write anywhere else.")
        XCTAssertTrue(invocation.stdin.contains(petDescription))
        XCTAssertTrue(invocation.stdin.contains("./out/"))
        XCTAssertEqual(invocation.cwd, runDir)
        XCTAssertEqual(invocation.environment, expectedEnvironment(path: "/test/bin:/usr/bin"))
        XCTAssertEqual(invocation.timeout, 2400)
        XCTAssertEqual(HatchInvocation.timeout, 2400)
        XCTAssertNil(invocation.outputFile)
        XCTAssertEqual(HatchInvocation.outputDirectory(runDir: runDir), runDir.appendingPathComponent("out", isDirectory: true))
    }

    func testPreflightListsEachMissingRequirementWithExactLine() {
        XCTAssertEqual(HatchPreflight(codexFound: false, loggedInWithChatGPT: true,
                                      hatchSkillPresent: true, pillowPresent: true).missing,
                       ["Look generation needs the Codex CLI (`codex`), which was not found.",
                        "Make one in Codex with /hatch — it appears here automatically"])
        XCTAssertEqual(HatchPreflight(codexFound: true, loggedInWithChatGPT: false,
                                      hatchSkillPresent: true, pillowPresent: true).missing,
                       ["Look generation needs Codex logged in with ChatGPT: run `codex login` in Terminal.",
                        "Make one in Codex with /hatch — it appears here automatically"])
        XCTAssertEqual(HatchPreflight(codexFound: true, loggedInWithChatGPT: true,
                                      hatchSkillPresent: false, pillowPresent: true).missing,
                       ["Look generation needs the hatch-pet Codex skill (~/.codex/skills/hatch-pet).",
                        "Make one in Codex with /hatch — it appears here automatically"])
        XCTAssertEqual(HatchPreflight(codexFound: true, loggedInWithChatGPT: true,
                                      hatchSkillPresent: true, pillowPresent: false).missing,
                       ["Look generation needs Python Pillow: run `python3 -m pip install --user pillow` in Terminal.",
                        "Make one in Codex with /hatch — it appears here automatically"])
    }

    func testPreflightPreservesFailureOrderAndAllPassIsEmpty() {
        XCTAssertEqual(HatchPreflight(codexFound: false, loggedInWithChatGPT: false,
                                      hatchSkillPresent: false, pillowPresent: false).missing,
                       ["Look generation needs the Codex CLI (`codex`), which was not found.",
                        "Look generation needs Codex logged in with ChatGPT: run `codex login` in Terminal.",
                        "Look generation needs the hatch-pet Codex skill (~/.codex/skills/hatch-pet).",
                        "Look generation needs Python Pillow: run `python3 -m pip install --user pillow` in Terminal.",
                        "Make one in Codex with /hatch — it appears here automatically"])
        XCTAssertEqual(HatchPreflight(codexFound: true, loggedInWithChatGPT: true,
                                      hatchSkillPresent: true, pillowPresent: true).missing, [])
    }

    private func expectedEnvironment(path: String) -> [String: String] {
        CLIBuilders.childEnvironment(path: path, base: ProcessInfo.processInfo.environment)
    }
}
