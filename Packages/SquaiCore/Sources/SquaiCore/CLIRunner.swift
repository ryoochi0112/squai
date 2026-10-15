import Foundation
import Darwin

public struct CLIResult: Equatable, Sendable {
    public var exitCode: Int32
    public var stdout: String
    public var stderr: String
    public var output: String

    public init(exitCode: Int32, stdout: String, stderr: String, output: String) {
        self.exitCode = exitCode
        self.stdout = stdout
        self.stderr = stderr
        self.output = output
    }
}

public enum CLIError: Error, Equatable, Sendable {
    case timedOut(seconds: TimeInterval)
    case launchFailed(String)
    case nonZeroExit(code: Int32, stderr: String)
}

public struct CLIRunner: CLIRunning {
    public init() {}

    /// Cancelling the calling task terminates the child (SIGTERM now, SIGKILL after 2 s).
    public func run(_ inv: CLIInvocation) async throws -> CLIResult {
        let canceller = CLICanceller()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                DispatchQueue.global(qos: .userInitiated).async {
                    do {
                        continuation.resume(returning: try Self.runProcess(inv, canceller: canceller))
                    } catch {
                        continuation.resume(throwing: error)
                    }
                }
            }
        } onCancel: {
            canceller.cancel()
        }
    }

    private static func runProcess(_ inv: CLIInvocation, canceller: CLICanceller) throws -> CLIResult {
        let process = Process()
        process.executableURL = inv.executable
        process.arguments = inv.arguments
        process.currentDirectoryURL = inv.cwd
        process.environment = inv.environment
        let input = Pipe()
        let output = Pipe()
        let errors = Pipe()
        process.standardInput = input
        process.standardOutput = output
        process.standardError = errors
        let exited = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in exited.signal() }
        defer {
            for pipe in [input, output, errors] {
                try? pipe.fileHandleForReading.close()
                try? pipe.fileHandleForWriting.close()
            }
        }
        do {
            try process.run()
        } catch {
            throw CLIError.launchFailed(error.localizedDescription)
        }
        canceller.attach(process)

        let io = DispatchGroup()
        let stdout = CLIDataBuffer()
        let stderr = CLIDataBuffer()
        for (handle, buffer) in [(output.fileHandleForReading, stdout), (errors.fileHandleForReading, stderr)] {
            io.enter()
            Thread.detachNewThread {
                buffer.set(handle.readDataToEndOfFile())
                io.leave()
            }
        }
        io.enter()
        Thread.detachNewThread {
            // macOS can deliver a pipe's SIGPIPE to the process even when the writing
            // thread masks it. Suppress it on this descriptor, without changing the
            // host application's signal disposition.
            let descriptor = input.fileHandleForWriting.fileDescriptor
            _ = fcntl(descriptor, F_SETNOSIGPIPE, 1)
            let data = Data(inv.stdin.utf8)
            data.withUnsafeBytes { bytes in
                var offset = 0
                while offset < bytes.count {
                    let count = Darwin.write(descriptor,
                                             bytes.baseAddress!.advanced(by: offset), bytes.count - offset)
                    if count > 0 { offset += count }
                    else if count < 0 && errno == EINTR { continue }
                    else { break }
                }
            }
            try? input.fileHandleForWriting.close()
            io.leave()
        }

        let timedOut = exited.wait(timeout: .now() + max(0, inv.timeout)) == .timedOut
        if timedOut {
            signal(process, SIGTERM)
            if exited.wait(timeout: .now() + 2) == .timedOut {
                signal(process, SIGKILL)
                exited.wait()
            }
        }
        process.waitUntilExit()
        // The invocation is finished. Descendants must not keep its pipes open or
        // continue running after either a successful exit or a timeout.
        signalGroup(process.processIdentifier, SIGKILL)
        io.wait()
        if timedOut { throw CLIError.timedOut(seconds: inv.timeout) }

        let stdoutText = String(decoding: stdout.get(), as: UTF8.self)
        let stderrText = String(decoding: stderr.get(), as: UTF8.self)
        guard process.terminationStatus == 0 else {
            throw CLIError.nonZeroExit(code: process.terminationStatus, stderr: stderrText)
        }
        let resultOutput: String
        if let file = inv.outputFile, FileManager.default.fileExists(atPath: file.path) {
            resultOutput = try String(contentsOf: file, encoding: .utf8)
        } else {
            resultOutput = stdoutText.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return CLIResult(exitCode: process.terminationStatus, stdout: stdoutText,
                         stderr: stderrText, output: resultOutput)
    }

    fileprivate static func signal(_ process: Process, _ value: Int32) {
        guard process.isRunning else { return }
        let pid = process.processIdentifier
        // Foundation launches macOS children in their own process group. Signal that
        // group as well, so shell scripts cannot leave a waiting sleep process behind.
        if getpgid(pid) == pid { _ = kill(-pid, value) }
        else { _ = kill(pid, value) }
    }

    private static func signalGroup(_ pid: Int32, _ value: Int32) {
        // A group may still exist after its leader has exited.
        _ = kill(-pid, value)
    }
}

private final class CLIDataBuffer: @unchecked Sendable {
    private let lock = NSLock()
    private var data = Data()

    func set(_ value: Data) {
        lock.lock()
        defer { lock.unlock() }
        data = value
    }

    func get() -> Data {
        lock.lock()
        defer { lock.unlock() }
        return data
    }
}

/// Lets a cancelled task terminate the child it launched, even if cancellation arrives before launch.
private final class CLICanceller: @unchecked Sendable {
    private let lock = NSLock()
    private var process: Process?
    private var cancelled = false

    func attach(_ process: Process) {
        lock.lock()
        self.process = process
        let already = cancelled
        lock.unlock()
        if already { terminate(process) }
    }

    func cancel() {
        lock.lock()
        cancelled = true
        let current = process
        lock.unlock()
        if let current { terminate(current) }
    }

    private func terminate(_ process: Process) {
        CLIRunner.signal(process, SIGTERM)
        DispatchQueue.global().asyncAfter(deadline: .now() + 2) { CLIRunner.signal(process, SIGKILL) }
    }
}
