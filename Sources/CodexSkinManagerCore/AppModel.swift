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
        recentThemeIDs = Array((defaults.stringArray(forKey: recentThemeKey) ?? []).prefix(3))
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
        operation = .switching
        do {
            try await engine.switchTheme(libraryID: theme.libraryID)
            try await reloadState()
            recordRecent(theme.libraryID)
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
    }

    private func recordRecent(_ libraryID: String) {
        let available = Set(themes.map(\.libraryID))
        var ids = [libraryID] + recentThemeIDs.filter { $0 != libraryID }
        ids = ids.filter { available.contains($0) }
        recentThemeIDs = Array(ids.prefix(3))
        defaults.set(recentThemeIDs, forKey: recentThemeKey)
    }

    private func pruneRecentThemes() {
        let available = Set(themes.map(\.libraryID))
        let filtered = Array(recentThemeIDs.filter { available.contains($0) }.prefix(3))
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
