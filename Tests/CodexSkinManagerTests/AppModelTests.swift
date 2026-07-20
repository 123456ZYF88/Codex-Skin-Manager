import CodexSkinManagerCore
import Foundation

final class FakeThemeCatalog: ThemeCatalogReading, @unchecked Sendable {
    private let lock = NSLock()
    private var storedThemes: [ThemeRecord]
    private var activeLibraryID: String?

    init(themes: [ThemeRecord]) {
        storedThemes = themes
        activeLibraryID = themes.first(where: \.isActive)?.libraryID
    }

    var themes: [ThemeRecord] {
        get { loadThemesForTest() }
        set { replaceThemes(newValue) }
    }

    func loadThemes() throws -> [ThemeRecord] { loadThemesForTest() }

    func loadActiveTheme() -> ThemeManifest? {
        loadThemesForTest().first(where: \.isActive)?.manifest
    }

    func setActiveLibraryID(_ id: String?) {
        lock.lock()
        activeLibraryID = id
        lock.unlock()
    }

    private func loadThemesForTest() -> [ThemeRecord] {
        lock.lock()
        let activeID = activeLibraryID
        let themes = storedThemes
        lock.unlock()
        return themes.map { theme in
            ThemeRecord(
                libraryID: theme.libraryID,
                manifest: theme.manifest,
                directoryURL: theme.directoryURL,
                imageURL: theme.imageURL,
                isActive: theme.libraryID == activeID
            )
        }
    }

    private func replaceThemes(_ themes: [ThemeRecord]) {
        lock.lock()
        storedThemes = themes
        activeLibraryID = themes.first(where: \.isActive)?.libraryID
        lock.unlock()
    }
}

actor FakeThemePackageExporter: ThemePackageExporting {
    private(set) var exports: [(themeID: String, destination: URL)] = []

    func export(theme: ThemeRecord, to destination: URL) async throws -> URL {
        exports.append((theme.libraryID, destination))
        return destination
    }

    func snapshot() -> [(themeID: String, destination: URL)] { exports }
}

