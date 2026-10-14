import Foundation

public struct TranslationResult: Equatable, Sendable {
    public var text: String
    /// Optional one-line nuance/register note (Claude only).
    public var note: String?
    public var backend: String

    public init(text: String, note: String? = nil, backend: String) {
        self.text = text
        self.note = note
        self.backend = backend
    }
}

public enum TranslationError: Error, Equatable {
    case languagePackMissing(source: String, target: String)
    case unsupported(source: String, target: String)
    case missingAPIKey
    case http(status: Int, body: String)
    case malformedResponse
    case empty
}

public protocol TranslationBackend: Sendable {
    var id: String { get }
    func translate(_ text: String, direction: LanguageDirection) async throws -> TranslationResult
}
