import XCTest
@testable import SquaiCore

private struct FakeBackend: TranslationBackend {
    var id: String
    func translate(_ text: String, direction: LanguageDirection) async throws -> TranslationResult {
        TranslationResult(text: "\(id):\(direction.source)->\(direction.target):\(text)", backend: id)
    }
}

final class SkillTests: XCTestCase {
    func testTranslateSkillUsesOnDeviceByDefault() async throws {
        let skill = TranslateSkill(onDevice: FakeBackend(id: "apple"), premium: FakeBackend(id: "claude"))
        let out = try await skill.run(SkillInput(text: " hello "))
        XCTAssertEqual(out.body, "apple:en->ja:hello")
        XCTAssertEqual(out.backend, "apple")
    }

    func testPremiumWhenRequested() async throws {
        let skill = TranslateSkill(onDevice: FakeBackend(id: "apple"), premium: FakeBackend(id: "claude"))
        let out = try await skill.run(SkillInput(text: "こんにちは", preferPremium: true))
        XCTAssertEqual(out.body, "claude:ja->en:こんにちは")
    }

    func testPremiumFallsBackWhenAbsent() async throws {
        let skill = TranslateSkill(onDevice: FakeBackend(id: "apple"))
        let out = try await skill.run(SkillInput(text: "x", preferPremium: true))
        XCTAssertEqual(out.backend, "apple")
    }

    func testRegistryKeepsOrderAndDedupes() {
        let r = SkillRegistry()
        r.register(TranslateSkill(onDevice: FakeBackend(id: "a")))
        r.register(TranslateSkill(onDevice: FakeBackend(id: "b")))
        XCTAssertEqual(r.all.count, 1)
        XCTAssertNotNil(r.skill(id: "translate.ja-en"))
    }
}
