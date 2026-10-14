import Foundation

public struct SkillInput: Sendable {
    public var text: String
    /// Set by the UI when the user explicitly asks for the premium backend.
    public var preferPremium: Bool

    public init(text: String, preferPremium: Bool = false) {
        self.text = text
        self.preferPremium = preferPremium
    }
}

public struct SkillOutput: Equatable, Sendable {
    public var body: String
    public var note: String?
    public var backend: String
    public var state: PetState

    public init(body: String, note: String? = nil, backend: String, state: PetState = .review) {
        self.body = body
        self.note = note
        self.backend = backend
        self.state = state
    }
}

/// One capability a pet can perform. v1 ships `TranslateSkill` only.
public protocol PetSkill: Sendable {
    var id: String { get }
    var displayName: String { get }
    func run(_ input: SkillInput) async throws -> SkillOutput
}

public final class SkillRegistry: @unchecked Sendable {
    private var skills: [String: any PetSkill] = [:]
    private var order: [String] = []
    private let lock = NSLock()

    public init() {}

    public func register(_ skill: any PetSkill) {
        lock.lock(); defer { lock.unlock() }
        if skills[skill.id] == nil { order.append(skill.id) }
        skills[skill.id] = skill
    }

    public func skill(id: String) -> (any PetSkill)? {
        lock.lock(); defer { lock.unlock() }
        return skills[id]
    }

    public var all: [any PetSkill] {
        lock.lock(); defer { lock.unlock() }
        return order.compactMap { skills[$0] }
    }
}

/// JPN<->EN translation using an on-device default and an optional premium backend.
public struct TranslateSkill: PetSkill {
    public let id = "translate.ja-en"
    public let displayName = "Translate JA ⇄ EN"
    public var onDevice: any TranslationBackend
    public var premium: (any TranslationBackend)?

    public init(onDevice: any TranslationBackend, premium: (any TranslationBackend)? = nil) {
        self.onDevice = onDevice
        self.premium = premium
    }

    public func run(_ input: SkillInput) async throws -> SkillOutput {
        let text = input.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { throw TranslationError.empty }
        let direction = LanguageDetector.detect(text)
        let backend: any TranslationBackend = (input.preferPremium ? premium : nil) ?? onDevice
        let t = try await backend.translate(text, direction: direction)
        return SkillOutput(body: t.text, note: t.note, backend: t.backend)
    }
}
