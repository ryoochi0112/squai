import XCTest
@testable import SquaiCore

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
}
