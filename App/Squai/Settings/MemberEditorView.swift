import SwiftUI
import AppKit
import Carbon.HIToolbox
import KeyboardShortcuts
import SquaiCore

extension KeyboardShortcuts.Name {
    /// Draft-only: nothing ever registers a handler for it, so recording cannot fire a member.
    static let memberDraft = Self("squai.memberDraft")
}

/// Create form (member == nil) or edit form for one member.
struct MemberEditorView: View {
    @ObservedObject var store: MemberStore
    /// nil = create a new member.
    let member: SquadMember?
    let onSaved: (String) -> Void
    let onDeleted: () -> Void
    let onReload: () -> Void

    @State private var name = ""
    @State private var prompt = ""
    @State private var backend: Backend = .claude
    @State private var lookKey: String?
    @State private var visible = true
    @State private var hotkey: String?
    @State private var hotkeyRejected = false
    @State private var errorText: String?
    @State private var confirmDelete = false
    /// Bumped to rebuild the Recorder when the draft is set or cleared programmatically.
    @State private var recorderEpoch = 0

    var body: some View {
        Form {
            TextField("Name", text: $name)
            VStack(alignment: .leading) {
                Text("Prompt")
                TextEditor(text: $prompt)
                    .font(.body)
                    .frame(height: 90)
                    .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.secondary.opacity(0.3)))
            }
            Picker("Backend", selection: $backend) {
                Text("Claude").tag(Backend.claude)
                Text("ChatGPT").tag(Backend.chatgpt)
            }
            if member == nil {
                LookPickerView(looks: store.looks, selectedID: $lookKey)
            } else if let member {
                Text("Look: \(member.pet.displayName)").foregroundStyle(.secondary)
            }
            LabeledContent("Hotkey") {
                VStack(alignment: .trailing) {
                    HStack {
                        Text(hotkey.map { "Saved: \($0)" } ?? "No hotkey").foregroundStyle(.secondary)
                        if hotkey != nil {
                            Button("Clear") { hotkey = nil; hotkeyRejected = false; errorText = nil }
                                .buttonStyle(.link)
                        }
                    }
                    // Records a new combination only; it starts empty so it never mirrors a live hotkey.
                    KeyboardShortcuts.Recorder(for: .memberDraft, onChange: recorded)
                        .id(recorderEpoch)
                    Text("e.g. ⌥⌘1").font(.caption).foregroundStyle(.secondary)
                }
            }
            Toggle("Show pet on screen", isOn: $visible)
            if let message = liveError ?? errorText {
                Text(message).foregroundStyle(.red).font(.callout)
            }
            HStack {
                Button(member == nil ? "Create" : "Save", action: save)
                    .keyboardShortcut(.defaultAction)
                    .disabled(liveError != nil)
                if let member {
                    Button("Delete…", role: .destructive) { confirmDelete = true }
                        .confirmationDialog("Move \(member.skill.name) to the Trash?",
                                            isPresented: $confirmDelete) {
                            Button("Move to Trash", role: .destructive) { delete(member) }
                        }
                }
                Spacer()
                Button("Reload", action: onReload)
            }
        }
        .formStyle(.grouped)
        .onAppear(perform: loadDraft)
        .onChange(of: member?.id) { _, _ in loadDraft() }
        // Reload (or any rewrite of skill.json) must re-seed the form, or Save would overwrite the disk change.
        .onChange(of: member?.skill) { _, _ in loadDraft() }
        .onDisappear(perform: clearDraftShortcut)
    }

    // MARK: Validation

    private var candidate: SkillFile {
        SkillFile(name: name, prompt: prompt, backend: backend, hotkey: hotkey, visible: visible)
    }

    /// Duplicate-hotkey and hidden-without-hotkey are shown as soon as they apply (AC5).
    private var liveError: String? {
        if let hotkey, HotkeySpec(hotkey)?.modifiers.isEmpty == true { return MemberStoreError.hotkeyNeedsModifier.localizedDescription }
        if hotkeyRejected { return "That key combination is not supported. Use a letter, digit, space or F1–F12 with modifiers." }
        guard hotkey != nil || !visible else { return nil }
        do { _ = try store.validate(candidate, excluding: member?.id) } catch MemberStoreError.emptyName, MemberStoreError.emptyPrompt {
            return nil
        } catch { return error.localizedDescription }
        return nil
    }

    // MARK: Actions

    private func loadDraft() {
        errorText = nil
        hotkeyRejected = false
        confirmDelete = false
        if let member {
            name = member.skill.name
            prompt = member.skill.prompt
            backend = member.skill.backend
            visible = member.skill.visible
            hotkey = member.skill.hotkey
        } else {
            name = ""; prompt = ""; backend = .claude; visible = true; hotkey = nil
            lookKey = store.looks.first(where: { $0.source == .bundled }).map(LookPickerView.key)
                ?? store.looks.first.map(LookPickerView.key)
        }
        // Never seed the draft with the saved combo: setShortcut registers/unregisters that combination
        // globally and would disable the member's live hotkey. Start the draft empty instead.
        resetDraftShortcut()
    }

    private func resetDraftShortcut() {
        KeyboardShortcuts.setShortcut(nil, for: .memberDraft)
        recorderEpoch += 1
        store.resyncHotkeys()
    }

    private func clearDraftShortcut() {
        KeyboardShortcuts.setShortcut(nil, for: .memberDraft)
        store.resyncHotkeys()
    }

    private func recorded(_ shortcut: KeyboardShortcuts.Shortcut?) {
        errorText = nil
        defer { store.resyncHotkeys() } // the draft may share a combination with a live member
        guard let shortcut else { return } // clearing the draft leaves the saved hotkey; use Clear for that
        if let spec = Self.spec(for: shortcut) {
            hotkey = spec.normalized
            hotkeyRejected = false
        } else {
            hotkey = nil
            hotkeyRejected = true
        }
    }

    private func save() {
        errorText = nil
        do {
            let skill = candidate
            if let member {
                try store.update(member, skill: skill)
                onSaved(member.id)
            } else {
                guard let look = store.looks.first(where: { LookPickerView.key($0) == lookKey }) else {
                    errorText = "Choose a look"
                    return
                }
                let created = try store.create(name: skill.name, prompt: skill.prompt, backend: skill.backend,
                                               look: look, hotkey: skill.hotkey, visible: skill.visible)
                onSaved(created.id)
            }
        } catch {
            errorText = error.localizedDescription
        }
    }

    private func delete(_ member: SquadMember) {
        do {
            try store.delete(member)
            onDeleted()
        } catch {
            errorText = error.localizedDescription
        }
    }

    /// Inverse of `HotkeyRegistry.shortcut(for:)`; nil when the registry could not map it back.
    static func spec(for shortcut: KeyboardShortcuts.Shortcut) -> HotkeySpec? {
        let flags = shortcut.modifiers
        var parts: [String] = []
        if flags.contains(.control) { parts.append("ctrl") }
        if flags.contains(.option) { parts.append("opt") }
        if flags.contains(.shift) { parts.append("shift") }
        if flags.contains(.command) { parts.append("cmd") }
        let keys = (Array("abcdefghijklmnopqrstuvwxyz0123456789").map(String.init)
                    + ["space"] + (1...12).map { "f\($0)" })
        for key in keys {
            guard let candidate = HotkeySpec((parts + [key]).joined(separator: "+")),
                  let mapped = HotkeyRegistry.shortcut(for: candidate),
                  mapped.carbonKeyCode == shortcut.carbonKeyCode else { continue }
            return candidate
        }
        return nil
    }
}
