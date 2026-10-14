import Foundation
import SquaiCore

enum MemberStoreError: LocalizedError {
    case emptyName
    case emptyPrompt
    case invalidHotkey(String)
    case hotkeyNeedsModifier
    case duplicateHotkey(String, owner: String)
    case hiddenWithoutHotkey
    case memberNotFound
    case unsafeFolder
    case copyFailed(String)

    var errorDescription: String? {
        switch self {
        case .emptyName: "Name is required"
        case .emptyPrompt: "Prompt is required"
        case .invalidHotkey(let s): "Hotkey \"\(s)\" is not supported"
        case .hotkeyNeedsModifier: "Add a modifier key (⌃⌥⇧⌘)"
        case .duplicateHotkey(_, let owner): "That hotkey is already used by \(owner)"
        case .hiddenWithoutHotkey: "Hidden members need a hotkey"
        case .memberNotFound: "This member no longer exists. Reload the squad."
        case .unsafeFolder: "Refusing to touch a folder outside the squad folder"
        case .copyFailed(let m): "Could not create the member: \(m)"
        }
    }
}

/// Creates, updates and deletes member folders under `memberRoot`, and nothing else.
/// Every write targets `memberRoot/<id>/`; look folders are only ever read.
@MainActor
final class MemberStore: ObservableObject {
    @Published private(set) var members: [SquadMember] = []
    @Published private(set) var looks: [Look] = []
    @Published private(set) var problems: [String: String] = [:]

    private let library: SquadLibrary
    private let squad: SquadController
    /// Called after every write so the pet and hotkeys follow within a second.
    /// AppDelegate points this at `reloadSquad()`, which also reloads the SquadController.
    var onChange: () -> Void
    /// Re-applies every member's saved hotkey to KeyboardShortcuts. The editor calls it after any
    /// change to its draft recorder, because setShortcut registers/unregisters combinations globally.
    var resyncHotkeys: () -> Void = {}

    init(library: SquadLibrary, squad: SquadController) {
        self.library = library
        self.squad = squad
        self.onChange = { squad.reload() }
    }

    /// Re-reads members/problems from the controller and looks from disk.
    func refresh() {
        members = squad.members
        problems = squad.problems
        looks = library.scan().looks.filter { $0.source != .member }
    }

    /// Checks a candidate skill. `excluding` is the id of the member being edited, if any.
    /// Returns the skill with name trimmed and hotkey normalized.
    func validate(_ skill: SkillFile, excluding id: String?) throws -> SkillFile {
        var skill = skill
        skill.name = skill.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !skill.name.isEmpty else { throw MemberStoreError.emptyName }
        guard !skill.prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw MemberStoreError.emptyPrompt
        }
        if let raw = skill.hotkey, !raw.isEmpty {
            guard let spec = HotkeySpec(raw) else { throw MemberStoreError.invalidHotkey(raw) }
            guard !spec.modifiers.isEmpty else { throw MemberStoreError.hotkeyNeedsModifier }
            skill.hotkey = spec.normalized
            for other in squad.members where other.id != id {
                if let h = other.skill.hotkey, HotkeySpec(h)?.normalized == spec.normalized {
                    throw MemberStoreError.duplicateHotkey(spec.normalized, owner: other.skill.name)
                }
            }
        } else {
            skill.hotkey = nil
        }
        if !skill.visible && skill.hotkey == nil { throw MemberStoreError.hiddenWithoutHotkey }
        return skill
    }

    @discardableResult
    func create(name: String, prompt: String, backend: Backend, look: Look,
                hotkey: String?, visible: Bool) throws -> SquadMember {
        let skill = try validate(SkillFile(name: name, prompt: prompt, backend: backend,
                                           hotkey: hotkey, visible: visible), excluding: nil)
        let fm = FileManager.default
        try fm.createDirectory(at: library.memberRoot, withIntermediateDirectories: true)
        // Take every folder name on disk, not just loaded members, so a look-only or broken folder is never overwritten.
        let taken = Set((try? fm.contentsOfDirectory(atPath: library.memberRoot.path)) ?? [])
        let id = MemberID.make(name: skill.name, existing: taken)
        let dest = library.memberRoot.appendingPathComponent(id, isDirectory: true)
        do {
            _ = try verifiedFolder(dest, id: id)
            try fm.copyItem(at: look.folder, to: dest)
            _ = try verifiedFolder(dest, id: id)
            try Self.rewritePetID(in: dest, to: id)
            _ = try verifiedFolder(dest, id: id)
            try skill.write(to: dest)
        } catch {
            try? fm.removeItem(at: dest) // dest is a folder this call just created under memberRoot
            throw MemberStoreError.copyFailed(error.localizedDescription)
        }
        onChange()
        refresh()
        guard let member = squad.members.first(where: { $0.id == id }) else {
            throw MemberStoreError.copyFailed("the new member did not load")
        }
        return member
    }

    func update(_ member: SquadMember, skill: SkillFile) throws {
        let validated = try validate(skill, excluding: member.id)
        // Resolve by id now: the passed member may be stale after a reload.
        guard let current = squad.members.first(where: { $0.id == member.id }) else {
            throw MemberStoreError.memberNotFound
        }
        let folder = try ownedFolder(of: current)
        try validated.write(to: folder)
        onChange()
        refresh()
    }

    func delete(_ member: SquadMember) throws {
        guard let current = squad.members.first(where: { $0.id == member.id }) else {
            throw MemberStoreError.memberNotFound
        }
        let folder = try ownedFolder(of: current)
        try FileManager.default.trashItem(at: folder, resultingItemURL: nil)
        // A later member may reuse this id; do not let it inherit the old position.
        UserDefaults.standard.removeObject(forKey: "petOrigin.\(member.id)")
        onChange()
        refresh()
    }

    /// The member's folder, only if it is a real (non-symlink) direct child of the member root named after its id.
    private func ownedFolder(of member: SquadMember) throws -> URL {
        try verifiedFolder(member.folder, id: member.id)
    }

    /// Call immediately before every write or trash. Rejects a folder that is itself a symlink, then checks that
    /// the symlink-resolved folder sits directly under the symlink-resolved member root and is named `id`.
    /// A missing folder (create's destination) is allowed; its parent is still checked.
    private func verifiedFolder(_ url: URL, id: String) throws -> URL {
        let folder = url.standardizedFileURL
        if (try? folder.resourceValues(forKeys: [.isSymbolicLinkKey]))?.isSymbolicLink == true {
            throw MemberStoreError.unsafeFolder
        }
        if let type = (try? FileManager.default.attributesOfItem(atPath: folder.path))?[.type] as? FileAttributeType,
           type == .typeSymbolicLink {
            throw MemberStoreError.unsafeFolder
        }
        let root = library.memberRoot.standardizedFileURL.resolvingSymlinksInPath()
        let resolved = folder.resolvingSymlinksInPath()
        guard resolved.deletingLastPathComponent().path == root.path,
              resolved.lastPathComponent == id,
              folder.lastPathComponent == id else { throw MemberStoreError.unsafeFolder }
        return folder
    }

    /// Sets `id` in pet.json, keeping every other key as-is.
    private static func rewritePetID(in folder: URL, to id: String) throws {
        let url = folder.appendingPathComponent("pet.json")
        let data = try Data(contentsOf: url)
        guard var json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw CocoaError(.fileReadCorruptFile)
        }
        json["id"] = id
        let out = try JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted, .sortedKeys])
        try out.write(to: url, options: .atomic)
    }
}
