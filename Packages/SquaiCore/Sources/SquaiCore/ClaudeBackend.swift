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

    public static func makeURLRequest(_ body: Request, apiKey: String) throws -> URLRequest {
        var req = URLRequest(url: endpoint)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        req.setValue(version, forHTTPHeaderField: "anthropic-version")
        req.httpBody = try JSONEncoder().encode(body)
        return req
    }

    public static func makePromptRequest(system: String, user: String, model: String) -> Request {
        Request(model: model, max_tokens: 1024, system: system,
                messages: [.init(role: "user", content: user)],
                output_config: .init(effort: "low"))
    }

    public static func parseText(_ data: Data) throws -> String {
        let response = try JSONDecoder().decode(Response.self, from: data)
        if response.stop_reason == "refusal" {
            throw BackendError.failed(.claude, "refused")
        }
        let text = response.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { throw BackendError.empty }
        return text
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
        guard let http = resp as? HTTPURLResponse else { throw BackendError.failed(.claude, "malformed response") }
        return (data, http)
    }
}
