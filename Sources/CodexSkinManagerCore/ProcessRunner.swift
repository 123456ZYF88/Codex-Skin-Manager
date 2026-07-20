import Darwin
import Foundation

package struct CommandRequest: Equatable, Sendable {
    package let executable: URL
    package let arguments: [String]
    package let timeout: TimeInterval

    package init(executable: URL, arguments: [String], timeout: TimeInterval) {
        self.executable = executable
        self.arguments = arguments
        self.timeout = timeout
    }
}

package struct CommandResult: Equatable, Sendable {
    package let exitCode: Int32
    package let stdout: String
    package let stderr: String

    package init(exitCode: Int32, stdout: String, stderr: String) {
        self.exitCode = exitCode
        self.stdout = stdout
        self.stderr = stderr
    }
}

package enum CommandRunnerError: Error, Equatable, LocalizedError {
    case failedToLaunch(String)
    case timedOut

    package var errorDescription: String? {
        switch self {
        case .failedToLaunch(let message): message
        case .timedOut: "命令执行超时。"
        }
    }
}

package protocol CommandRunning: Sendable {
    func run(_ request: CommandRequest) async throws -> CommandResult
}

package struct ProcessRunner: CommandRunning, Sendable {
    private static let captureLimit = 65_536

    package init() {}

    package func run(_ request: CommandRequest) async throws -> CommandResult {
        let process = Process()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.executableURL = request.executable
        process.arguments = request.arguments
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        // Register completion before launch: very short-lived commands can exit before an
        // asynchronously scheduled waitUntilExit() starts observing Foundation's task state.
        let terminationStatuses = AsyncStream<Int32>(bufferingPolicy: .bufferingNewest(1)) { continuation in
            process.terminationHandler = { completedProcess in
                continuation.yield(completedProcess.terminationStatus)
                continuation.finish()
            }
        }

        do {
            try process.run()
        } catch {
            throw CommandRunnerError.failedToLaunch(error.localizedDescription)
        }

        let stdoutTask = Task.detached(priority: .utility) {
            Self.readCapped(from: stdoutPipe.fileHandleForReading)
        }
        let stderrTask = Task.detached(priority: .utility) {
            Self.readCapped(from: stderrPipe.fileHandleForReading)
        }
        let completionTask = Task.detached(priority: .userInitiated) { () -> Int32 in
            for await status in terminationStatuses {
                return status
            }
            return process.terminationStatus
        }

        let timeout = max(0.01, request.timeout)
        let didTimeOut = await withTaskGroup(of: Bool.self) { group in
            group.addTask {
                _ = await completionTask.value
                return false
            }
            group.addTask {
                let nanoseconds = UInt64(min(timeout, 86_400) * 1_000_000_000)
                try? await Task.sleep(nanoseconds: nanoseconds)
                guard !Task.isCancelled else { return false }
                if process.isRunning {
                    process.terminate()
                    let processID = process.processIdentifier
                    Task.detached(priority: .utility) {
                        try? await Task.sleep(nanoseconds: 500_000_000)
                        if process.isRunning {
                            Darwin.kill(processID, SIGKILL)
                        }
                    }
                }
                return true
            }
            let first = await group.next() ?? false
            group.cancelAll()
            return first
        }

        let exitCode = await completionTask.value
        let stdoutData = await stdoutTask.value
        let stderrData = await stderrTask.value
        if didTimeOut { throw CommandRunnerError.timedOut }
        return CommandResult(
            exitCode: exitCode,
            stdout: String(decoding: stdoutData, as: UTF8.self),
            stderr: String(decoding: stderrData, as: UTF8.self)
        )
    }

    private static func readCapped(from handle: FileHandle) -> Data {
        var captured = Data()
        while true {
            let chunk: Data
            do {
                chunk = try handle.read(upToCount: 8_192) ?? Data()
            } catch {
                break
            }
            if chunk.isEmpty { break }
            let remaining = captureLimit - captured.count
            if remaining > 0 {
                captured.append(chunk.prefix(remaining))
            }
        }
        return captured
    }
}
