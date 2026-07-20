import CodexSkinManagerCore
import Foundation

actor RecordingCommandRunner: CommandRunning {
    private(set) var requests: [CommandRequest] = []
    private var results: [CommandResult]

    init(results: [CommandResult]) {
        self.results = results
    }

    func run(_ request: CommandRequest) async throws -> CommandResult {
        requests.append(request)
        guard !results.isEmpty else {
            throw TestFailure(description: "recording runner has no result")
        }
        return results.removeFirst()
    }

    func recordedRequests() -> [CommandRequest] { requests }
}

enum EngineBridgeTests {
    static func run() async throws {
        try await mapsTypedCommandsWithoutShellInterpolation()
        try await mapsDuplicateImportToTypedError()
        try await processRunnerKeepsArgumentsLiteral()
        try await processRunnerCapsOutput()
        try await processRunnerTimesOut()
        print("PASS: EngineBridgeTests")
    }

    private static func mapsTypedCommandsWithoutShellInterpolation() async throws {
        let statusJSON = """
        {"session":"live","port":9341,"injectorAlive":true,"cdpOk":true,"codexRunning":true,"themeName":"Current"}
        """
        let importJSON = """
        {"pass":true,"code":"imported","message":"ok","themeId":"new-theme","themeName":"New Theme"}
        """
        let runner = RecordingCommandRunner(results: [
            CommandResult(exitCode: 0, stdout: statusJSON, stderr: ""),
            CommandResult(exitCode: 0, stdout: "", stderr: ""),
            CommandResult(exitCode: 0, stdout: importJSON, stderr: ""),
            CommandResult(exitCode: 0, stdout: importJSON, stderr: ""),
            CommandResult(exitCode: 0, stdout: "", stderr: ""),
        ])
        let engineRoot = URL(fileURLWithPath: "/tmp/fake-engine", isDirectory: true)
        let bridge = EngineBridge(engineRoot: engineRoot, runner: runner)
        let packageURL = URL(fileURLWithPath: "/tmp/My Theme;still-one-argument.codexskin")

        let status = try await bridge.status()
        try await bridge.switchTheme(libraryID: "preset-midnight-aurora;literal")
        _ = try await bridge.importTheme(packageURL: packageURL, replace: false)
        _ = try await bridge.importTheme(packageURL: packageURL, replace: true)
        try await bridge.restoreOriginal()

        let requests = await runner.recordedRequests()
        try expect(status.themeName == "Current", "status JSON must decode")
        try expect(requests.count == 5, "bridge must issue five commands")
        try expect(requests[0].executable.lastPathComponent == "status-dream-skin-macos.sh", "status script mismatch")
        try expect(requests[0].arguments == ["--json", "--deep"], "status arguments mismatch")
        try expect(requests[1].executable.lastPathComponent == "switch-theme-macos.sh", "switch script mismatch")
        try expect(requests[1].arguments == ["--id", "preset-midnight-aurora;literal"], "theme id must stay one argument")
        try expect(requests[2].arguments == ["--file", packageURL.path, "--json"], "import arguments mismatch")
        try expect(requests[3].arguments == ["--file", packageURL.path, "--replace", "--json"], "replace arguments mismatch")
        try expect(requests[4].executable.lastPathComponent == "restore-dream-skin-macos.sh", "restore script mismatch")
        try expect(requests[4].arguments == ["--restore-base-theme", "--restart-codex"], "restore must request full original UI and restart")
    }

    private static func mapsDuplicateImportToTypedError() async throws {
        let duplicate = """
        {"pass":false,"code":"theme_exists","message":"exists","themeId":"duplicate-id","themeName":"Duplicate"}
        """
        let runner = RecordingCommandRunner(results: [
            CommandResult(exitCode: 3, stdout: duplicate, stderr: "exists"),
        ])
        let bridge = EngineBridge(engineRoot: URL(fileURLWithPath: "/tmp/fake-engine"), runner: runner)

        do {
            _ = try await bridge.importTheme(
                packageURL: URL(fileURLWithPath: "/tmp/duplicate.codexskin"),
                replace: false
            )
            throw TestFailure(description: "duplicate import should throw")
        } catch ManagerError.themeAlreadyExists(let id) {
            try expect(id == "duplicate-id", "duplicate id must be preserved")
        }
    }

    private static func processRunnerKeepsArgumentsLiteral() async throws {
        let directory = try makeTemporaryDirectory(prefix: "CodexSkinManagerProcessTests")
        defer { try? FileManager.default.removeItem(at: directory) }
        let script = try makeScript(
            in: directory,
            name: "echo-argument.sh",
            body: "#!/bin/bash\n/usr/bin/printf '%s' \"$1\"\n"
        )
        let marker = directory.appendingPathComponent("must-not-exist")
        let argument = "literal;/usr/bin/touch \(marker.path)"

        let result = try await ProcessRunner().run(
            CommandRequest(executable: script, arguments: [argument], timeout: 2)
        )

        try expect(result.stdout == argument, "process arguments must not be shell-evaluated")
        try expect(!FileManager.default.fileExists(atPath: marker.path), "semicolon payload must not execute")
    }

    private static func processRunnerCapsOutput() async throws {
        let directory = try makeTemporaryDirectory(prefix: "CodexSkinManagerProcessTests")
        defer { try? FileManager.default.removeItem(at: directory) }
        let script = try makeScript(
            in: directory,
            name: "large-output.sh",
            body: "#!/bin/bash\n/usr/bin/yes x | /usr/bin/head -c 70000\n"
        )

        let result = try await ProcessRunner().run(
            CommandRequest(executable: script, arguments: [], timeout: 2)
        )

        try expect(result.stdout.utf8.count == 65_536, "captured stdout must be capped at 64 KB")
    }

    private static func processRunnerTimesOut() async throws {
        let request = CommandRequest(
            executable: URL(fileURLWithPath: "/bin/sleep"),
            arguments: ["1"],
            timeout: 0.1
        )
        let started = Date()

        do {
            _ = try await ProcessRunner().run(request)
            throw TestFailure(description: "sleep should time out")
        } catch CommandRunnerError.timedOut {
            try expect(Date().timeIntervalSince(started) < 0.8, "timeout must terminate promptly")
        }
    }

    private static func makeScript(in directory: URL, name: String, body: String) throws -> URL {
        let url = directory.appendingPathComponent(name)
        try Data(body.utf8).write(to: url)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: url.path)
        return url
    }
}
