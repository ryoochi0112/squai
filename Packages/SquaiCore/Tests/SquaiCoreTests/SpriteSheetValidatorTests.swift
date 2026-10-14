import XCTest
import CoreGraphics
import ImageIO
@testable import SquaiCore

final class SpriteSheetValidatorTests: XCTestCase {
    func testAcceptsAtlasWithOneOpaquePixelInEachRow() {
        let image = atlas(transparentRow: nil)

        assertSuccess(SpriteSheetValidator.validate(image))
    }

    func testFileAtAcceptsPNGWithOneOpaquePixelInEachRow() throws {
        let image = atlas(transparentRow: nil)
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("squai-sheet-validator-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let url = directory.appendingPathComponent("valid.png")
        let destination = try XCTUnwrap(CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, nil)
        XCTAssertTrue(CGImageDestinationFinalize(destination))

        assertSuccess(SpriteSheetValidator.validate(fileAt: url))
    }

    func testRejectsWrongSizeWithActualDimensions() {
        let image = blankImage(width: 1536, height: 1024)

        assertFailure(SpriteSheetValidator.validate(image), equals: .wrongSize(width: 1536, height: 1024))
    }

    func testRejectsFirstEmptyRowByName() {
        let image = atlas(transparentRow: 5)

        assertFailure(SpriteSheetValidator.validate(image), equals: .emptyRow(name: "failed"))
    }

    func testUnreadableFileReturnsUnreadable() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("squai-sheet-validator-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let url = directory.appendingPathComponent("not-an-image.png")
        try Data("not a PNG".utf8).write(to: url)

        assertFailure(SpriteSheetValidator.validate(fileAt: url), equals: .unreadable)
    }

    func testPetStateRowNamesMatchAtlasContract() {
        XCTAssertEqual(PetState.allCases.map(\.rowName), [
            "idle", "running-left", "running-right", "waving", "jumping",
            "failed", "waiting", "running", "review"
        ])
    }

    private func atlas(transparentRow: Int?) -> CGImage {
        let layout = SpriteSheetLayout.codex
        let context = CGContext(data: nil,
                                width: layout.atlasWidth,
                                height: layout.atlasHeight,
                                bitsPerComponent: 8,
                                bytesPerRow: 0,
                                space: CGColorSpaceCreateDeviceRGB(),
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.clear(CGRect(x: 0, y: 0, width: layout.atlasWidth, height: layout.atlasHeight))
        context.translateBy(x: 0, y: CGFloat(layout.atlasHeight))
        context.scaleBy(x: 1, y: -1)
        context.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
        for row in 0..<layout.rows where row != transparentRow {
            context.fill(CGRect(x: 10, y: row * layout.cellHeight, width: 1, height: 1))
        }
        return context.makeImage()!
    }

    private func blankImage(width: Int, height: Int) -> CGImage {
        let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpaceCreateDeviceRGB(),
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        return context.makeImage()!
    }

    private func assertSuccess(_ result: Result<Void, SheetProblem>, file: StaticString = #filePath,
                               line: UInt = #line) {
        guard case .success = result else {
            return XCTFail("Expected validation success, got \(result)", file: file, line: line)
        }
    }

    private func assertFailure(_ result: Result<Void, SheetProblem>, equals expected: SheetProblem,
                               file: StaticString = #filePath, line: UInt = #line) {
        guard case .failure(let actual) = result else {
            return XCTFail("Expected validation failure \(expected), got success", file: file, line: line)
        }
        XCTAssertEqual(actual, expected, file: file, line: line)
    }
}
