import Foundation
import XCTest
@testable import SquaiCore

final class SkillFileTests: XCTestCase {
    func testGoldenSkillSampleDecodes() throws {
        let json = """
        {
          "name": "Polite",
          "prompt": "Rewrite in polite business Japanese. Output only the rewritten text.",
          "backend": "claude",
          "hotkey": "opt+cmd+p",
          "visible": true
        }
        """

        let skill = try JSONDecoder().decode(SkillFile.self, from: Data(json.utf8))
        XCTAssertEqual(skill, SkillFile(
            name: "Polite",
            prompt: "Rewrite in polite business Japanese. Output only the rewritten text.",
            backend: .claude,
            hotkey: "opt+cmd+p",
            visible: true
        ))
        XCTAssertEqual(HotkeySpec(skill.hotkey!)?.normalized, "opt+cmd+p")
    }

    func testWriteAndLoadRoundTripAllFiveFields() throws {
        let folder = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: folder) }

        let expected = SkillFile(
            name: "Summarize",
            prompt: "Summarize in three bullets.",
            backend: .chatgpt,
            hotkey: "cmd+shift+s",
            visible: false
        )
        try expected.write(to: folder)

        XCTAssertEqual(try SkillFile.load(from: folder), expected)

        let encoded = try Data(contentsOf: folder.appendingPathComponent("skill.json"))
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        XCTAssertEqual(Set(object.keys), Set(["name", "prompt", "backend", "hotkey", "visible"]))
        XCTAssertEqual(object["backend"] as? String, "chatgpt")
        XCTAssertEqual(object["hotkey"] as? String, "cmd+shift+s")
    }

    func testUnknownKeysAreIgnored() throws {
        let json = """
        {"name":"Polite","prompt":"Rewrite.","backend":"claude","hotkey":null,"visible":true,"futureSetting":{"x":1}}
        """

        XCTAssertEqual(
            try JSONDecoder().decode(SkillFile.self, from: Data(json.utf8)),
            SkillFile(name: "Polite", prompt: "Rewrite.", backend: .claude, hotkey: nil, visible: true)
        )
    }

    func testUnknownBackendFailsToDecode() {
        let json = """
        {"name":"Polite","prompt":"Rewrite.","backend":"other","hotkey":null,"visible":true}
        """

        XCTAssertThrowsError(try JSONDecoder().decode(SkillFile.self, from: Data(json.utf8)))
    }

    func testHotkeyParsingAndNormalization() throws {
        let hotkey = try XCTUnwrap(HotkeySpec("cmd+opt+P"))
        XCTAssertEqual(hotkey.normalized, "opt+cmd+p")
        XCTAssertEqual(HotkeySpec("CTRL+SHIFT+F12")?.normalized, "ctrl+shift+f12")
        XCTAssertEqual(HotkeySpec("space")?.normalized, "space")
        XCTAssertEqual(HotkeySpec("cmd+CMD+p")?.normalized, "cmd+p")

        XCTAssertNil(HotkeySpec("cmd"))
        XCTAssertNil(HotkeySpec("foo+p"))
        XCTAssertNil(HotkeySpec(""))
        XCTAssertNil(HotkeySpec("p+q"))
        XCTAssertNil(HotkeySpec("cmd+f13"))
        XCTAssertNil(HotkeySpec("cmd++p"))
    }

    func testHotkeyCollisionsUseNormalizedKeysAndPreserveMemberOrder() {
        let duplicates = HotkeyCollision.duplicates([
            (id: "first", hotkey: "cmd+opt+P"),
            (id: "ignored-nil", hotkey: nil),
            (id: "invalid", hotkey: "nope"),
            (id: "second", hotkey: "opt+cmd+p"),
            (id: "other-key", hotkey: "shift+q"),
            (id: "third", hotkey: "OPT+CMD+P"),
            (id: "third", hotkey: "cmd+opt+p")
        ])

        XCTAssertEqual(duplicates, ["opt+cmd+p": ["first", "second", "third"]])
    }

    private func makeTemporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
