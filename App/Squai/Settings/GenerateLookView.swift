import SwiftUI
import SquaiCore

/// Description field + Generate button for the member form. Problems appear inline; there is no dialog.
struct GenerateLookView: View {
    @ObservedObject var generator: LookGenerator
    /// Called with the new look so the form can select it.
    let onGenerated: (Look) -> Void

    @State private var description = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Generate a look").font(.headline)
            TextField("Describe your pet, e.g. a sleepy orange cat", text: $description)
                .disabled(generator.state.isRunning)
            HStack {
                switch generator.state {
                case .running(let started):
                    TimelineView(.periodic(from: started, by: 1)) { context in
                        Text("Generating… (\(Self.clock(context.date.timeIntervalSince(started))))")
                            .monospacedDigit()
                    }
                    Button("Cancel") { generator.cancel() }
                default:
                    Button("Generate") { generator.start(description: description, onDone: onGenerated) }
                        .disabled(description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            switch generator.state {
            case .preflightFailed(let lines):
                ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                    Text(line).font(.callout).foregroundStyle(.red)
                }
            case .failed(let message):
                Text(message).font(.callout).foregroundStyle(.red)
            case .done(let look):
                Text("Added look “\(look.pet.displayName)”.").font(.callout).foregroundStyle(.secondary)
            default:
                EmptyView()
            }
        }
    }

    static func clock(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds))
        return String(format: "%02d:%02d", total / 60, total % 60)
    }
}
