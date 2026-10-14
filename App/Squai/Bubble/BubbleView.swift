import SwiftUI
import SquaiCore

enum BubbleContent {
    case result(String)
    case info(String)
    case notSetUp(backendName: String)
    case error(String)
}

struct BubbleView: View {
    let content: BubbleContent
    let onCopy: (String) -> Void
    let onReplace: (String) -> Void
    let onOpenSettings: () -> Void
    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            switch content {
            case .result(let body):
                Text(body).font(.body).textSelection(.enabled)
                HStack {
                    Spacer()
                    Button("Copy") { onCopy(body) }
                    Button("Replace") { onReplace(body) }
                }
            case .info(let msg):
                Text(msg).font(.body)
            case .notSetUp(let name):
                Text("\(name) is not set up").font(.headline)
                HStack { Spacer(); Button("Open Settings") { onOpenSettings() } }
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
