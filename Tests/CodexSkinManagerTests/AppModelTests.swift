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

final class PostCopyFailureFileOperations: ThemePackageFileOperating, @unchecked Sendable {
    enum Failure: Error { case hardening }

    private let base = POSIXThemePackageFileOperations()
    private(set) var partialDestination: URL?
    private(set) var removedPartialCopy = false

    func itemExists(at url: URL) -> Bool { base.itemExists(at: url) }
    func isDirectory(at url: URL) -> Bool { base.isDirectory(at: url) }
    func isSymbolicLink(at url: URL) throws -> Bool { try base.isSymbolicLink(at: url) }
    func isRegularFile(at url: URL) throws -> Bool { try base.isRegularFile(at: url) }
    func createDirectory(at url: URL, permissions: Int) throws { try base.createDirectory(at: url, permissions: permissions) }
    func permissions(at url: URL) throws -> Int { try base.permissions(at: url) }
    func copyItem(at source: URL, to destination: URL) throws {
        try base.copyItem(at: source, to: destination)
        partialDestination = destination
    }
    func setPermissions(_ permissions: Int, at url: URL) throws {
        if url == partialDestination { throw Failure.hardening }
        try base.setPermissions(permissions, at: url)
    }
    func removeItem(at url: URL) throws {
        if url == partialDestination { removedPartialCopy = true }
        try base.removeItem(at: url)
    }
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
    var importFailure: ManagerError?
    var restoreFailure: ManagerError?
    var statusFailure: ManagerError?
    var validationFailure: ManagerError?
    var blockSwitch = false
    var blockImport = false
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
    private var importStarted = false
    private var importWaiters: [CheckedContinuation<Void, Never>] = []
    private var importRelease: CheckedContinuation<Void, Never>?

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
        importStarted = true
        importWaiters.forEach { $0.resume() }
        importWaiters.removeAll()
        if blockImport { await withCheckedContinuation { importRelease = $0 } }
        if let importFailure { throw importFailure }
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
        if let restoreFailure { throw restoreFailure }
    }

    func pauseTheme() async throws {
        pauseCount += 1
    }

    func restartTheme() async throws {
        restartCount += 1
    }

    func setDuplicateOnNormalImport(_ value: Bool) { duplicateOnNormalImport = value }
    func setSwitchFailure(_ error: ManagerError?) { switchFailure = error }
    func setImportFailure(_ error: ManagerError?) { importFailure = error }
    func setRestoreFailure(_ error: ManagerError?) { restoreFailure = error }
    func setStatusFailure(_ error: ManagerError?) { statusFailure = error }
    func setValidationFailure(_ error: ManagerError?) { validationFailure = error }
    func setBlockSwitch(_ value: Bool) { blockSwitch = value }
    func setBlockImport(_ value: Bool) { blockImport = value }
    func setStatus(_ status: EngineStatus) { engineStatus = status }

    func waitForSwitchStart() async {
        if switchStarted { return }
        await withCheckedContinuation { startWaiters.append($0) }
    }

    func releaseSwitch() {
        switchRelease?.resume()
        switchRelease = nil
    }

    func waitForImportStart() async {
        if importStarted { return }
        await withCheckedContinuation { importWaiters.append($0) }
    }

    func releaseImport() {
        importRelease?.resume()
        importRelease = nil
    }

    func snapshot() -> (
        switchedIDs: [String],
        importURLs: [URL],
        importReplaceFlags: [Bool],
        validatedPackages: [URL],
        restoreCount: Int,
        pauseCount: Int,
        restartCount: Int
    ) {
        (switchedIDs, imports.map(\.0), imports.map(\.1), validatedPackages, restoreCount, pauseCount, restartCount)
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
        try await failedApplyRetriesTheSameThemeAndClearsIntentOnSuccess()
        try await failedPauseRetriesTheTypedLifecycleAction()
        try await failedRestoreStoresRetryIntent()
        try await failedImportDoesNotRetryStaleSecurityScopedURL()
        try await failedImportRetiresEarlierRetryIntent()
        try await retryIsUnavailableWhenItsThemeIsRemoved()
        try await exportRetrySurvivesSelectionChange()
        try await exportRetryIsUnavailableWhenItsThemeIsRemoved()
        try deferredReplacementStagingRejectsSymlinksAndPreservesAPrivateCopy()
        try await deferredReplacementUsesThePrivateCopyAndCleansItUp()
        try await pendingReplacementIsCleanedOnCancelAndNextImport()
        try safeExportNameSanitizesPrimaryAndFallbackNames()
        try deferredStoreCorrectsAnExistingWorldReadableRoot()
        try deferredStoreRemovesPartialCopyWhenPostCopyHardeningFails()
        try await importReservationRejectsBusyDrops()
        try await importTransactionRetainsModelUntilScopeCompletes()
        print("PASS: AppModelTests")
    }

    @MainActor
    private static func failedApplyRetriesTheSameThemeAndClearsIntentOnSuccess() async throws {
        let theme = makeThemeRecord(id: "retry-target", name: "Retry Target")
        let catalog = FakeThemeCatalog(themes: [theme])
        let engine = FakeEngine(onSwitch: { id in catalog.setActiveLibraryID(id) })
        await engine.setSwitchFailure(.engine("切换失败"))
        let model = AppModel(
            catalog: catalog,
            engine: engine,
            defaults: makeDefaults()
        )

        await model.refresh()
        await model.apply(theme)

        try expect(model.operation == .failed("切换失败"), "fixture must enter the failed state")
        try expect(model.retryAvailable, "failed apply must retain a typed retry intent")
        await engine.setSwitchFailure(nil)
        await model.retryLastAction()

        let snapshot = await engine.snapshot()
        try expect(snapshot.switchedIDs == ["retry-target", "retry-target"], "retry must switch the original library ID")
        try expect(!model.retryAvailable, "verified success must clear the retry intent")
    }

    @MainActor
    private static func failedPauseRetriesTheTypedLifecycleAction() async throws {
        let engine = FakeEngine()
        await engine.setStatusFailure(.engine("暂停后状态读取失败"))
        let model = AppModel(catalog: FakeThemeCatalog(themes: []), engine: engine, defaults: makeDefaults())

        await model.pauseTheme()

        try expect(model.retryAvailable, "failed pause must retain a typed pause retry intent")
        await engine.setStatusFailure(nil)
        await model.retryLastAction()

        let snapshot = await engine.snapshot()
        try expect(snapshot.pauseCount == 2, "retry must execute pause again")
        try expect(model.operation == .succeeded("主题已暂停"), "successful pause retry must complete")
    }

    @MainActor
    private static func failedRestoreStoresRetryIntent() async throws {
        let engine = FakeEngine()
        await engine.setRestoreFailure(.engine("恢复失败"))
        let model = AppModel(catalog: FakeThemeCatalog(themes: []), engine: engine, defaults: makeDefaults())

        await model.restoreOriginal()

        try expect(model.operation == .failed("恢复失败"), "restore failure must stay visible")
        try expect(model.retryAvailable, "restore failure must retain a typed restore retry intent")
    }

    @MainActor
    private static func failedImportDoesNotRetryStaleSecurityScopedURL() async throws {
        let temporary = try makeTemporaryDirectory(prefix: "stale-import")
        defer { try? FileManager.default.removeItem(at: temporary) }
        let packageURL = temporary.appendingPathComponent("stale-scope.codexskin")
        try Data("theme".utf8).write(to: packageURL)
        let engine = FakeEngine()
        await engine.setImportFailure(.engine("主题包验证失败"))
        let model = AppModel(catalog: FakeThemeCatalog(themes: []), engine: engine, defaults: makeDefaults())

        _ = await model.importPackage(packageURL)

        try expect(model.operation == .failed("主题包验证失败"), "import validation failure must stay visible")
        try expect(!model.retryAvailable, "import must not retain a security-scoped URL for retry")
        await model.retryLastAction()
        let snapshot = await engine.snapshot()
        try expect(snapshot.importReplaceFlags == [false], "retry must never reuse a stale import URL")
    }

    @MainActor
    private static func failedImportRetiresEarlierRetryIntent() async throws {
        let temporary = try makeTemporaryDirectory(prefix: "retry-import")
        defer { try? FileManager.default.removeItem(at: temporary) }
        let packageURL = temporary.appendingPathComponent("import-clears-retry.codexskin")
        try Data("theme".utf8).write(to: packageURL)
        let theme = makeThemeRecord(id: "earlier-retry")
        let catalog = FakeThemeCatalog(themes: [theme])
        let engine = FakeEngine(onSwitch: { id in catalog.setActiveLibraryID(id) })
        await engine.setSwitchFailure(.engine("切换失败"))
        let model = AppModel(catalog: catalog, engine: engine, defaults: makeDefaults())
        await model.refresh()
        await model.apply(theme)
        try expect(model.retryAvailable, "fixture must retain an earlier retryable action")

        await engine.setImportFailure(.engine("主题包验证失败"))
        _ = await model.importPackage(packageURL)

        try expect(!model.retryAvailable, "a non-retryable import must retire any earlier retry intent")
        await model.retryLastAction()
        let snapshot = await engine.snapshot()
        try expect(snapshot.switchedIDs == ["earlier-retry"], "import failure must not retry an earlier action")
    }

    @MainActor
    private static func retryIsUnavailableWhenItsThemeIsRemoved() async throws {
        let theme = makeThemeRecord(id: "removed-retry")
        let catalog = FakeThemeCatalog(themes: [theme])
        let engine = FakeEngine()
        await engine.setSwitchFailure(.engine("切换失败"))
        let model = AppModel(catalog: catalog, engine: engine, defaults: makeDefaults())
        await model.refresh()
        await model.apply(theme)
        catalog.themes = []
        await model.refresh()

        try expect(!model.retryAvailable, "retry must retire an apply intent whose target disappeared")
        await model.retryLastAction()
        let snapshot = await engine.snapshot()
        try expect(snapshot.switchedIDs == ["removed-retry"], "removed retry targets must not execute")
    }

    @MainActor
    private static func exportRetrySurvivesSelectionChange() async throws {
        let original = makeThemeRecord(id: "export-original")
        let selectedLater = makeThemeRecord(id: "export-later")
        let engine = FakeEngine()
        let exporter = FakeThemePackageExporter()
        let model = AppModel(
            catalog: FakeThemeCatalog(themes: [original, selectedLater]),
            engine: engine,
            exporter: exporter,
            defaults: makeDefaults()
        )
        await model.refresh()
        await engine.setValidationFailure(.engine("导出验证失败"))
        let destination = URL(fileURLWithPath: "/tmp/export-original.codexskin")
        await model.exportSelectedTheme(to: destination)
        model.selectTheme(selectedLater)
        await engine.setValidationFailure(nil)

        try expect(model.retryAvailable, "selection changes must not invalidate a still-installed export target")
        await model.retryLastAction()
        let exports = await exporter.snapshot()
        try expect(exports.map(\.themeID) == ["export-original", "export-original"], "retry must export the stored target, not the new selection")
    }

    @MainActor
    private static func exportRetryIsUnavailableWhenItsThemeIsRemoved() async throws {
        let theme = makeThemeRecord(id: "export-removed")
        let catalog = FakeThemeCatalog(themes: [theme])
        let engine = FakeEngine()
        let exporter = FakeThemePackageExporter()
        let model = AppModel(catalog: catalog, engine: engine, exporter: exporter, defaults: makeDefaults())
        await model.refresh()
        await engine.setValidationFailure(.engine("导出验证失败"))
        await model.exportSelectedTheme(to: URL(fileURLWithPath: "/tmp/export-removed.codexskin"))
        catalog.themes = []
        await model.refresh()

        try expect(!model.retryAvailable, "retry must retire an export intent whose target disappeared")
        await model.retryLastAction()
        let exports = await exporter.snapshot()
        try expect(exports.count == 1, "removed export targets must not execute")
    }

    private static func deferredReplacementStagingRejectsSymlinksAndPreservesAPrivateCopy() throws {
        let temporary = try makeTemporaryDirectory(prefix: "deferred-store")
        defer { try? FileManager.default.removeItem(at: temporary) }
        let source = temporary.appendingPathComponent("source.codexskin")
        let symlink = temporary.appendingPathComponent("linked.codexskin")
        let storeRoot = temporary.appendingPathComponent("private-store", isDirectory: true)
        try Data("theme".utf8).write(to: source)
        try FileManager.default.createSymbolicLink(at: symlink, withDestinationURL: source)

        try expect(ThemePackageDeferredStore.isRegularPackage(source), "a regular .codexskin file must be accepted")
        try expect(!ThemePackageDeferredStore.isRegularPackage(symlink), "symlinked theme packages must be rejected")
        let staged = try ThemePackageDeferredStore.stage(source, root: storeRoot)
        try FileManager.default.removeItem(at: source)

        try expect(staged.deletingLastPathComponent() == storeRoot, "deferred replacements must use the app-owned store")
        let stagedData = try Data(contentsOf: staged)
        try expect(stagedData == Data("theme".utf8), "the staged copy must survive after the original URL is gone")
        let attributes = try FileManager.default.attributesOfItem(atPath: staged.path)
        try expect(attributes[FileAttributeKey.posixPermissions] as? Int == 0o600, "staged packages must be private to the current user")
        let directoryAttributes = try FileManager.default.attributesOfItem(atPath: storeRoot.path)
        try expect(directoryAttributes[FileAttributeKey.posixPermissions] as? Int == 0o700, "the private staging directory must not be group-readable")
    }

    @MainActor
    private static func deferredReplacementUsesThePrivateCopyAndCleansItUp() async throws {
        let temporary = try makeTemporaryDirectory(prefix: "deferred-replace")
        defer { try? FileManager.default.removeItem(at: temporary) }
        let source = temporary.appendingPathComponent("duplicate.codexskin")
        let storeRoot = temporary.appendingPathComponent("private-store", isDirectory: true)
        try Data("replacement".utf8).write(to: source)

        let engine = FakeEngine()
        await engine.setDuplicateOnNormalImport(true)
        let model = AppModel(catalog: FakeThemeCatalog(themes: []), engine: engine, defaults: makeDefaults(), deferredImportRoot: storeRoot)
        let requiresReplacement = await model.importPackage(source)
        try expect(requiresReplacement, "duplicate import must request deferred replacement staging")
        let staged = try unwrap(model.pendingReplacementURL, "duplicate import must commit a staged package")
        try FileManager.default.removeItem(at: source)
        await engine.setDuplicateOnNormalImport(false)

        await model.replacePendingImport()

        let snapshot = await engine.snapshot()
        try expect(snapshot.importURLs == [source, staged], "replacement must use the app-owned staged file after the original disappears")
        try expect(!FileManager.default.fileExists(atPath: staged.path), "staged package must be removed after replacement")
    }

    @MainActor
    private static func pendingReplacementIsCleanedOnCancelAndNextImport() async throws {
        let temporary = try makeTemporaryDirectory(prefix: "deferred-cleanup")
        defer { try? FileManager.default.removeItem(at: temporary) }
        let first = temporary.appendingPathComponent("first.codexskin")
        let second = temporary.appendingPathComponent("second.codexskin")
        let third = temporary.appendingPathComponent("third.codexskin")
        try Data("first".utf8).write(to: first)
        try Data("second".utf8).write(to: second)
        try Data("third".utf8).write(to: third)
        let root = temporary.appendingPathComponent("store", isDirectory: true)
        let engine = FakeEngine()
        await engine.setDuplicateOnNormalImport(true)
        let model = AppModel(catalog: FakeThemeCatalog(themes: []), engine: engine, defaults: makeDefaults(), deferredImportRoot: root)

        _ = await model.importPackage(first)
        let firstStaged = try unwrap(model.pendingReplacementURL, "first duplicate must stage")
        model.cancelPendingImport()
        try expect(!FileManager.default.fileExists(atPath: firstStaged.path), "cancel must remove a staged replacement")

        _ = await model.importPackage(second)
        let secondStaged = try unwrap(model.pendingReplacementURL, "second duplicate must stage")
        await engine.setDuplicateOnNormalImport(false)
        _ = await model.importPackage(third)
        try expect(!FileManager.default.fileExists(atPath: secondStaged.path), "a new import must remove the previous staged replacement")
    }

    private static func safeExportNameSanitizesPrimaryAndFallbackNames() throws {
        try expect(ThemeExportName.safeExportName("  Blue / Armor!!! ", fallback: "ignored") == "Blue-Armor", "invalid name runs must collapse to one separator")
        try expect(ThemeExportName.safeExportName("蓝色 主题", fallback: "ignored") == "蓝色-主题", "Unicode letters must be retained")
        try expect(ThemeExportName.safeExportName("///", fallback: " id / ") == "id", "fallback must be sanitized too")
        try expect(ThemeExportName.safeExportName("", fallback: " ... ") == "Theme", "empty sanitized names must use a fixed safe fallback")
    }

    private static func deferredStoreCorrectsAnExistingWorldReadableRoot() throws {
        let temporary = try makeTemporaryDirectory(prefix: "deferred-permissions")
        defer { try? FileManager.default.removeItem(at: temporary) }
        let source = temporary.appendingPathComponent("source.codexskin")
        let root = temporary.appendingPathComponent("existing-store", isDirectory: true)
        try Data("theme".utf8).write(to: source)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        try FileManager.default.setAttributes([.posixPermissions: 0o777], ofItemAtPath: root.path)

        _ = try ThemePackageDeferredStore.stage(source, root: root)

        let attributes = try FileManager.default.attributesOfItem(atPath: root.path)
        try expect(attributes[FileAttributeKey.posixPermissions] as? Int == 0o700, "an existing staging root must be chmodded and verified as 0700")
    }

    private static func deferredStoreRemovesPartialCopyWhenPostCopyHardeningFails() throws {
        let temporary = try makeTemporaryDirectory(prefix: "deferred-partial")
        defer { try? FileManager.default.removeItem(at: temporary) }
        let source = temporary.appendingPathComponent("source.codexskin")
        let root = temporary.appendingPathComponent("store", isDirectory: true)
        try Data("theme".utf8).write(to: source)
        let operations = PostCopyFailureFileOperations()

        do {
            _ = try ThemePackageDeferredStore.stage(source, root: root, operations: operations)
            throw TestFailure(description: "post-copy hardening failure must reject staging")
        } catch is PostCopyFailureFileOperations.Failure {}

        try expect(operations.partialDestination != nil, "fixture must copy a destination before failing")
        try expect(operations.removedPartialCopy, "failed post-copy hardening must remove the partial destination")
    }

    @MainActor
    private static func importReservationRejectsBusyDrops() async throws {
        let temporary = try makeTemporaryDirectory(prefix: "busy-drop")
        defer { try? FileManager.default.removeItem(at: temporary) }
        let first = temporary.appendingPathComponent("first.codexskin")
        let second = temporary.appendingPathComponent("second.codexskin")
        try Data("first".utf8).write(to: first)
        try Data("second".utf8).write(to: second)
        let model = AppModel(catalog: FakeThemeCatalog(themes: []), engine: FakeEngine(), defaults: makeDefaults())

        try expect(model.beginImport(first), "a regular package must reserve import synchronously")
        try expect(!model.beginImport(second), "a drop arriving while reserved must be rejected synchronously")
        while model.operation.isBusy { await Task.yield() }
    }

    @MainActor
    private static func importTransactionRetainsModelUntilScopeCompletes() async throws {
        let temporary = try makeTemporaryDirectory(prefix: "import-lifetime")
        defer { try? FileManager.default.removeItem(at: temporary) }
        let packageURL = temporary.appendingPathComponent("theme.codexskin")
        try Data("theme".utf8).write(to: packageURL)
        let engine = FakeEngine()
        await engine.setBlockImport(true)
        var model: AppModel? = AppModel(catalog: FakeThemeCatalog(themes: []), engine: engine, defaults: makeDefaults())
        let weakModel = WeakReference(model)
        try expect(model?.beginImport(packageURL) == true, "transaction must reserve")
        await engine.waitForImportStart()
        model = nil
        try expect(weakModel.value != nil, "the active import transaction must retain its model and scope lease")
        await engine.releaseImport()
        for _ in 0..<100 where weakModel.value != nil { await Task.yield() }
        try expect(weakModel.value == nil, "model must release after the transaction and scope lease complete")
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
        try expect(model.retryAvailable, "failed export must retain a typed export retry intent")
        await engine.setValidationFailure(nil)
        await model.retryLastAction()
        let retriedExports = await exporter.snapshot()
        try expect(retriedExports.map(\.destination) == [prior, rejected, rejected], "retry must export to the original destination")
        try expect(!model.retryAvailable, "verified export retry must clear its intent")
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
        let temporary = try makeTemporaryDirectory(prefix: "duplicate-prompt")
        defer { try? FileManager.default.removeItem(at: temporary) }
        let packageURL = temporary.appendingPathComponent("duplicate.codexskin")
        try Data("duplicate".utf8).write(to: packageURL)
        let engine = FakeEngine()
        await engine.setDuplicateOnNormalImport(true)
        let model = AppModel(catalog: FakeThemeCatalog(themes: []), engine: engine, defaults: makeDefaults(), deferredImportRoot: temporary.appendingPathComponent("store", isDirectory: true))

        let requiresReplacement = await model.importPackage(packageURL)
        try expect(requiresReplacement, "duplicate import must request an explicit staged replacement")
        try expect(model.pendingReplacementURL != packageURL, "staged replacement must not retain the scoped source URL")
        try expect(model.operation == .idle, "duplicate prompt must return to an actionable state")
        await model.replacePendingImport()

        let snapshot = await engine.snapshot()
        try expect(snapshot.importReplaceFlags == [false, true], "replacement must be explicit")
        try expect(model.pendingReplacementURL == nil, "replacement prompt must clear after use")
    }

    @MainActor
    private static func duplicateImportCanBeCancelled() async throws {
        let temporary = try makeTemporaryDirectory(prefix: "duplicate-cancel")
        defer { try? FileManager.default.removeItem(at: temporary) }
        let packageURL = temporary.appendingPathComponent("cancel.codexskin")
        let stagingRoot = temporary.appendingPathComponent("store", isDirectory: true)
        try Data("duplicate".utf8).write(to: packageURL)
        let engine = FakeEngine()
        await engine.setDuplicateOnNormalImport(true)
        let model = AppModel(
            catalog: FakeThemeCatalog(themes: []),
            engine: engine,
            defaults: makeDefaults(),
            deferredImportRoot: stagingRoot
        )

        let duplicate = await model.importPackage(packageURL)
        try expect(duplicate, "a real duplicate package must create a cancellation prompt")
        let staged = try unwrap(model.pendingReplacementURL, "duplicate package must be staged before cancellation")
        model.cancelPendingImport()

        try expect(model.pendingReplacementURL == nil, "cancel must clear the duplicate prompt")
        try expect(!FileManager.default.fileExists(atPath: staged.path), "cancel must delete the staged package")
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
