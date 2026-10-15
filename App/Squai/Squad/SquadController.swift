import AppKit
import SquaiCore

/// Owns one PetController per visible squad member and keeps them in sync with the member folders.
@MainActor
final class SquadController {
    static let cascadeStep: CGFloat = 110

    private let library: SquadLibrary
    private var pets: [String: PetController] = [:]
    private(set) var members: [SquadMember] = []
    var problems: [String: String] = [:]
    var onLeftClick: (SquadMember) -> Void = { NSLog("squai: left click on %@", $0.id) }
    var onRightClick: (SquadMember) -> Void = { NSLog("squai: right click on %@", $0.id) }

    init(library: SquadLibrary) {
        self.library = library
    }

    func pet(for id: String) -> PetController? { pets[id] }

    func reload() {
        let scan = library.scan()
        members = scan.members
        problems = scan.problems
        for (id, reason) in problems { NSLog("squai: member %@ skipped: %@", id, reason) }

        let visible = members.filter { $0.skill.visible }
        let visibleIDs = Set(visible.map(\.id))
        for (id, pet) in pets where !visibleIDs.contains(id) {
            pet.close()
            pets[id] = nil
        }

        // Pass 1: close changed pets, then collect every origin that is already claimed.
        for member in visible {
            if let existing = pets[member.id],
               existing.member.folder != member.folder || existing.member.pet != member.pet {
                existing.close()
                pets[member.id] = nil
            }
        }
        var occupied = pets.values.map { $0.panel.frame.origin }
        for member in visible {
            if pets[member.id] == nil, let saved = Preferences.origin(for: member.id) { occupied.append(saved) }
        }

        // Pass 2: create missing pets; unsaved members take the first free cascade slot.
        for member in visible where pets[member.id] == nil {
            let origin: NSPoint
            if let saved = Preferences.origin(for: member.id) {
                origin = saved
            } else {
                origin = Self.freeCascadeOrigin(avoiding: occupied)
                occupied.append(origin)
            }
            let pet = PetController(member: member, origin: origin)
            let id = member.id
            pet.onClick = { [weak self] in
                guard let self, let m = self.members.first(where: { $0.id == id }) else { return }
                self.onLeftClick(m)
            }
            pet.onRightClick = { [weak self] in
                guard let self, let m = self.members.first(where: { $0.id == id }) else { return }
                self.onRightClick(m)
            }
            pets[id] = pet
            pet.show()
        }
    }

    /// First cascade slot whose origin is not within 1 pt of any occupied origin.
    private static func freeCascadeOrigin(avoiding taken: [NSPoint]) -> NSPoint {
        var slot = 0
        while true {
            let o = cascadeOrigin(slot: slot)
            if !taken.contains(where: { abs($0.x - o.x) < 1 && abs($0.y - o.y) < 1 }) { return o }
            slot += 1
        }
    }

    private static func cascadeOrigin(slot: Int) -> NSPoint {
        var o = PetController.defaultOrigin()
        o.x -= cascadeStep * CGFloat(slot)
        return o
    }
}
