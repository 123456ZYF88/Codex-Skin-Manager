import Foundation

package struct ThemeImportResult: Codable, Equatable, Sendable {
    package let pass: Bool
    package let code: String
    package let message: String
    package let themeId: String
    package let themeName: String

    package init(pass: Bool, code: String, message: String, themeId: String, themeName: String) {
        self.pass = pass
        self.code = code
        self.message = message
        self.themeId = themeId
        self.themeName = themeName
    }
}

package enum ManagerError: Error, Equatable, LocalizedError {
    case themeAlreadyExists(id: String)
    case engine(String)
    case invalidResponse(String)

    package var errorDescription: String? {
        switch self {
        case .themeAlreadyExists:
            "这个主题已经安装。"
        case .engine(let message), .invalidResponse(let message):
            message
        }
    }
}

package protocol EngineControlling: Sendable {
    func status() async throws -> EngineStatus
    func switchTheme(libraryID: String) async throws
    func importTheme(packageURL: URL, replace: Bool) async throws -> ThemeImportResult
    func restoreOriginal() async throws
}

package struct EngineBridge: EngineControlling, Sendable {
    package let engineRoot: URL
    private let runner: any CommandRunning

    package init(engineRoot: URL, runner: any CommandRunning = ProcessRunner()) {
        self.engineRoot = engineRoot.standardizedFileURL
        self.runner = runner
    }

    package func status() async throws -> EngineStatus {
        let result = try await runScript(
            named: "status-dream-skin-macos.sh",
            arguments: ["--json", "--deep"],
            timeout: 8
        )
        try requireSuccess(result)
        do {
            return try JSONDecoder().decode(EngineStatus.self, from: Data(result.stdout.utf8))
        } catch {
            throw ManagerError.invalidResponse("无法读取 Dream Skin 状态。")
        }
    }

    package func switchTheme(libraryID: String) async throws {
        let result = try await runScript(
            named: "switch-theme-macos.sh",
            arguments: ["--id", libraryID],
            timeout: 60
        )
        try requireSuccess(result)
    }

    package func importTheme(packageURL: URL, replace: Bool) async throws -> ThemeImportResult {
        var arguments = ["--file", packageURL.path]
        if replace { arguments.append("--replace") }
        arguments.append("--json")
        let result = try await runScript(
            named: "import-theme-pack-macos.sh",
            arguments: arguments,
            timeout: 45
        )
        if result.exitCode == 3 {
            let payload = try? JSONDecoder().decode(ThemeImportResult.self, from: Data(result.stdout.utf8))
            throw ManagerError.themeAlreadyExists(id: payload?.themeId ?? "")
        }
        try requireSuccess(result)
        do {
            let payload = try JSONDecoder().decode(ThemeImportResult.self, from: Data(result.stdout.utf8))
            guard payload.pass else { throw ManagerError.engine(sanitize(payload.message)) }
            return payload
        } catch let error as ManagerError {
            throw error
        } catch {
            throw ManagerError.invalidResponse("主题导入器返回了无法识别的结果。")
        }
    }

    package func restoreOriginal() async throws {
        let result = try await runScript(
            named: "restore-dream-skin-macos.sh",
            arguments: ["--restore-base-theme", "--restart-codex"],
            timeout: 90
        )
        try requireSuccess(result)
    }

    private func runScript(named name: String, arguments: [String], timeout: TimeInterval) async throws -> CommandResult {
        let executable = engineRoot
            .appendingPathComponent("scripts", isDirectory: true)
            .appendingPathComponent(name, isDirectory: false)
        return try await runner.run(
            CommandRequest(executable: executable, arguments: arguments, timeout: timeout)
        )
    }

    private func requireSuccess(_ result: CommandResult) throws {
        guard result.exitCode == 0 else {
            let source = result.stderr.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? result.stdout
                : result.stderr
            throw ManagerError.engine(sanitize(source))
        }
    }

    private func sanitize(_ text: String) -> String {
        let clean = text.unicodeScalars.filter { scalar in
            !CharacterSet.controlCharacters.contains(scalar) || scalar == "\n" || scalar == "\t"
        }
        let normalized = String(String.UnicodeScalarView(clean))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if normalized.isEmpty { return "Dream Skin 命令执行失败。" }
        return String(normalized.prefix(500))
    }
}
