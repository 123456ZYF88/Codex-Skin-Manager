import Combine
import Foundation

package enum ManagerCommand: Equatable, Sendable {
    case importTheme
    case exportTheme
    case applySelected
    case restoreOriginal
    case refresh
    case focusSearch
}

package enum ManagerOperation: Equatable, Sendable {
    case idle
    case preflighting
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
        case .preflighting, .validating, .switching, .importing, .exporting, .restoring, .pausing, .restarting: true
        case .idle, .succeeded, .failed: false
        }
    }
}

@MainActor
package final class AppModel: ObservableObject {
    private enum ApplyScope: Equatable, Sendable {
        case mainWindow
        case menuBar
    }

    private enum RetryIntent: Equatable, Sendable {
        case apply(String, ApplyScope)
        case pause
        case restart
        case restore
        case export(String, URL)
    }

    @Published package private(set) var themes: [ThemeRecord] = []
    @Published package private(set) var status: EngineStatus?
    @Published package private(set) var operation: ManagerOperation = .idle
    @Published package private(set) var recentThemeIDs: [String]
    @Published package private(set) var pendingReplacement: PendingThemeReplacement?
    @Published package private(set) var pendingRestartThemeID: String?
    @Published package private(set) var lastExportURL: URL?
    @Published package private(set) var commandRequest: (command: ManagerCommand, nonce: UUID)?
    @Published package var selectedSection: ManagerSection = .dashboard {
        didSet { reconcileVisibleSelection() }
    }
    @Published package var selectedThemeID: String?
    @Published package var searchText = "" {
        didSet { reconcileVisibleSelection() }
    }
    @Published package var themeFilter: ThemeFilter = .all {
        didSet { reconcileVisibleSelection() }
    }
    @Published package var themeSort: ThemeSort = .recent {
        didSet { reconcileVisibleSelection() }
    }

    private let catalog: any ThemeCatalogReading
    private let engine: any EngineControlling
    private let exporter: any ThemePackageExporting
    private let defaults: UserDefaults
    private let recentThemeKey = "recentThemeLibraryIDs"
    private let deferredImportRoot: URL
    private var retryIntent: RetryIntent?
    private var pendingRestartApplyScope: ApplyScope?
    private var importGeneration = 0
    private var consumedCommandNonce: UUID?

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
        let storedRecentIDs = defaults.stringArray(forKey: recentThemeKey) ?? []
        let normalizedRecentIDs = Array(Self.deduplicatedRecentIDs(storedRecentIDs).prefix(8))
        recentThemeIDs = normalizedRecentIDs
        if storedRecentIDs != normalizedRecentIDs {
            defaults.set(normalizedRecentIDs, forKey: recentThemeKey)
        }
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

    package var pendingReplacementURL: URL? { pendingReplacement?.packageURL }

    package var pendingReplacementConfirmationText: String? {
        guard let pendingReplacement else { return nil }
        return "即将用“\(pendingReplacement.incomingName)”（ID: \(pendingReplacement.incomingID)）替换已安装的“\(pendingReplacement.existingName)”（ID: \(pendingReplacement.existingID)）。替换后不会自动应用。"
    }

    package var menuBarRecentThemes: [ThemeRecord] {
        Array(recentThemes.filter { !$0.isActive }.prefix(3))
    }

    package var visibleThemes: [ThemeRecord] {
        let effectiveFilter: ThemeFilter = selectedSection == .recent ? .recent : themeFilter
        return ThemeLibraryQuery(searchText: searchText, filter: effectiveFilter, sort: themeSort)
            .filtered(themes: themes, recentIDs: recentThemeIDs)
    }

    package var selectedTheme: ThemeRecord? {
        guard let selectedThemeID else { return nil }
        if selectedSection == .library || selectedSection == .recent {
            return visibleThemes.first { $0.libraryID == selectedThemeID }
        }
        return themes.first { $0.libraryID == selectedThemeID }
    }

    package var retryAvailable: Bool {
        guard !operation.isBusy, let retryIntent else { return false }
        return retryTargetExists(for: retryIntent)
    }

    package func selectTheme(_ theme: ThemeRecord?) {
        if let theme, !visibleThemes.contains(where: { $0.libraryID == theme.libraryID }) { return }
        selectedThemeID = theme?.libraryID
    }

    package func request(_ command: ManagerCommand) {
        commandRequest = (command, UUID())
    }

    package func consumeCommandRequest(nonce: UUID?) -> ManagerCommand? {
        guard let request = commandRequest,
              request.nonce == nonce,
              consumedCommandNonce != request.nonce
        else { return nil }
        // The model is shared by every window, so claiming here prevents duplicate native panels.
        consumedCommandNonce = request.nonce
        return request.command
    }

    package func retryLastAction() async {
        guard !operation.isBusy, let retryIntent else { return }
        switch retryIntent {
        case .apply(let id, let scope):
            guard let theme = themes.first(where: { $0.libraryID == id }) else {
                self.retryIntent = nil
                return
            }
            await performApply(theme, scope: scope)
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

    package func applySelectedTheme() async {
        guard let theme = selectedTheme else { return }
        await applyResolvedTheme(theme, scope: .mainWindow)
    }

    package func applyMenuBarRecentTheme(_ theme: ThemeRecord) async {
        guard menuBarRecentThemes.contains(where: { $0.libraryID == theme.libraryID }) else { return }
        await applyResolvedTheme(theme, scope: .menuBar)
    }

    private func applyResolvedTheme(_ theme: ThemeRecord, scope: ApplyScope) async {
        guard !operation.isBusy else { return }
        operation = .preflighting
        let current = (try? await engine.status()) ?? status
        status = current
        if current?.codexRunning == true && current?.cdpOk != true {
            pendingRestartThemeID = theme.libraryID
            pendingRestartApplyScope = scope
            operation = .idle
            return
        }
        await performApply(theme, scope: scope)
    }

    package func confirmPendingRestartApply() async {
        guard !operation.isBusy,
              let id = pendingRestartThemeID,
              let theme = themes.first(where: { $0.libraryID == id })
        else { return }
        let scope = pendingRestartApplyScope ?? .mainWindow
        pendingRestartThemeID = nil
        pendingRestartApplyScope = nil
        await performApply(theme, scope: scope)
    }

    package func cancelPendingRestartApply() {
        guard !operation.isBusy else { return }
        pendingRestartThemeID = nil
        pendingRestartApplyScope = nil
    }

    private func performApply(_ theme: ThemeRecord, scope: ApplyScope) async {
        retryIntent = .apply(theme.libraryID, scope)
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
        guard !operation.isBusy, let packageURL = pendingReplacement?.packageURL else { return }
        pendingReplacement = nil
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
            guard status?.session.lowercased() == "paused" else {
                throw ManagerError.invalidResponse("暂停命令完成，但引擎仍未进入暂停状态。")
            }
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
            guard status?.codexRunning == true,
                  status?.injectorAlive == true,
                  status?.cdpOk == true
            else {
                throw ManagerError.invalidResponse("重启命令完成，但 Codex、注入器或 CDP 未全部恢复健康。")
            }
            retryIntent = nil
            operation = .succeeded("Codex 已重新启动并应用主题")
        } catch {
            operation = .failed(message(for: error))
        }
    }

    private func completeImport(_ packageURL: URL, generation: Int, scoped: Bool) async {
        defer { if scoped { packageURL.stopAccessingSecurityScopedResource() } }
        guard generation == importGeneration else { return }
        do {
            let staged = try ThemePackageDeferredStore.stage(packageURL, root: deferredImportRoot)
            var keepSnapshot = false
            defer { if !keepSnapshot { try? FileManager.default.removeItem(at: staged) } }
            guard generation == importGeneration else { return }
            operation = .importing
            do {
                let result = try await engine.importTheme(packageURL: staged, replace: false)
                guard generation == importGeneration else {
                    return
                }
                try await reloadState()
                guard generation == importGeneration else { return }
                operation = .succeeded("已导入 \(result.themeName)")
            } catch ManagerError.themeAlreadyExists(let incomingID, let incomingName) {
                guard generation == importGeneration else { return }
                let normalizedID = incomingID.trimmingCharacters(in: .whitespacesAndNewlines)
                let normalizedName = incomingName.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !normalizedID.isEmpty, !normalizedName.isEmpty else {
                    operation = .failed("主题导入器返回了无法识别的重复主题信息。")
                    return
                }
                // Replacement is destructive, so stale in-memory catalog data is not sufficient
                // when the current installed identity cannot be read and verified.
                let installedThemes = try catalog.loadThemes()
                guard let existing = installedThemes.first(where: {
                    $0.libraryID == normalizedID || $0.manifest.id == normalizedID
                }) else {
                    operation = .failed("主题包与已安装主题身份不一致，已取消替换。")
                    return
                }
                keepSnapshot = true
                pendingReplacement = PendingThemeReplacement(
                    packageURL: staged,
                    incomingID: normalizedID,
                    incomingName: normalizedName,
                    existingID: existing.manifest.id,
                    existingName: existing.manifest.name
                )
                operation = .idle
            } catch {
                if generation == importGeneration {
                    operation = .failed(message(for: error))
                }
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
        case .apply(let id, .menuBar):
            return menuBarRecentThemes.contains(where: { $0.libraryID == id })
        case .apply(let id, .mainWindow), .export(let id, _):
            guard themes.contains(where: { $0.libraryID == id }) else { return false }
            guard selectedSection == .recent else { return true }
            return visibleThemes.contains(where: { $0.libraryID == id })
        case .pause, .restart, .restore:
            return true
        }
    }

    private func discardPendingReplacement() {
        guard let packageURL = pendingReplacement?.packageURL else { return }
        pendingReplacement = nil
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
        if selectedSection == .dashboard {
            let available = Set(themes.map(\.libraryID))
            if let selectedThemeID, available.contains(selectedThemeID) {
                // Preserve the inspected installed theme on the dashboard.
            } else {
                selectedThemeID = themes.first(where: \.isActive)?.libraryID ?? themes.first?.libraryID
            }
        } else {
            reconcileVisibleSelection()
        }
        retireInvalidRetryIntent()
    }

    private func recordRecent(_ libraryID: String) {
        let available = Set(themes.map(\.libraryID))
        var ids = Self.deduplicatedRecentIDs([libraryID] + recentThemeIDs)
        ids = ids.filter { available.contains($0) }
        recentThemeIDs = Array(ids.prefix(8))
        defaults.set(recentThemeIDs, forKey: recentThemeKey)
    }

    private func pruneRecentThemes() {
        let available = Set(themes.map(\.libraryID))
        let filtered = Array(
            Self.deduplicatedRecentIDs(recentThemeIDs)
                .filter { available.contains($0) }
                .prefix(8)
        )
        if filtered != recentThemeIDs {
            recentThemeIDs = filtered
            defaults.set(filtered, forKey: recentThemeKey)
        }
    }

    private func reconcileVisibleSelection() {
        guard selectedSection == .library || selectedSection == .recent else { return }
        let visible = visibleThemes
        if let selectedThemeID, visible.contains(where: { $0.libraryID == selectedThemeID }) {
            retireInvalidRetryIntent()
            return
        }
        selectedThemeID = visible.first?.libraryID
        if let pendingRestartThemeID,
           selectedSection == .recent,
           !visible.contains(where: { $0.libraryID == pendingRestartThemeID }) {
            self.pendingRestartThemeID = nil
            pendingRestartApplyScope = nil
        }
        retireInvalidRetryIntent()
    }

    private func retireInvalidRetryIntent() {
        if let retryIntent, !retryTargetExists(for: retryIntent) {
            self.retryIntent = nil
        }
    }

    private static func deduplicatedRecentIDs(_ ids: [String]) -> [String] {
        var seen = Set<String>()
        return ids.filter { seen.insert($0).inserted }
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
