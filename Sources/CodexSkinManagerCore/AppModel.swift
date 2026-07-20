import Combine
import Foundation

package enum ManagerOperation: Equatable, Sendable {
    case idle
    case validating
    case switching
    case importing
    case restoring
    case succeeded(String)
    case failed(String)

    package var isBusy: Bool {
        switch self {
        case .validating, .switching, .importing, .restoring: true
        case .idle, .succeeded, .failed: false
        }
    }
}

@MainActor
package final class AppModel: ObservableObject {
    @Published package private(set) var themes: [ThemeRecord] = []
    @Published package private(set) var status: EngineStatus?
    @Published package private(set) var operation: ManagerOperation = .idle
    @Published package private(set) var recentThemeIDs: [String]
    @Published package private(set) var pendingReplacementURL: URL?
    @Published package private(set) var pendingRestartThemeID: String?
    @Published package var selectedSection: ManagerSection = .dashboard
    @Published package var selectedThemeID: String?
    @Published package var searchText = ""
    @Published package var themeFilter: ThemeFilter = .all
    @Published package var themeSort: ThemeSort = .recent

    private let catalog: any ThemeCatalogReading
    private let engine: any EngineControlling
    private let defaults: UserDefaults
    private let recentThemeKey = "recentThemeLibraryIDs"

    package init(
        catalog: any ThemeCatalogReading,
        engine: any EngineControlling,
        defaults: UserDefaults
    ) {
        self.catalog = catalog
        self.engine = engine
        self.defaults = defaults
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

    package func selectTheme(_ theme: ThemeRecord?) {
        selectedThemeID = theme?.libraryID
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
            operation = .succeeded("已应用 \(theme.manifest.name)")
        } catch {
            operation = .failed(message(for: error))
        }
    }

    package func importPackage(_ packageURL: URL) async {
        guard !operation.isBusy else { return }
        pendingReplacementURL = nil
        operation = .validating
        await performImport(packageURL, replace: false)
    }

    package func replacePendingImport() async {
        guard !operation.isBusy, let packageURL = pendingReplacementURL else { return }
        pendingReplacementURL = nil
        operation = .importing
        await performImport(packageURL, replace: true)
    }

    package func cancelPendingImport() {
        guard !operation.isBusy else { return }
        pendingReplacementURL = nil
    }

    package func restoreOriginal() async {
        guard !operation.isBusy else { return }
        operation = .restoring
        do {
            try await engine.restoreOriginal()
            try await reloadState()
            operation = .succeeded("已恢复 Codex 原版界面")
        } catch {
            operation = .failed(message(for: error))
        }
    }

    private func performImport(_ packageURL: URL, replace: Bool) async {
        operation = .importing
        do {
            let result = try await engine.importTheme(packageURL: packageURL, replace: replace)
            try await reloadState()
            operation = .succeeded("已导入 \(result.themeName)")
        } catch ManagerError.themeAlreadyExists {
            pendingReplacementURL = packageURL
            operation = .idle
        } catch {
            operation = .failed(message(for: error))
        }
    }

    private func reloadState() async throws {
        themes = try catalog.loadThemes()
        status = try? await engine.status()
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
