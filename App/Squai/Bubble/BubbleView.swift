import SwiftUI
import SquaiCore

enum BubbleContent {
    case result(SkillOutput, source: String)
    case languagePackMissing(source: String, target: String)
    case error(String)
}

struct BubbleView: View {
    let content: BubbleContent
    let onCopy: (String) -> Void
    let onAskClaude: (String) -> Void
    let onDownloadPack: () -> Void
    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            switch content {
            case .result(let out, let source):
                Text(out.body).font(.body).textSelection(.enabled)
                if let note = out.note {
                    Text(note).font(.caption).foregroundStyle(.secondary)
                }
                HStack {
                    Text(out.backend == "claude" ? "Claude Haiku" : "On-device").font(.caption2).foregroundStyle(.tertiary)
                    Spacer()
                    Button("Copy") { onCopy(out.body) }
                    if out.backend != "claude" {
                        Button("Ask Claude") { onAskClaude(source) }
                    }
                }
            case .languagePackMissing(let s, let t):
                Text("The \(s)→\(t) language pack is not installed.")
                HStack { Spacer(); Button("Download \(s)/\(t)") { onDownloadPack() } }
            case .error(let msg):
                Text("Something went wrong").font(.headline)
                Text(msg).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
            }
        }
        .padding(12)
        .frame(width: 300, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        .overlay(alignment: .topTrailing) {
            Button(action: onClose) { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) }
                .buttonStyle(.plain).padding(6)
        }
    }
}
