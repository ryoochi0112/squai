import Foundation

/// Codex-pet-compatible manifest (`pet.json`).
/// Field names and sprite layout follow the third-party Codex pet docs; see research notes.
public struct PetManifest: Codable, Equatable, Sendable {
    public var id: String
    public var displayName: String
    public var description: String
    public var spritesheetPath: String

    public init(id: String, displayName: String, description: String, spritesheetPath: String) {
        self.id = id
        self.displayName = displayName
        self.description = description
        self.spritesheetPath = spritesheetPath
    }

    public static func load(from folder: URL) throws -> PetManifest {
        let data = try Data(contentsOf: folder.appendingPathComponent("pet.json"))
        return try JSONDecoder().decode(PetManifest.self, from: data)
    }
}

/// A pet on disk: manifest + resolved atlas URL.
public struct InstalledPet: Equatable, Sendable {
    public var manifest: PetManifest
    public var folder: URL
    public var spritesheetURL: URL { folder.appendingPathComponent(manifest.spritesheetPath) }

    public init(manifest: PetManifest, folder: URL) {
        self.manifest = manifest
        self.folder = folder
    }
}

/// Scans pet folders. Order of `searchPaths` is precedence; first `id` wins.
public struct PetLibrary: Sendable {
    public var searchPaths: [URL]

    public init(searchPaths: [URL]) {
        self.searchPaths = searchPaths
    }

    public static var defaultSearchPaths: [URL] {
        let fm = FileManager.default
        let appSupport = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("squai/pets", isDirectory: true)
        let codex = fm.homeDirectoryForCurrentUser.appendingPathComponent(".codex/pets", isDirectory: true)
        return [appSupport, codex]
    }

    public func scan(fileManager fm: FileManager = .default) -> [InstalledPet] {
        var seen = Set<String>()
        var result: [InstalledPet] = []
        for root in searchPaths {
            guard let entries = try? fm.contentsOfDirectory(at: root, includingPropertiesForKeys: [.isDirectoryKey]) else { continue }
            for folder in entries.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
                guard (try? folder.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true,
                      let manifest = try? PetManifest.load(from: folder),
                      !seen.contains(manifest.id) else { continue }
                seen.insert(manifest.id)
                result.append(InstalledPet(manifest: manifest, folder: folder))
            }
        }
        return result
    }
}
