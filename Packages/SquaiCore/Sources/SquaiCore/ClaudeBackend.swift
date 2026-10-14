import Foundation

/// Messages API codec (request/response shapes), kept separate from transport for testing.
public enum ClaudeAPI {
    public static let endpoint = URL(string: "https://api.anthropic.com/v1/messages")!
    public static let version = "2023-06-01"
    public static let defaultModel = "claude-haiku-5-5"

    public struct Request: Codable, Equatable, Sendable {
        public struct Message: Codable, Equatable, Sendable {
            public var role: String
            public var content: String
        }
        public struct OutputConfig: Codable, Equatable, Sendable {
            public var effort: String
        }
        public var model: String
        public var max_tokens: Int
        public var system: String
        public var messages: [Message]
        public var output_config: OutputConfig?
    }

    public struct Response: Codable, Sendable {
        public struct ContentBlock: Codable, Sendable {
            public var type: String
            public var text: String?
        }
        public struct Usage: Codable, Sendable {
            public var input_tokens: Int?
            public var output_tokens: Int?
            public var cache_read_input_tokens: Int?
            public var cache_creation_input_tokens: Int?
        }
        public var content: [ContentBlock]
        public var stop_reason: String?
        public var usage: Usage?

        /// Concatenated text blocks only; thinking/tool blocks are skipped.
        public var text: String {
            content.filter { $0.type == "text" }.compactMap(\.text).joined()
        }
    }

    /// Structured output we ask the model for (parsed leniently from the text block).
    public struct TranslationPayload: Codable, Equatable, Sendable {
        public var translation: String
        public var note: String?
    }

    public static func systemPrompt(direction: LanguageDirection) -> String {
        let pair = direction == .jaToEn ? "Japanese to English" : "English to Japanese"
        return """
        You are a precise \(pair) translator living on the user's desktop. \
        Translate the user's text faithfully, keeping register and tone. \
        Reply with JSON only: {"translation": "<translated text>", "note": "<at most one short sentence on nuance, register, or ambiguity, or null>"}.
        """
    }

    public static func makeRequest(text: String, direction: LanguageDirection, model: String = defaultModel) -> Request {
        Request(
            model: model,
            max_tokens: 1024,
            system: systemPrompt(direction: direction),
            messages: [.init(role: "user", content: text)],
            output_config: .init(effort: "low")
        )
    }

    public static func makeURLRequest(_ body: Request, apiKey: String) throws -> URLRequest {
        var req = URLRequest(url: endpoint)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        req.setValue(version, forHTTPHeaderField: "anthropic-version")
        req.httpBody = try JSONEncoder().encode(body)
        return req
    }

    public static func parseTranslation(_ data: Data, backendID: String) throws -> TranslationResult {
        let response = try JSONDecoder().decode(Response.self, from: data)
        if let reason = response.stop_reason, reason == "refusal" {
            throw TranslationError.malformedResponse
        }
        let raw = response.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else { throw TranslationError.empty }
        // Tolerate code fences or leading prose around the JSON object.
        if let start = raw.firstIndex(of: "{"), let end = raw.lastIndex(of: "}"), start < end,
           let payload = try? JSONDecoder().decode(TranslationPayload.self, from: Data(raw[start...end].utf8)) {
            let note = payload.note?.trimmingCharacters(in: .whitespacesAndNewlines)
            return TranslationResult(text: payload.translation, note: (note?.isEmpty ?? true) ? nil : note, backend: backendID)
        }
        return TranslationResult(text: raw, note: nil, backend: backendID)
    }
}

/// Transport abstraction so tests can stub the network.
public protocol HTTPTransport: Sendable {
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

public struct URLSessionTransport: HTTPTransport {
    public var session: URLSession
    public init(session: URLSession = .shared) { self.session = session }
    public func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, resp) = try await session.data(for: request)
        guard let http = resp as? HTTPURLResponse else { throw TranslationError.malformedResponse }
        return (data, http)
    }
}

public struct ClaudeBackend: TranslationBackend {
    public let id = "claude"
    public var model: String
    public var apiKeyProvider: @Sendable () -> String?
    public var transport: any HTTPTransport

    public init(model: String = ClaudeAPI.defaultModel,
                apiKeyProvider: @escaping @Sendable () -> String?,
                transport: any HTTPTransport = URLSessionTransport()) {
        self.model = model
        self.apiKeyProvider = apiKeyProvider
        self.transport = transport
    }

    public func translate(_ text: String, direction: LanguageDirection) async throws -> TranslationResult {
        guard let key = apiKeyProvider(), !key.isEmpty else { throw TranslationError.missingAPIKey }
        let body = ClaudeAPI.makeRequest(text: text, direction: direction, model: model)
        let req = try ClaudeAPI.makeURLRequest(body, apiKey: key)
        let (data, http) = try await transport.send(req)
        guard (200..<300).contains(http.statusCode) else {
            throw TranslationError.http(status: http.statusCode, body: String(decoding: data, as: UTF8.self))
        }
        return try ClaudeAPI.parseTranslation(data, backendID: id)
    }
}
