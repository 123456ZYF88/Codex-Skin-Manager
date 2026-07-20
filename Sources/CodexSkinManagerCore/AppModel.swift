import Combine
import Foundation

package enum ManagerOperation: Equatable, Sendable {
    case idle
    case validating
    case switching
    case importing
    case exporting
    case restoring
    case pausing
    case restarting
    case succeeded(String)
    case failed(String)

    package var isBusy: Bool {
        switch self {
        case .validating, .switching, .importing, .exporting, .restoring, .pausing, .restarting: true
        case .idle, .succeeded, .failed: false
        }
    }
}

@MainActor
package final class AppModel: ObservableObject {
    private enum RetryIntent: Equatable, Sendable {
        case apply(String)
        case pause
        case restart
        case restore
        case export(String, URL)
    }

    @Published package private(set) var themes: [ThemeRecord] = []
    @Published package private(set) var status: EngineStatus?
    @Published package private(set) var operation: ManagerOperation = .idle
    @Published package private(set) var recentThemeIDs: [String]
    @Published package private(set) var pendingReplacementURL: URL?
    @Published package private(set) var pendingRestartThemeID: String?
    @Published package private(set) var lastExportURL: URL?
    @Published package var selectedSection: ManagerSection = .dashboard
    @Published package var selectedThemeID: String?
    @Published package var searchText = ""
    @Published package var themeFilter: ThemeFilter = .all
    @Published package var themeSort: ThemeSort = .recent

    private let catalog: any ThemeCatalogReading
    private let engine: any EngineControlling
    private let exporter: any ThemePackageExporting
    private let defaults: UserDefaults
    private let recentThemeKey = "recentThemeLibraryIDs"
    private let deferredImportRoot: URL
    private var retryIntent: RetryIntent?
    private var importGeneration = 0

    package init(
        catalog: any ThemeCatalogReading,
        engine: any EngineControlling,
        exporter: any ThemePackageExporting = ThemePackageExporter(),
        defaults: UserDefaults,
        deferredImportRoot: URL = ThemePackageDeferredStore.defaultRoot()
    ) {
        self.catalog = catalog
        self.engine = engine
        self.exporter = exporter
        self.defaults = defaults
        self.deferredImportRoot = deferredImportRoot
        recentThemeIDs = Array((defaults.stringArray(forKey: recentThemeKey) ?? []).prefix(8))
    }

    package static func live() -> AppModel {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let stateRoot = home
            .appendingPathComponent("Library/Application Support", isDirectory: true)
            .appendingPathComponent("CodexDreamSkinStudio", isDirectory: true)
        let engineRoot = home
            .appendingPathComponent(".codex", isDirectory: true)
            .appendingPathComponent("codex-dream-skin-studio", isDirectory: true)
        return AppModel(
            catalog: ThemeCatalog(stateRoot: stateRoot),
            engine: EngineBridge(engineRoot: engineRoot),
            exporter: ThemePackageExporter(),
            defaults: .standard
        )
    }

    package var recentThemes: [ThemeRecord] {
        recentThemeIDs.compactMap { id in themes.first(where: { $0.libraryID == id }) }
    }

    package var menuBarRecentThemes: [ThemeRecord] {
        Array(recentThemes.prefix(3))
    }

    package var visibleThemes: [ThemeRecord] {
        let effectiveFilter: ThemeFilter = selectedSection == .recent ? .recent : themeFilter
        return ThemeLibraryQuery(searchText: searchText, filter: effectiveFilter, sort: themeSort)
            .filtered(themes: themes, recentIDs: recentThemeIDs)
    }

    package var selectedTheme: ThemeRecord? {
        guard let selectedThemeID else { return nil }
        return themes.first { $0.libraryID == selectedThemeID }
    }

    package var retryAvailable: Bool {
        guard !operation.isBusy, let retryIntent else { return false }
        guard retryTargetExists(for: retryIntent) else {
            self.retryIntent = nil
            return false
        }
        return true
    }

    package func selectTheme(_ theme: ThemeRecord?) {
        selectedThemeID = theme?.libraryID
    }

    package func retryLastAction() async {
        guard !operation.isBusy, let retryIntent else { return }
        switch retryIntent {
        case .apply(let id):
            guard let theme = themes.first(where: { $0.libraryID == id }) else {
                self.retryIntent = nil
                return
            }
            await performApply(theme)
        case .pause:
            await pauseTheme()
        case .restart:
            await restartTheme()
        case .restore:
            await restoreOriginal()
        case .export(let id, let destination):
            guard let theme = themes.first(where: { $0.libraryID == id }) else {
                self.retryIntent = nil
                return
            }
            await performExport(theme, to: destination)
        }
    }

    package func refresh() async {
        guard !operation.isBusy else { return }
        do {
            try await reloadState()
        } catch {
            operation = .failed(message(for: error))
        }
    }

    package func apply(_ theme: ThemeRecord) async {
        guard !operation.isBusy else { return }
        let current = (try? await engine.status()) ?? status
        status = current
        if current?.codexRunning == true && current?.cdpOk != true {
            pendingRestartThemeID = theme.libraryID
            operation = .idle
            return
        }
        await performApply(theme)
    }

    package func confirmPendingRestartApply() async {
        guard !operation.isBusy,
              let id = pendingRestartThemeID,
              let theme = themes.first(where: { $0.libraryID == id })
        else { return }
        pendingRestartThemeID = nil
        await performApply(theme)
    }

    package func cancelPendingRestartApply() {
        guard !operation.isBusy else { return }
        pendingRestartThemeID = nil
    }

    private func performApply(_ theme: ThemeRecord) async {
        retryIntent = .apply(theme.libraryID)
        operation = .switching
        do {
            try await engine.switchTheme(libraryID: theme.libraryID)
            try await reloadState()
            guard status?.injectorAlive == true,
                  status?.cdpOk == true,
                  themes.first(where: { $0.libraryID == theme.libraryID })?.isActive == true
            else {
                throw ManagerError.invalidResponse("主题切换完成，但未验证到目标主题。")
            }
            recordRecent(theme.libraryID)
            selectedThemeID = theme.libraryID
            retryIntent = nil
            operation = .succeeded("已应用 \(theme.manifest.name)")
        } catch {
            operation = .failed(message(for: error))
        }
    }

    package func beginImport(_ packageURL: URL) -> Bool {
        guard !operation.isBusy else { return false }
        let scoped = packageURL.startAccessingSecurityScopedResource()
        guard ThemePackageDeferredStore.isRegularPackage(packageURL) else {
            if scoped { packageURL.stopAccessingSecurityScopedResource() }
            return false
        }
        // Imports cannot be retried safely after the caller's security scope ends.
        retryIntent = nil
        discardPendingReplacement()
        importGeneration &+= 1
        let generation = importGeneration
        operation = .validating
        Task { [self] in
            await completeImport(packageURL, generation: generation, scoped: scoped)
        }
        return true
    }

    package func importPackage(_ packageURL: URL) async -> Bool {
        guard beginImport(packageURL) else { return false }
        while operation.isBusy { await Task.yield() }
        return pendingReplacementURL != nil
    }

    package func exportSelectedTheme(to destination: URL) async {
        guard !operation.isBusy, let theme = selectedTheme else { return }
        await performExport(theme, to: destination)
    }

    private func performExport(_ theme: ThemeRecord, to destination: URL) async {
        retryIntent = .export(theme.libraryID, destination)
        operation = .exporting
        do {
            let output = try await exporter.export(theme: theme, to: destination)
            // Publish success only after the engine has independently accepted the archive.
            try await engine.validateThemePackage(packageURL: output)
            lastExportURL = output
            retryIntent = nil
            operation = .succeeded("已导出 \(theme.manifest.name)")
        } catch {
            operation = .failed(message(for: error))
        }
    }

    package func replacePendingImport() async {
        guard !operation.isBusy, let packageURL = pendingReplacementURL else { return }
        pendingReplacementURL = nil
        defer { try? FileManager.default.removeItem(at: packageURL) }
        _ = await performImport(packageURL, replace: true)
    }

    package func cancelPendingImport() {
        guard !operation.isBusy else { return }
        discardPendingReplacement()
    }

    package func restoreOriginal() async {
        guard !operation.isBusy else { return }
        retryIntent = .restore
        operation = .restoring
        do {
            try await engine.restoreOriginal()
            try await reloadState()
            retryIntent = nil
            operation = .succeeded("已恢复 Codex 原版界面")
        } catch {
            operation = .failed(message(for: error))
        }
    }

    package func pauseTheme() async {
        guard !operation.isBusy else { return }
        retryIntent = .pause
        operation = .pausing
        do {
            try await engine.pauseTheme()
            try await reloadState(requiringStatus: true)
            retryIntent = nil
            operation = .succeeded("主题已暂停")
        } catch {
            operation = .failed(message(for: error))
        }
    }

    package func restartTheme() async {
        guard !operation.isBusy else { return }
        retryIntent = .restart
        operation = .restarting
        do {
            try await engine.restartTheme()
            try await reloadState(requiringStatus: true)
            retryIntent = nil
            operation = .succeeded("Codex 已重新启动并应用主题")
        } catch {
            operation = .failed(message(for: error))
        }
    }

    private func completeImport(_ packageURL: URL, generation: Int, scoped: Bool) async {
        defer { if scoped { packageURL.stopAccessingSecurityScopedResource() } }
        guard generation == importGeneration else { return }
        operation = .importing
        do {
            let result = try await engine.importTheme(packageURL: packageURL, replace: false)
            guard generation == importGeneration else { return }
            try await reloadState()
            guard generation == importGeneration else { return }
            operation = .succeeded("已导入 \(result.themeName)")
        } catch ManagerError.themeAlreadyExists {
            guard generation == importGeneration else { return }
            do {
                let staged = try ThemePackageDeferredStore.stage(packageURL, root: deferredImportRoot)
                guard generation == importGeneration else {
                    try? FileManager.default.removeItem(at: staged)
                    return
                }
                pendingReplacementURL = staged
                operation = .idle
            } catch {
                operation = .failed(message(for: error))
            }
        } catch {
            if generation == importGeneration {
                operation = .failed(message(for: error))
            }
        }
    }

    private func performImport(_ packageURL: URL, replace: Bool) async -> Bool {
        operation = .importing
        do {
            let result = try await engine.importTheme(packageURL: packageURL, replace: replace)
            try await reloadState()
            operation = .succeeded("已导入 \(result.themeName)")
            return false
        } catch ManagerError.themeAlreadyExists {
            operation = .idle
            return true
        } catch {
            operation = .failed(message(for: error))
            return false
        }
    }

    private func retryTargetExists(for retryIntent: RetryIntent) -> Bool {
        switch retryIntent {
        case .apply(let id), .export(let id, _):
            themes.contains(where: { $0.libraryID == id })
        case .pause, .restart, .restore:
            true
        }
    }

    private func discardPendingReplacement() {
        guard let packageURL = pendingReplacementURL else { return }
        pendingReplacementURL = nil
        try? FileManager.default.removeItem(at: packageURL)
    }

    private func reloadState(requiringStatus: Bool = false) async throws {
        themes = try catalog.loadThemes()
        if requiringStatus {
            status = try await engine.status()
        } else {
            status = try? await engine.status()
        }
        pruneRecentThemes()
        let available = Set(themes.map(\.libraryID))
        if let selectedThemeID, available.contains(selectedThemeID) {
            // Preserve the user's inspected theme even when it is not active.
        } else {
            selectedThemeID = themes.first(where: \.isActive)?.libraryID ?? themes.first?.libraryID
        }
    }

    private func recordRecent(_ libraryID: String) {
        let available = Set(themes.map(\.libraryID))
        var ids = [libraryID] + recentThemeIDs.filter { $0 != libraryID }
        ids = ids.filter { available.contains($0) }
        recentThemeIDs = Array(ids.prefix(8))
        defaults.set(recentThemeIDs, forKey: recentThemeKey)
    }

    private func pruneRecentThemes() {
        let available = Set(themes.map(\.libraryID))
        let filtered = Array(recentThemeIDs.filter { available.contains($0) }.prefix(8))
        if filtered != recentThemeIDs {
            recentThemeIDs = filtered
            defaults.set(filtered, forKey: recentThemeKey)
        }
    }

    private func message(for error: Error) -> String {
        if let localized = error as? LocalizedError,
           let message = localized.errorDescription,
           !message.isEmpty {
            return message
        }
        let message = error.localizedDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        return message.isEmpty ? "操作失败，请检查 Dream Skin 引擎。" : String(message.prefix(500))
    }
}
