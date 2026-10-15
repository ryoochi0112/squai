import Foundation
import XCTest
@testable import SquaiCore

final class SquadLibraryTests: XCTestCase {
    func testScanClassifiesFoldersReportsMalformedMembersAndDoesNotMutateRoots() throws {
        let temporaryRoot = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: temporaryRoot) }

        let memberRoot = temporaryRoot.appendingPathComponent("members", isDirectory: true)
        let codexRoot = temporaryRoot.appendingPathComponent("codex", isDirectory: true)
        try FileManager.default.createDirectory(at: memberRoot, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: codexRoot, withIntermediateDirectories: true)

        let fullMember = try makeFolder("z-full", under: memberRoot)
        try writePet(in: fullMember, id: "manifest-id")
        try SkillFile(name: "Translate", prompt: "Translate.", backend: .claude, hotkey: "opt+cmd+t", visible: true)
            .write(to: fullMember)

        let lookOnlyMember = try makeFolder("a-look-only", under: memberRoot)
        try writePet(in: lookOnlyMember, id: "look-manifest-id")

        let invalidSkillMember = try makeFolder("b-invalid-skill", under: memberRoot)
        try writePet(in: invalidSkillMember, id: "invalid-skill")
        try Data("{\"name\":\"Bad\",\"backend\":\"unknown\"}".utf8)
            .write(to: invalidSkillMember.appendingPathComponent("skill.json"))

        let invalidPetMember = try makeFolder("c-invalid-pet", under: memberRoot)
        try Data("{\"id\":false}".utf8).write(to: invalidPetMember.appendingPathComponent("pet.json"))

        let codexLook = try makeFolder("codex-look", under: codexRoot)
        try writePet(in: codexLook, id: "codex-look")
        // Look roots contribute looks only, so this malformed skill file is ignored.
        try Data("not json".utf8).write(to: codexLook.appendingPathComponent("skill.json"))

        let directories = [memberRoot, fullMember, lookOnlyMember, invalidSkillMember, invalidPetMember, codexRoot, codexLook]
        let before = try directorySnapshot(directories)
        let result = SquadLibrary(memberRoot: memberRoot, lookRoots: [(codexRoot, .codex)]).scan()
        let after = try directorySnapshot(directories)

        XCTAssertEqual(result.members.map(\.id), ["z-full"])
        XCTAssertEqual(result.members.first?.skill.name, "Translate")
        XCTAssertEqual(result.members.first?.pet.id, "manifest-id")
        XCTAssertEqual(result.looks.map(\.id), ["a-look-only", "codex-look"])
        XCTAssertEqual(result.looks.map(\.source), [.member, .codex])
        XCTAssertTrue(result.problems["b-invalid-skill"]?.contains("skill.json invalid (") == true)
        XCTAssertTrue(result.problems["c-invalid-pet"]?.contains("pet.json invalid (") == true)
        XCTAssertEqual(Set(result.problems.keys), ["b-invalid-skill", "c-invalid-pet"])
        XCTAssertEqual(after, before, "scan must not change directory contents or modification times")
    }

    func testMissingMemberAndLookRootsAreSkipped() throws {
        let temporaryRoot = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: temporaryRoot) }

        let result = SquadLibrary(
            memberRoot: temporaryRoot.appendingPathComponent("missing-members"),
            lookRoots: [(temporaryRoot.appendingPathComponent("missing-looks"), .bundled)]
        ).scan()

        XCTAssertTrue(result.members.isEmpty)
        XCTAssertTrue(result.looks.isEmpty)
        XCTAssertTrue(result.problems.isEmpty)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: temporaryRoot.path), [])
    }

    func testPromptAssemblyAndMemberIDs() {
        XCTAssertEqual(PromptAssembler.assemble(prompt: "P", selection: "S"), "P\n\nS")
        XCTAssertEqual(MemberID.make(name: "Hello, World!", existing: []), "hello-world")
        XCTAssertEqual(MemberID.make(name: "!!!", existing: []), "member")
        XCTAssertEqual(MemberID.make(name: "Hello, World!", existing: ["hello-world", "hello-world-2"]), "hello-world-3")
        XCTAssertEqual(MemberID.make(name: "Member", existing: ["member"]), "member-2")
    }

    private func makeTemporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func makeFolder(_ name: String, under root: URL) throws -> URL {
        let folder = root.appendingPathComponent(name, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    private func writePet(in folder: URL, id: String) throws {
        let pet = PetManifest(id: id, displayName: id, description: "Test pet", spritesheetPath: "spritesheet.png")
        try JSONEncoder().encode(pet).write(to: folder.appendingPathComponent("pet.json"))
    }

    private func directorySnapshot(_ directories: [URL]) throws -> [String: DirectoryState] {
        var snapshot: [String: DirectoryState] = [:]
        for directory in directories {
            let children = try FileManager.default.contentsOfDirectory(atPath: directory.path).sorted()
            let attributes = try FileManager.default.attributesOfItem(atPath: directory.path)
            snapshot[directory.path] = DirectoryState(
                modificationDate: attributes[.modificationDate] as? Date,
                children: children
            )
        }
        return snapshot
    }
}

private struct DirectoryState: Equatable {
    var modificationDate: Date?
    var children: [String]
}
