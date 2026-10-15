import Foundation
import CoreGraphics

/// Animation rows in Codex pet atlas order (row index == rawValue).
public enum PetState: Int, CaseIterable, Sendable {
    case idle = 0
    case runningLeft
    case runningRight
    case waving
    case jumping
    case failed
    case waiting
    case running
    case review

    public var rowName: String {
        switch self {
        case .idle: "idle"
        case .runningLeft: "running-left"
        case .runningRight: "running-right"
        case .waving: "waving"
        case .jumping: "jumping"
        case .failed: "failed"
        case .waiting: "waiting"
        case .running: "running"
        case .review: "review"
        }
    }
}

/// Geometry of the 8x9 atlas (1536x1872, 192x208 cells).
public struct SpriteSheetLayout: Equatable, Sendable {
    public var columns: Int
    public var rows: Int
    public var cellWidth: Int
    public var cellHeight: Int

    public static let codex = SpriteSheetLayout(columns: 8, rows: 9, cellWidth: 192, cellHeight: 208)

    public init(columns: Int, rows: Int, cellWidth: Int, cellHeight: Int) {
        self.columns = columns
        self.rows = rows
        self.cellWidth = cellWidth
        self.cellHeight = cellHeight
    }

    public var atlasWidth: Int { columns * cellWidth }
    public var atlasHeight: Int { rows * cellHeight }
    public var cellCount: Int { columns * rows }

    /// Cell rect in top-left-origin image coordinates (CGImage.cropping space).
    public func rect(row: Int, column: Int) -> CGRect {
        CGRect(x: column * cellWidth, y: row * cellHeight, width: cellWidth, height: cellHeight)
    }

    public func rects(for state: PetState) -> [CGRect] {
        (0..<columns).map { rect(row: state.rawValue, column: $0) }
    }
}

public enum SpriteSheetError: Error, Equatable {
    case sizeMismatch(expected: CGSize, actual: CGSize)
    case cropFailed(row: Int, column: Int)
}

/// Pre-sliced frames per state.
public struct SpriteSheet: Sendable {
    public var layout: SpriteSheetLayout
    public var frames: [PetState: [CGImage]]

    public init(atlas: CGImage, layout: SpriteSheetLayout = .codex) throws {
        let actual = CGSize(width: atlas.width, height: atlas.height)
        let expected = CGSize(width: layout.atlasWidth, height: layout.atlasHeight)
        guard actual == expected else { throw SpriteSheetError.sizeMismatch(expected: expected, actual: actual) }
        var frames: [PetState: [CGImage]] = [:]
        for state in PetState.allCases where state.rawValue < layout.rows {
            var row: [CGImage] = []
            for col in 0..<layout.columns {
                guard let img = atlas.cropping(to: layout.rect(row: state.rawValue, column: col)) else {
                    throw SpriteSheetError.cropFailed(row: state.rawValue, column: col)
                }
                row.append(img)
            }
            frames[state] = row
        }
        self.layout = layout
        self.frames = frames
    }

    public func frame(_ state: PetState, index: Int) -> CGImage? {
        guard let row = frames[state], !row.isEmpty else { return nil }
        return row[((index % row.count) + row.count) % row.count]
    }
}
