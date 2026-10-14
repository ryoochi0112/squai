import XCTest
import CoreGraphics
@testable import SquaiCore

final class SpriteSheetTests: XCTestCase {
    private func blankAtlas(width: Int, height: Int) -> CGImage {
        let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        return ctx.makeImage()!
    }

    func testCodexLayoutGeometry() {
        let l = SpriteSheetLayout.codex
        XCTAssertEqual(l.atlasWidth, 1536)
        XCTAssertEqual(l.atlasHeight, 1872)
        XCTAssertEqual(l.cellCount, 72)
        XCTAssertEqual(l.rect(row: 8, column: 7), CGRect(x: 1344, y: 1664, width: 192, height: 208))
        XCTAssertEqual(l.rects(for: .review).count, 8)
    }

    func testSlicesSeventyTwoCells() throws {
        let sheet = try SpriteSheet(atlas: blankAtlas(width: 1536, height: 1872))
        XCTAssertEqual(sheet.frames.values.reduce(0) { $0 + $1.count }, 72)
        XCTAssertEqual(sheet.frame(.idle, index: 9)?.width, 192)
        XCTAssertEqual(sheet.frame(.jumping, index: -1)?.height, 208)
    }

    func testRejectsWrongSize() {
        XCTAssertThrowsError(try SpriteSheet(atlas: blankAtlas(width: 100, height: 100))) { error in
            guard case SpriteSheetError.sizeMismatch = error else { return XCTFail("\(error)") }
        }
    }
}
