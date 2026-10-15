import Foundation

public struct SquadMember: Sendable {
    /// The containing folder's name, which is the member's stable id.
    public var id: String
    public var folder: URL
    public var skill: SkillFile
    public var pet: PetManifest

    public init(id: String, folder: URL, skill: SkillFile, pet: PetManifest) {
        self.id = id
        self.folder = folder
        self.skill = skill
        self.pet = pet
    }
}

public struct Look: Sendable {
    public enum Source: Sendable {
        case bundled
        case squai
        case codex
        case member
    }

    /// The containing folder's name, which is the look's id.
    public var id: String
    public var folder: URL
    public var pet: PetManifest
    public var source: Source

    public init(id: String, folder: URL, pet: PetManifest, source: Source) {
        self.id = id
        self.folder = folder
        self.pet = pet
        self.source = source
    }
}

public struct SquadLibrary: Sendable {
    public var memberRoot: URL
    public var lookRoots: [(URL, Look.Source)]

    public init(memberRoot: URL, lookRoots: [(URL, Look.Source)]) {
        self.memberRoot = memberRoot
        self.lookRoots = lookRoots
    }

    public func scan() -> (members: [SquadMember], looks: [Look], problems: [String: String]) {
        let fileManager = FileManager.default
        var members: [SquadMember] = []
        var looks: [Look] = []
        var problems: [String: String] = [:]

        for folder in subfolders(in: memberRoot, fileManager: fileManager) {
            let id = folder.lastPathComponent
            let petURL = folder.appendingPathComponent("pet.json")
            let skillURL = folder.appendingPathComponent("skill.json")
            guard fileManager.fileExists(atPath: petURL.path) else { continue }

            let pet: PetManifest
            do {
                pet = try PetManifest.load(from: folder)
            } catch {
                problems[id] = "pet.json invalid (\(error.localizedDescription))"
                continue
            }

            guard fileManager.fileExists(atPath: skillURL.path) else {
                looks.append(Look(id: id, folder: folder, pet: pet, source: .member))
                continue
            }

            do {
                let skill = try SkillFile.load(from: folder)
                members.append(SquadMember(id: id, folder: folder, skill: skill, pet: pet))
            } catch {
                problems[id] = "skill.json invalid (\(error.localizedDescription))"
            }
        }

        for (root, source) in lookRoots {
            for folder in subfolders(in: root, fileManager: fileManager) {
                let petURL = folder.appendingPathComponent("pet.json")
                guard fileManager.fileExists(atPath: petURL.path),
                      let pet = try? PetManifest.load(from: folder) else { continue }
                looks.append(Look(id: folder.lastPathComponent, folder: folder, pet: pet, source: source))
            }
        }

        members.sort { $0.id < $1.id }
        looks.sort {
            if $0.id != $1.id { return $0.id < $1.id }
            return $0.folder.path < $1.folder.path
        }
        return (members, looks, problems)
    }

    private func subfolders(in root: URL, fileManager: FileManager) -> [URL] {
        guard let folders = try? fileManager.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: []
        ) else { return [] }

        return folders.filter {
            (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
        }
    }
}

public enum PromptAssembler: Sendable {
    public static func assemble(prompt: String, selection: String) -> String {
        prompt + "\n\n" + selection
    }
}

public enum MemberID: Sendable {
    public static func make(name: String, existing: Set<String>) -> String {
        var slug = ""
        for byte in name.lowercased().utf8 {
            if (byte >= 97 && byte <= 122) || (byte >= 48 && byte <= 57) {
                slug.append(Character(UnicodeScalar(byte)))
            } else if !slug.isEmpty && slug.last != "-" {
                slug.append("-")
            }
        }

        while slug.last == "-" { slug.removeLast() }
        if slug.isEmpty { slug = "member" }
        guard existing.contains(slug) else { return slug }

        var suffix = 2
        while existing.contains("\(slug)-\(suffix)") { suffix += 1 }
        return "\(slug)-\(suffix)"
    }
}
