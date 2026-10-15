import Foundation

public enum Backend: String, Codable, Sendable {
    case claude
    case chatgpt
}

/// The user-authored prompt and invocation settings stored in `skill.json`.
public struct SkillFile: Codable, Equatable, Sendable {
    public var name: String
    public var prompt: String
    public var backend: Backend
    public var hotkey: String?
    public var visible: Bool

    public init(name: String, prompt: String, backend: Backend, hotkey: String?, visible: Bool) {
        self.name = name
        self.prompt = prompt
        self.backend = backend
        self.hotkey = hotkey
        self.visible = visible
    }

    public static func load(from folder: URL) throws -> SkillFile {
        let data = try Data(contentsOf: folder.appendingPathComponent("skill.json"))
        return try JSONDecoder().decode(SkillFile.self, from: data)
    }

    public func write(to folder: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(self)
        try data.write(to: folder.appendingPathComponent("skill.json"), options: .atomic)
    }
}
