import CodexSkinManagerCore
import Foundation

final class FakeThemeCatalog: ThemeCatalogReading, @unchecked Sendable {
    var themes: [ThemeRecord]

    init(themes: [ThemeRecord]) {
        self.themes = themes
    }

    func loadThemes() throws -> [ThemeRecord] { themes }
    func loadActiveTheme() -> ThemeManifest? { themes.first(where: \.isActive)?.manifest }
}

actor FakeEngine: EngineControlling {
    private(set) var switchedIDs: [String] = []
    private(set) var imports: [(URL, Bool)] = []
    private(set) var restoreCount = 0
    var duplicateOnNormalImport = false
    var switchFailure: ManagerError?
    var blockSwitch = false
    private var switchStarted = false
    private var startWaiters: [CheckedContinuation<Void, Never>] = []
    private var switchRelease: CheckedContinuation<Void, Never>?

    func status() async throws -> EngineStatus {
        EngineStatus(
            session: "live",
            port: 9341,
            injectorAlive: true,
            cdpOk: true,
            codexRunning: true,
            themeName: "Current"
        )
    }

    func switchTheme(libraryID: String) async throws {
        switchedIDs.append(libraryID)
        switchStarted = true
        startWaiters.forEach { $0.resume() }
        startWaiters.removeAll()
        if blockSwitch {
            await withCheckedContinuation { switchRelease = $0 }
        }
        if let switchFailure { throw switchFailure }
    }

    func importTheme(packageURL: URL, replace: Bool) async throws -> ThemeImportResult {
        imports.append((packageURL, replace))
        if duplicateOnNormalImport && !replace {
            throw ManagerError.themeAlreadyExists(id: "duplicate")
        }
        return ThemeImportResult(
            pass: true,
            code: "imported",
            message: "ok",
            themeId: "imported-id",
            themeName: "Imported Theme"
        )
    }

    func restoreOriginal() async throws {
        restoreCount += 1
    }

    func setDuplicateOnNormalImport(_ value: Bool) { duplicateOnNormalImport = value }
    func setSwitchFailure(_ error: ManagerError?) { switchFailure = error }
    func setBlockSwitch(_ value: Bool) { blockSwitch = value }

    func waitForSwitchStart() async {
        if switchStarted { return }
        await withCheckedContinuation { startWaiters.append($0) }
    }

    func releaseSwitch() {
        switchRelease?.resume()
        switchRelease = nil
    }

    func snapshot() -> (switchedIDs: [String], importReplaceFlags: [Bool], restoreCount: Int) {
        (switchedIDs, imports.map(\.1), restoreCount)
    }
}

enum AppModelTests {
    @MainActor
    static func run() async throws {
        try await appliesThemeAndStoresRecent()
        try await ignoresSecondActionWhileBusy()
        try await duplicateImportExposesReplaceConfirmation()
        try await duplicateImportCanBeCancelled()
        try await restoreCallsOnlyRestoreCommand()
        try await failuresBecomeActionableState()
        print("PASS: AppModelTests")
    }

    @MainActor
    private static func appliesThemeAndStoresRecent() async throws {
        let themes = [makeTheme(id: "one"), makeTheme(id: "two"), makeTheme(id: "three"), makeTheme(id: "four")]
        let engine = FakeEngine()
        let defaults = makeDefaults()
        let model = AppModel(catalog: FakeThemeCatalog(themes: themes), engine: engine, defaults: defaults)

        try expect(model.operation == .idle, "model must start idle")
        for theme in themes {
            await model.apply(theme)
        }

        let snapshot = await engine.snapshot()
        try expect(snapshot.switchedIDs == ["one", "two", "three", "four"], "apply must use library ids")
        try expect(model.operation == .succeeded("已应用 Four"), "apply success message mismatch")
        try expect(model.recentThemeIDs == ["four", "three", "two"], "recents must retain the last three ids")
    }

