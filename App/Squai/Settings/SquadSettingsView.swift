import SwiftUI
import SquaiCore

struct SquadSettingsView: View {
    @ObservedObject var store: MemberStore
    let onReload: () -> Void

    private enum Selection: Hashable {
        case new
        case member(String)
    }

    @State private var selection: Selection = .new

    var body: some View {
        HSplitView {
            VStack(alignment: .leading, spacing: 0) {
                List(selection: Binding(get: { Optional(selection) }, set: { if let v = $0 { selection = v } })) {
                    Label("New member", systemImage: "plus").tag(Selection.new)
                    Section("Members") {
                        ForEach(store.members, id: \.id) { m in
                            Text(m.skill.name).tag(Selection.member(m.id))
                        }
                    }
                    if !store.problems.isEmpty {
                        Section("Problems") {
                            ForEach(store.problems.keys.sorted(), id: \.self) { id in
                                Text("\(id): \(store.problems[id] ?? "")")
                                    .foregroundStyle(.red).font(.caption)
                            }
                        }
                    }
                }
            }
            .frame(minWidth: 170, idealWidth: 190, maxWidth: 240)

            Group {
                switch selection {
                case .new:
                    MemberEditorView(store: store, member: nil,
                                     onSaved: { selection = .member($0) },
                                     onDeleted: { selection = .new }, onReload: onReload)
                        .id("new")
                case .member(let id):
                    if let member = store.members.first(where: { $0.id == id }) {
                        MemberEditorView(store: store, member: member,
                                         onSaved: { _ in }, onDeleted: { selection = .new }, onReload: onReload)
                            .id(id)
                    } else {
                        Text("This member no longer exists.").foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
            }
            .frame(minWidth: 380)
        }
        .onAppear {
            store.refresh()
            if store.members.isEmpty { selection = .new }
        }
    }
}
