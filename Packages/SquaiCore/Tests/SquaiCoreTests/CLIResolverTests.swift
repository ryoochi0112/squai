import Foundation
import XCTest
@testable import SquaiCore

private final class Box<T>: @unchecked Sendable {
    private let lock = NSLock()
    private var value: T
    init(_ value: T) { self.value = value }
    var current: T {
        get { lock.withLock { value } }
        set { lock.withLock { value = newValue } }
    }
}

final class CLIResolverTests: XCTestCase {
    private let home = URL(fileURLWithPath: "/tmp/squai-resolver-home", isDirectory: true)

    func testLocatesAgainOnEveryCallAndRefreshPicksUpNewLoginPath() async {
        let executables = Box<Set<String>>(["/opt/homebrew/bin/claude"])
        let loginPath = Box<String?>(nil)
        let resolver = CLIResolver(home: home, isExecutable: { executables.current.contains($0) },
                                   fetchLoginShellPath: { loginPath.current })
        XCTAssertEqual(resolver.locate(.claude)?.path, "/opt/homebrew/bin/claude")
        XCTAssertNil(resolver.locate(.chatgpt))

        // A shim added on a new login PATH dir is used after Recheck (refresh), not before.
        executables.current.insert("/shim/claude")
        loginPath.current = "/shim:/usr/bin"
        XCTAssertEqual(resolver.locate(.claude)?.path, "/opt/homebrew/bin/claude")
        await resolver.refresh()
        XCTAssertEqual(resolver.locate(.claude)?.path, "/shim/claude")
        XCTAssertTrue(resolver.childPATH(for: URL(fileURLWithPath: "/shim/claude")).hasPrefix("/shim:/usr/bin:"))

        // A CLI removed after lookup is never handed to a run.
        executables.current = ["/shim/codex"]
        XCTAssertNil(resolver.locate(.claude))
        XCTAssertEqual(resolver.locate(.chatgpt)?.path, "/shim/codex")
    }
}