    @MainActor
    private static func ignoresSecondActionWhileBusy() async throws {
        let theme = makeTheme(id: "blocked")
        let engine = FakeEngine()
        await engine.setBlockSwitch(true)
        let model = AppModel(
            catalog: FakeThemeCatalog(themes: [theme]),
            engine: engine,
            defaults: makeDefaults()
        )

        let first = Task { @MainActor in await model.apply(theme) }
        await engine.waitForSwitchStart()
        await model.restoreOriginal()
        let busySnapshot = await engine.snapshot()
        try expect(busySnapshot.restoreCount == 0, "a restore must be ignored while switching")
        await engine.releaseSwitch()
        await first.value
    }

    @MainActor
    private static func duplicateImportExposesReplaceConfirmation() async throws {
        let engine = FakeEngine()
        await engine.setDuplicateOnNormalImport(true)
        let model = AppModel(catalog: FakeThemeCatalog(themes: []), engine: engine, defaults: makeDefaults())
        let packageURL = URL(fileURLWithPath: "/tmp/duplicate.codexskin")

        await model.importPackage(packageURL)
        try expect(model.pendingReplacementURL == packageURL, "duplicate import must retain its package URL")
        try expect(model.operation == .idle, "duplicate prompt must return to an actionable state")
        await model.replacePendingImport()

        let snapshot = await engine.snapshot()
        try expect(snapshot.importReplaceFlags == [false, true], "replacement must be explicit")
        try expect(model.pendingReplacementURL == nil, "replacement prompt must clear after use")
    }

    @MainActor
    private static func duplicateImportCanBeCancelled() async throws {
        let engine = FakeEngine()
        await engine.setDuplicateOnNormalImport(true)
        let model = AppModel(catalog: FakeThemeCatalog(themes: []), engine: engine, defaults: makeDefaults())

        await model.importPackage(URL(fileURLWithPath: "/tmp/cancel.codexskin"))
        model.cancelPendingImport()

        try expect(model.pendingReplacementURL == nil, "cancel must clear the duplicate prompt")
    }

    @MainActor
    private static func restoreCallsOnlyRestoreCommand() async throws {
        let engine = FakeEngine()
        let model = AppModel(catalog: FakeThemeCatalog(themes: []), engine: engine, defaults: makeDefaults())

        await model.restoreOriginal()

        let snapshot = await engine.snapshot()
        try expect(snapshot.restoreCount == 1, "restore must call the restore command exactly once")
        try expect(snapshot.switchedIDs.isEmpty, "restore must not switch a theme")
        try expect(snapshot.importReplaceFlags.isEmpty, "restore must not import")
        try expect(model.operation == .succeeded("已恢复 Codex 原版界面"), "restore success message mismatch")
    }

    @MainActor
    private static func failuresBecomeActionableState() async throws {
        let theme = makeTheme(id: "failure")
        let engine = FakeEngine()
        await engine.setSwitchFailure(.engine("可读错误"))
        let model = AppModel(
            catalog: FakeThemeCatalog(themes: [theme]),
            engine: engine,
            defaults: makeDefaults()
        )

        await model.apply(theme)

        try expect(model.operation == .failed("可读错误"), "failure message must remain actionable")
    }

    private static func makeTheme(id: String) -> ThemeRecord {
        let name = id.prefix(1).uppercased() + id.dropFirst()
        let directory = URL(fileURLWithPath: "/tmp/\(id)", isDirectory: true)
        return ThemeRecord(
            libraryID: id,
            manifest: ThemeManifest(
                schemaVersion: 1,
                id: id,
                name: name,
                image: "background.png",
                appearance: "dark"
            ),
            directoryURL: directory,
            imageURL: directory.appendingPathComponent("background.png"),
            isActive: false
        )
    }

    private static func makeDefaults() -> UserDefaults {
        let suite = "CodexSkinManagerTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }
}