actor FakeEngine: EngineControlling {
    private(set) var switchedIDs: [String] = []
    private(set) var imports: [(URL, Bool)] = []
    private(set) var validatedPackages: [URL] = []
    private(set) var restoreCount = 0
    private(set) var pauseCount = 0
    private(set) var restartCount = 0
    var duplicateOnNormalImport = false
    var switchFailure: ManagerError?
    var statusFailure: ManagerError?
    var validationFailure: ManagerError?
    var blockSwitch = false
    private var engineStatus = EngineStatus(
        session: "live",
        port: 9341,
        injectorAlive: true,
        cdpOk: true,
        codexRunning: true,
        themeName: "Current"
    )
    private let onSwitch: @Sendable (String) -> Void
    private var switchStarted = false
    private var startWaiters: [CheckedContinuation<Void, Never>] = []
    private var switchRelease: CheckedContinuation<Void, Never>?

    init(onSwitch: @escaping @Sendable (String) -> Void = { _ in }) {
        self.onSwitch = onSwitch
    }

    func status() async throws -> EngineStatus {
        if let statusFailure { throw statusFailure }
        return engineStatus
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
        engineStatus = EngineStatus(
            session: "live",
            port: 9341,
            injectorAlive: true,
            cdpOk: true,
            codexRunning: true,
            themeName: libraryID
        )
        onSwitch(libraryID)
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

    func validateThemePackage(packageURL: URL) async throws {
        validatedPackages.append(packageURL)
        if let validationFailure { throw validationFailure }
    }

    func restoreOriginal() async throws {
        restoreCount += 1
    }

    func pauseTheme() async throws {
        pauseCount += 1
    }

    func restartTheme() async throws {
        restartCount += 1
    }

    func setDuplicateOnNormalImport(_ value: Bool) { duplicateOnNormalImport = value }
    func setSwitchFailure(_ error: ManagerError?) { switchFailure = error }
    func setStatusFailure(_ error: ManagerError?) { statusFailure = error }
    func setValidationFailure(_ error: ManagerError?) { validationFailure = error }
    func setBlockSwitch(_ value: Bool) { blockSwitch = value }
    func setStatus(_ status: EngineStatus) { engineStatus = status }

    func waitForSwitchStart() async {
        if switchStarted { return }
        await withCheckedContinuation { startWaiters.append($0) }
    }

    func releaseSwitch() {
        switchRelease?.resume()
        switchRelease = nil
    }

    func snapshot() -> (
        switchedIDs: [String],
        importReplaceFlags: [Bool],
        validatedPackages: [URL],
        restoreCount: Int,
        pauseCount: Int,
        restartCount: Int
    ) {
        (switchedIDs, imports.map(\.1), validatedPackages, restoreCount, pauseCount, restartCount)
    }
}

enum AppModelTests {
    @MainActor
    static func run() async throws {
        try await appliesThemeAndStoresRecent()
        try await runningWithoutCDPRequiresConsent()
        try await applyRequiresVerifiedTarget()
        try await pendingRestartApplyCanBeCancelled()
        try await confirmPendingRestartApplyVerifiesAndRecordsTheme()
        try await selectsInactiveThemeWithoutChangingActivity()
        try await refreshFallsBackWhenSelectedThemeIsRemoved()
        try await ignoresSecondActionWhileBusy()
        try await duplicateImportExposesReplaceConfirmation()
        try await duplicateImportCanBeCancelled()
        try await restoreCallsOnlyRestoreCommand()
        try await pauseRefreshesStatus()
        try await restartRefreshesStatus()
        try await pauseFailsWhenStatusRefreshFails()
        try await restartFailsWhenStatusRefreshFails()
        try await busySwitchBlocksPauseAndRestart()
        try await exportsSelectedThemeThenValidatesPackage()
        try await failedExportValidationPreservesPriorURL()
        try await failuresBecomeActionableState()
        print("PASS: AppModelTests")
    }

    @MainActor
    private static func exportsSelectedThemeThenValidatesPackage() async throws {
        let theme = makeThemeRecord(id: "exported", name: "Exported")
        let engine = FakeEngine()
        let exporter = FakeThemePackageExporter()
        let model = AppModel(
            catalog: FakeThemeCatalog(themes: [theme]),
            engine: engine,
            exporter: exporter,
            defaults: makeDefaults()
        )
        let destination = URL(fileURLWithPath: "/tmp/exported.codexskin")
        await model.refresh()

        try expect(ManagerOperation.exporting.isBusy, "export operation must block concurrent actions")
        await model.exportSelectedTheme(to: destination)

        let exports = await exporter.snapshot()
        let engineSnapshot = await engine.snapshot()
        try expect(exports.count == 1, "selected theme must be exported exactly once")
        try expect(exports.first?.themeID == "exported", "selected theme must be passed to exporter")
        try expect(exports.first?.destination == destination, "export destination mismatch")
        try expect(engineSnapshot.validatedPackages == [destination], "published export must be engine-validated")
        try expect(model.lastExportURL == destination, "validated export URL must be retained")
        try expect(model.operation == .succeeded("已导出 Exported"), "export success message mismatch")
    }

    @MainActor
    private static func failedExportValidationPreservesPriorURL() async throws {
        let theme = makeThemeRecord(id: "validation-failure", name: "Validation Failure")
        let engine = FakeEngine()
        let exporter = FakeThemePackageExporter()
        let model = AppModel(
            catalog: FakeThemeCatalog(themes: [theme]),
            engine: engine,
            exporter: exporter,
            defaults: makeDefaults()
        )
        let prior = URL(fileURLWithPath: "/tmp/prior.codexskin")
        let rejected = URL(fileURLWithPath: "/tmp/rejected.codexskin")
        await model.refresh()
        await model.exportSelectedTheme(to: prior)
        await engine.setValidationFailure(.engine("导出后验证失败，请检查主题包。"))

        await model.exportSelectedTheme(to: rejected)

        let snapshot = await engine.snapshot()
        try expect(snapshot.validatedPackages == [prior, rejected], "every export must be validated")
        try expect(model.lastExportURL == prior, "failed validation must preserve the prior export URL")
        try expect(
            model.operation == .failed("导出后验证失败，请检查主题包。"),
            "validation failure must remain actionable"
        )
    }

    @MainActor
    private static func appliesThemeAndStoresRecent() async throws {
        let themes = [
            makeThemeRecord(id: "one", name: "One"),
            makeThemeRecord(id: "two", name: "Two"),
            makeThemeRecord(id: "three", name: "Three"),
            makeThemeRecord(id: "four", name: "Four"),
        ]
        let catalog = FakeThemeCatalog(themes: themes)
        let engine = FakeEngine(onSwitch: { id in catalog.setActiveLibraryID(id) })
        let defaults = makeDefaults()
        let model = AppModel(catalog: catalog, engine: engine, defaults: defaults)

        try expect(model.operation == .idle, "model must start idle")
        for theme in themes {
            await model.apply(theme)
        }

        let snapshot = await engine.snapshot()
        try expect(snapshot.switchedIDs == ["one", "two", "three", "four"], "apply must use library ids")
        try expect(model.operation == .succeeded("已应用 Four"), "apply success message mismatch")
        try expect(model.recentThemeIDs == ["four", "three", "two", "one"], "recents must retain the last eight ids")
    }

    @MainActor
    private static func runningWithoutCDPRequiresConsent() async throws {
        let catalog = FakeThemeCatalog(themes: [makeThemeRecord(id: "cold", name: "Cold")])
        let engine = FakeEngine()
        await engine.setStatus(EngineStatus(
            session: "off", port: 9341, injectorAlive: false,
            cdpOk: false, codexRunning: true, themeName: ""
        ))
        let model = AppModel(catalog: catalog, engine: engine, defaults: makeDefaults())
        await model.refresh()
        await model.apply(catalog.themes[0])
        try expect(model.pendingRestartThemeID == "cold", "restart consent must retain the theme id")
        let snapshot = await engine.snapshot()
        try expect(snapshot.switchedIDs.isEmpty, "theme must not switch before consent")
    }

    @MainActor
    private static func applyRequiresVerifiedTarget() async throws {
        let theme = makeThemeRecord(id: "target", name: "Target")
        let catalog = FakeThemeCatalog(themes: [theme])
        let engine = FakeEngine(onSwitch: { _ in })
        let model = AppModel(catalog: catalog, engine: engine, defaults: makeDefaults())
        await model.refresh()
        await model.apply(theme)
        try expect(model.operation == .failed("主题切换完成，但未验证到目标主题。"), "unverified apply must fail")
    }

    @MainActor
    private static func pendingRestartApplyCanBeCancelled() async throws {
        let theme = makeThemeRecord(id: "cancel", name: "Cancel")
        let engine = FakeEngine()
        await engine.setStatus(EngineStatus(
            session: "off", port: 9341, injectorAlive: false,
            cdpOk: false, codexRunning: true, themeName: ""
        ))
        let model = AppModel(
            catalog: FakeThemeCatalog(themes: [theme]),
            engine: engine,
            defaults: makeDefaults()
        )

        await model.apply(theme)
        model.cancelPendingRestartApply()

        try expect(model.pendingRestartThemeID == nil, "cancel must clear restart consent")
        let snapshot = await engine.snapshot()
        try expect(snapshot.switchedIDs.isEmpty, "cancel must leave the engine untouched")
    }

    @MainActor
    private static func confirmPendingRestartApplyVerifiesAndRecordsTheme() async throws {
        let theme = makeThemeRecord(id: "confirmed", name: "Confirmed")
        let catalog = FakeThemeCatalog(themes: [theme])
        let engine = FakeEngine(onSwitch: { id in catalog.setActiveLibraryID(id) })
        await engine.setStatus(EngineStatus(
            session: "off", port: 9341, injectorAlive: false,
            cdpOk: false, codexRunning: true, themeName: ""
        ))
        let model = AppModel(catalog: catalog, engine: engine, defaults: makeDefaults())

        await model.refresh()
        await model.apply(theme)
        await model.confirmPendingRestartApply()

        let snapshot = await engine.snapshot()
        try expect(snapshot.switchedIDs == ["confirmed"], "confirmation must switch exactly once")
        try expect(model.themes.first(where: { $0.libraryID == "confirmed" })?.isActive == true, "confirmation must verify the target is active")
        try expect(model.recentThemeIDs == ["confirmed"], "confirmation must record the target as recent")
        try expect(model.pendingRestartThemeID == nil, "confirmation must clear restart consent")
    }

    @MainActor
    private static func selectsInactiveThemeWithoutChangingActivity() async throws {
        let active = makeThemeRecord(id: "active", isActive: true)
        let inactive = makeThemeRecord(id: "inactive")
        let model = AppModel(
            catalog: FakeThemeCatalog(themes: [active, inactive]),
            engine: FakeEngine(),
            defaults: makeDefaults()
        )

        await model.refresh()
        model.selectTheme(inactive)

        try expect(model.selectedThemeID == "inactive", "selection must track the inspected theme")
        try expect(model.themes.first(where: \.isActive)?.libraryID == "active", "selection must not change activity")
    }

    @MainActor
    private static func refreshFallsBackWhenSelectedThemeIsRemoved() async throws {
        let active = makeThemeRecord(id: "active", isActive: true)
        let selected = makeThemeRecord(id: "selected")
        let catalog = FakeThemeCatalog(themes: [active, selected])
        let model = AppModel(catalog: catalog, engine: FakeEngine(), defaults: makeDefaults())

        await model.refresh()
        model.selectTheme(selected)
        catalog.themes = [active]
        await model.refresh()

        try expect(model.selectedThemeID == "active", "refresh must fall back to the active theme")
    }

    @MainActor
    private static func ignoresSecondActionWhileBusy() async throws {
        let theme = makeThemeRecord(id: "blocked")
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
    private static func pauseRefreshesStatus() async throws {
        let engine = FakeEngine()
        let expectedStatus = EngineStatus(
            session: "paused", port: 9341, injectorAlive: false,
            cdpOk: false, codexRunning: true, themeName: ""
        )
        await engine.setStatus(expectedStatus)
        let model = AppModel(catalog: FakeThemeCatalog(themes: []), engine: engine, defaults: makeDefaults())

        await model.pauseTheme()

        let snapshot = await engine.snapshot()
        try expect(snapshot.pauseCount == 1, "pause must call the lifecycle command exactly once")
        try expect(model.status == expectedStatus, "pause must refresh engine status")
        try expect(model.operation == .succeeded("主题已暂停"), "pause success message mismatch")
    }

    @MainActor
    private static func restartRefreshesStatus() async throws {
        let engine = FakeEngine()
        let expectedStatus = EngineStatus(
            session: "live", port: 9341, injectorAlive: true,
            cdpOk: true, codexRunning: true, themeName: "Current"
        )
        await engine.setStatus(expectedStatus)
        let model = AppModel(catalog: FakeThemeCatalog(themes: []), engine: engine, defaults: makeDefaults())

        await model.restartTheme()

        let snapshot = await engine.snapshot()
        try expect(snapshot.restartCount == 1, "restart must call the lifecycle command exactly once")
        try expect(model.status == expectedStatus, "restart must refresh engine status")
        try expect(model.operation == .succeeded("Codex 已重新启动并应用主题"), "restart success message mismatch")
    }

    @MainActor
    private static func pauseFailsWhenStatusRefreshFails() async throws {
        let engine = FakeEngine()
        await engine.setStatusFailure(.engine("暂停后状态读取失败"))
        let model = AppModel(catalog: FakeThemeCatalog(themes: []), engine: engine, defaults: makeDefaults())

        await model.pauseTheme()

        let snapshot = await engine.snapshot()
        try expect(snapshot.pauseCount == 1, "pause must execute before the status refresh")
        try expect(model.operation == .failed("暂停后状态读取失败"), "pause must fail when status refresh fails")
    }

    @MainActor
    private static func restartFailsWhenStatusRefreshFails() async throws {
        let engine = FakeEngine()
        await engine.setStatusFailure(.engine("重启后状态读取失败"))
        let model = AppModel(catalog: FakeThemeCatalog(themes: []), engine: engine, defaults: makeDefaults())

        await model.restartTheme()

        let snapshot = await engine.snapshot()
        try expect(snapshot.restartCount == 1, "restart must execute before the status refresh")
        try expect(model.operation == .failed("重启后状态读取失败"), "restart must fail when status refresh fails")
    }

    @MainActor
    private static func busySwitchBlocksPauseAndRestart() async throws {
        let theme = makeThemeRecord(id: "lifecycle-blocked")
        let engine = FakeEngine()
        await engine.setBlockSwitch(true)
        let model = AppModel(
            catalog: FakeThemeCatalog(themes: [theme]),
            engine: engine,
            defaults: makeDefaults()
        )

        let first = Task { @MainActor in await model.apply(theme) }
        await engine.waitForSwitchStart()
        await model.pauseTheme()
        await model.restartTheme()

        let snapshot = await engine.snapshot()
        try expect(snapshot.pauseCount == 0, "pause must be ignored while switching")
        try expect(snapshot.restartCount == 0, "restart must be ignored while switching")
        await engine.releaseSwitch()
        await first.value
    }

    @MainActor
    private static func failuresBecomeActionableState() async throws {
        let theme = makeThemeRecord(id: "failure")
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

    private static func makeDefaults() -> UserDefaults {
        let suite = "CodexSkinManagerTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }
}
