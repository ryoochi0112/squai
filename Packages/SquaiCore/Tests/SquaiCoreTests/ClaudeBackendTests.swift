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
