import SwiftUI
import AppKit
import SquaiCore

/// Loads a look's sprite sheet from disk (read-only).
@MainActor
enum LookSheets {
    private static var cache: [String: SpriteSheet] = [:]

    static func sheet(for look: Look) -> SpriteSheet? {
        let url = look.folder.appendingPathComponent(look.pet.spritesheetPath)
        if let hit = cache[url.path] { return hit }
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil),
              let atlas = CGImageSourceCreateImageAtIndex(src, 0, nil),
              let sheet = try? SpriteSheet(atlas: atlas) else { return nil }
        cache[url.path] = sheet
        return sheet
    }
}

private func pixelImage(_ cg: CGImage) -> some View {
    Image(decorative: cg, scale: 1).interpolation(.none).resizable().scaledToFit()
}

/// Grid of looks (bundled / squai / codex) with an idle thumbnail, plus a row preview.
struct LookPickerView: View {
    let looks: [Look]
    @Binding var selectedID: String?
    @State private var previewRow: PetState = .idle

    private var selected: Look? { looks.first { Self.key($0) == selectedID } }

    static func key(_ look: Look) -> String { look.folder.path }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if looks.isEmpty {
                Text("No looks found.").foregroundStyle(.secondary)
            } else {
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 72), spacing: 8)], spacing: 8) {
                        ForEach(looks, id: \.folder) { look in
                            LookCell(look: look, isSelected: Self.key(look) == selectedID)
                                .onTapGesture { selectedID = Self.key(look) }
                        }
                    }
                    .padding(4)
                }
                .frame(height: 150)
            }
            if let selected {
                HStack(alignment: .top, spacing: 12) {
                    LookAnimation(look: selected, row: previewRow)
                        .frame(width: 72, height: 78)
                    VStack(alignment: .leading) {
                        Picker("Preview rows", selection: $previewRow) {
                            ForEach(PetState.allCases, id: \.self) { Text($0.rowName).tag($0) }
                        }
                        Text("\(selected.pet.displayName) · \(Self.sourceName(selected.source))")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    static func sourceName(_ s: Look.Source) -> String {
        switch s {
        case .bundled: "bundled"
        case .squai: "generated"
        case .codex: "codex"
        case .member: "member"
        }
    }
}

private struct LookCell: View {
    let look: Look
    let isSelected: Bool

    var body: some View {
        VStack(spacing: 2) {
            Group {
                if let cg = LookSheets.sheet(for: look)?.frame(.idle, index: 0) {
                    pixelImage(cg)
                } else {
                    Image(systemName: "exclamationmark.triangle").foregroundStyle(.secondary)
                }
            }
            .frame(width: 56, height: 60)
            Text(look.pet.displayName).font(.caption2).lineLimit(1)
        }
        .padding(4)
        .frame(width: 72)
        .background(RoundedRectangle(cornerRadius: 6)
            .fill(isSelected ? Color.accentColor.opacity(0.25) : Color.clear))
        .overlay(RoundedRectangle(cornerRadius: 6)
            .stroke(isSelected ? Color.accentColor : Color.secondary.opacity(0.3)))
        .contentShape(Rectangle())
    }
}

private struct LookAnimation: View {
    let look: Look
    let row: PetState

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1.0 / 8.0)) { context in
            let index = Int(context.date.timeIntervalSinceReferenceDate * 8)
            if let cg = LookSheets.sheet(for: look)?.frame(row, index: index) {
                pixelImage(cg)
            } else {
                Image(systemName: "exclamationmark.triangle").foregroundStyle(.secondary)
            }
        }
    }
}
