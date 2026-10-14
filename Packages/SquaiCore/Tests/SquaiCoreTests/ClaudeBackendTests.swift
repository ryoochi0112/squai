import XCTest
@testable import SquaiCore

private struct StubTransport: HTTPTransport {
    var status: Int
    var body: String
    var capture: @Sendable (URLRequest) -> Void = { _ in }
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        capture(request)
        let http = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
        return (Data(body.utf8), http)
    }
}

final class ClaudeBackendTests: XCTestCase {
    func testGenericPromptRequestShape() throws {
        let request = try ClaudeAPI.makeURLRequest(
            ClaudeAPI.makePromptRequest(system: "custom system", user: "custom user", model: "custom model"),
            apiKey: "stub-key")
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.url, ClaudeAPI.endpoint)
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")
        XCTAssertEqual(request.value(forHTTPHeaderField: "x-api-key"), "stub-key")
        XCTAssertEqual(request.value(forHTTPHeaderField: "anthropic-version"), ClaudeAPI.version)
        let body = try JSONDecoder().decode(ClaudeAPI.Request.self, from: XCTUnwrap(request.httpBody))
        XCTAssertEqual(body.system, "custom system")
        XCTAssertEqual(body.model, "custom model")
        XCTAssertEqual(body.max_tokens, 1024)
        XCTAssertEqual(body.output_config?.effort, "low")
        XCTAssertEqual(body.messages.count, 1)
        XCTAssertEqual(body.messages.first?.role, "user")
        XCTAssertEqual(body.messages.first?.content, "custom user")
    }

    func testGenericTextConcatenatesOnlyTextBlocksAndTrims() throws {
        let body = #"{"content":[{"type":"thinking","text":"skip"},{"type":"text","text":" \nHello"},{"type":"tool_use","text":"skip"},{"type":"text"},{"type":"text","text":" world\n "}],"stop_reason":"end_turn"}"#
        XCTAssertEqual(try ClaudeAPI.parseText(Data(body.utf8)), "Hello world")
    }

    func testGenericTextRefusalAndEmpty() {
        let cases: [(String, BackendError)] = [
            (#"{"content":[{"type":"text","text":"No"}],"stop_reason":"refusal"}"#, .failed(.claude, "refused")),
            (#"{"content":[{"type":"text","text":" \n\t "}]}"#, .empty),
            (#"{"content":[{"type":"thinking"}]}"#, .empty),
            (#"{"content":[]}"#, .empty)
        ]
        for (body, expected) in cases {
            XCTAssertThrowsError(try ClaudeAPI.parseText(Data(body.utf8))) {
                XCTAssertEqual($0 as? BackendError, expected)
            }
        }
    }

    func testGenericTextRejectsMalformedResponse() {
        XCTAssertThrowsError(try ClaudeAPI.parseText(Data("{}".utf8))) {
            XCTAssertTrue($0 is DecodingError)
        }
    }

    func testRequestShape() throws {
        let req = try ClaudeAPI.makeURLRequest(ClaudeAPI.makeRequest(text: "hello", direction: .enToJa), apiKey: "k")
        XCTAssertEqual(req.url, ClaudeAPI.endpoint)
        XCTAssertEqual(req.value(forHTTPHeaderField: "x-api-key"), "k")
        XCTAssertEqual(req.value(forHTTPHeaderField: "anthropic-version"), "2023-06-01")
        let json = try JSONSerialization.jsonObject(with: req.httpBody!) as! [String: Any]
        XCTAssertEqual(json["model"] as? String, "claude-haiku-5-5")
        XCTAssertEqual(json["max_tokens"] as? Int, 1024)
        XCTAssertNil(json["temperature"])
        XCTAssertEqual((json["output_config"] as? [String: Any])?["effort"] as? String, "low")
        XCTAssertEqual(((json["messages"] as? [[String: Any]])?.first?["content"]) as? String, "hello")
    }

    func testParsesTextBlocksSkippingThinking() throws {
        let body = """
        {"id":"m","type":"message","role":"assistant","model":"claude-haiku-5-5",
         "content":[{"type":"thinking","thinking":"","signature":"x"},
                    {"type":"text","text":"{\\"translation\\":\\"こんにちは\\",\\"note\\":\\"Casual greeting.\\"}"}],
         "stop_reason":"end_turn","usage":{"input_tokens":10,"output_tokens":5}}
        """
        let t = try ClaudeAPI.parseTranslation(Data(body.utf8), backendID: "claude")
        XCTAssertEqual(t, TranslationResult(text: "こんにちは", note: "Casual greeting.", backend: "claude"))
    }

    func testFallsBackToRawTextWhenNotJSON() throws {
        let body = #"{"content":[{"type":"text","text":"Hello"}],"stop_reason":"end_turn"}"#
        XCTAssertEqual(try ClaudeAPI.parseTranslation(Data(body.utf8), backendID: "claude").text, "Hello")
    }

    func testMissingKey() async {
        let backend = ClaudeBackend(apiKeyProvider: { nil }, transport: StubTransport(status: 200, body: "{}"))
        do { _ = try await backend.translate("x", direction: .enToJa); XCTFail() }
        catch { XCTAssertEqual(error as? TranslationError, .missingAPIKey) }
    }

    func testHTTPErrorSurfacesStatus() async {
        let backend = ClaudeBackend(apiKeyProvider: { "k" }, transport: StubTransport(status: 401, body: "nope"))
        do { _ = try await backend.translate("x", direction: .enToJa); XCTFail() }
        catch { XCTAssertEqual(error as? TranslationError, .http(status: 401, body: "nope")) }
    }
}
