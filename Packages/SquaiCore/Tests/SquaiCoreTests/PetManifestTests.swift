import XCTest
@testable import SquaiCore

final class PetManifestTests: XCTestCase {
    func testDecodesCodexShape() throws {
        let json = """
        {"id":"blob","displayName":"Blob","description":"A blob.","spritesheetPath":"blob.png"}
        """
        let m = try JSONDecoder().decode(PetManifest.self, from: Data(json.utf8))
        XCTAssertEqual(m, PetManifest(id: "blob", displayName: "Blob", description: "A blob.", spritesheetPath: "blob.png"))
    }

    func testLibraryScansFoldersWithPrecedence() throws {
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let a = tmp.appendingPathComponent("a"), b = tmp.appendingPathComponent("b")
        for (root, name) in [(a, "First"), (b, "Second")] {
            let pet = root.appendingPathComponent("blob")
            try FileManager.default.createDirectory(at: pet, withIntermediateDirectories: true)
            let m = PetManifest(id: "blob", displayName: name, description: "", spritesheetPath: "s.png")
            try JSONEncoder().encode(m).write(to: pet.appendingPathComponent("pet.json"))
        }
        try FileManager.default.createDirectory(at: b.appendingPathComponent("junk"), withIntermediateDirectories: true)
        let pets = PetLibrary(searchPaths: [a, b]).scan()
        XCTAssertEqual(pets.map(\.manifest.displayName), ["First"])
        XCTAssertEqual(pets[0].spritesheetURL.lastPathComponent, "s.png")
    }
}
