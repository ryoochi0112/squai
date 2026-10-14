import XCTest
@testable import SquaiCore

final class LanguageDetectorTests: XCTestCase {
    func testHiraganaIsJapanese() { XCTAssertEqual(LanguageDetector.detect("こんにちは"), .jaToEn) }
    func testKanjiIsJapanese() { XCTAssertEqual(LanguageDetector.detect("翻訳 test"), .jaToEn) }
    func testHalfWidthKatakana() { XCTAssertEqual(LanguageDetector.detect("ｶﾀｶﾅ"), .jaToEn) }
    func testLatinIsEnglish() { XCTAssertEqual(LanguageDetector.detect("hello, world"), .enToJa) }
    func testEmptyDefaultsToEnglish() { XCTAssertEqual(LanguageDetector.detect(""), .enToJa) }
    func testDirectionCodes() {
        XCTAssertEqual(LanguageDirection.jaToEn.source, "ja")
        XCTAssertEqual(LanguageDirection.enToJa.target, "ja")
    }
}
