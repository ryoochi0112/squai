import Foundation
import CoreGraphics
import ImageIO

public enum SheetProblem: Error, Equatable {
    case wrongSize(width: Int, height: Int)
    case emptyRow(name: String)
    case unreadable
}

public enum SpriteSheetValidator {
    public static func validate(_ image: CGImage) -> Result<Void, SheetProblem> {
        let layout = SpriteSheetLayout.codex
        guard image.width == layout.atlasWidth, image.height == layout.atlasHeight else {
            return .failure(.wrongSize(width: image.width, height: image.height))
        }

        for state in PetState.allCases where state.rawValue < layout.rows {
            let rowRect = CGRect(x: 0, y: state.rawValue * layout.cellHeight,
                                 width: layout.atlasWidth, height: layout.cellHeight)
            guard let rowImage = image.cropping(to: rowRect),
                  let hasVisiblePixel = containsVisiblePixel(in: rowImage) else {
                return .failure(.unreadable)
            }
            guard hasVisiblePixel else {
                return .failure(.emptyRow(name: state.rowName))
            }
        }

        return .success(())
    }

    public static func validate(fileAt url: URL) -> Result<Void, SheetProblem> {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            return .failure(.unreadable)
        }
        return validate(image)
    }

    private static func containsVisiblePixel(in image: CGImage) -> Bool? {
        let width = image.width
        let height = image.height
        let bytesPerRow = width * 4
        var pixels = [UInt8](repeating: 0, count: bytesPerRow * height)
        let bitmapInfo = CGBitmapInfo.byteOrder32Big.rawValue
            | CGImageAlphaInfo.premultipliedLast.rawValue

        return pixels.withUnsafeMutableBytes { buffer in
            guard let context = CGContext(data: buffer.baseAddress,
                                          width: width,
                                          height: height,
                                          bitsPerComponent: 8,
                                          bytesPerRow: bytesPerRow,
                                          space: CGColorSpaceCreateDeviceRGB(),
                                          bitmapInfo: bitmapInfo) else {
                return nil
            }
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return stride(from: 3, to: buffer.count, by: 4).contains { buffer[$0] > 0 }
        }
    }
}
