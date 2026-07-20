import AppKit
import SwiftUI
import UniformTypeIdentifiers

package extension UTType {
    static let codexSkinPackage = UTType(exportedAs: "dev.codexskin.package", conformingTo: .zip)
}

package enum ThemePackageDeferredStore {
    package static func isRegularPackage(_ url: URL) -> Bool {
        guard url.isFileURL,
              url.pathExtension.localizedCaseInsensitiveCompare("codexskin") == .orderedSame,
              let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey]),
              values.isRegularFile == true,
              values.isSymbolicLink != true
        else { return false }
        return true
    }

    package static func stage(_ source: URL, root: URL = defaultRoot()) throws -> URL {
        guard isRegularPackage(source) else {
            throw ManagerError.invalidResponse("导入包必须是普通 .codexskin 文件。")
        }
        let fileManager = FileManager.default
        try fileManager.createDirectory(
            at: root,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        let destination = root.appendingPathComponent("\(UUID().uuidString).codexskin")
        try fileManager.copyItem(at: source, to: destination)
        try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: destination.path)
        return destination
    }

    private static func defaultRoot() -> URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support", isDirectory: true)
            .appendingPathComponent("CodexDreamSkinStudio", isDirectory: true)
            .appendingPathComponent("PendingThemeImports", isDirectory: true)
    }
}

package enum ThemeExportName {
    package static func safeExportName(_ name: String, fallback: String) -> String {
        let primary = sanitize(name)
        if !primary.isEmpty { return primary }
        let fallback = sanitize(fallback)
        return fallback.isEmpty ? "Theme" : fallback
    }

    private static func sanitize(_ value: String) -> String {
        var result = ""
        for character in value {
            if character.isLetter || character.isNumber || character == "-" || character == "_" {
                result.append(character)
            } else if result.last != "-" {
                result.append("-")
            }
        }
        return result.trimmingCharacters(in: CharacterSet(charactersIn: "-_"))
    }
}

/// Composes the main workspaces while the library owns its toolbar and selected-theme detail.
/// The operation banner remains fixed below the selected workspace.
package struct ContentView: View {
    @ObservedObject package var model: AppModel
    @State private var showingImporter = false
    @State private var confirmingRestore = false
    @State private var localError: String?

    package init(model: AppModel) {
        self.model = model
    }

    package var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            ZStack {
                MangaBurstBackground()
                VStack(spacing: 0) {
                    workspace
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    OperationBanner(model: model)
                }
            }
        }
        .navigationSplitViewStyle(.balanced)
        .frame(minWidth: 960, minHeight: 640)
        .task { await model.refresh() }
        .fileImporter(isPresented: $showingImporter, allowedContentTypes: [.codexSkinPackage]) { result in
            handleImportResult(result)
        }
        .alert("主题已经安装", isPresented: duplicateAlertBinding) {
            Button("替换已安装主题", role: .destructive) {
                Task { await model.replacePendingImport() }
            }
            Button("取消", role: .cancel) { model.cancelPendingImport() }
        } message: {
            Text("替换会更新主题库中的同名 ID，但不会自动应用。")
        }
        .alert("需要重新启动 Codex", isPresented: restartAlertBinding) {
            Button("重启并应用") {
                Task { await model.confirmPendingRestartApply() }
            }
            Button("取消", role: .cancel) { model.cancelPendingRestartApply() }
        } message: {
            Text("当前 Codex 正在运行，但 CDP 未通过验证。继续会重启 Codex 并验证所选主题。")
        }
        .alert("无法导入主题", isPresented: localErrorBinding) {
            Button("好", role: .cancel) { localError = nil }
        } message: {
            Text(localError ?? "未知错误")
        }
        .confirmationDialog("恢复 Codex 原版界面？", isPresented: $confirmingRestore, titleVisibility: .visible) {
            Button("恢复并重启 Codex", role: .destructive) {
                Task { await model.restoreOriginal() }
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("这会移除 Dream Skin 的当前视觉效果，并自动关闭后重新打开 Codex。")
        }
    }

    @ViewBuilder
    private var workspace: some View {
        switch model.selectedSection {
        case .dashboard:
            DashboardView(
                model: model,
                onOpenLibrary: { model.selectedSection = .library },
                onRestore: { confirmingRestore = true }
            )
        case .library, .recent:
            ThemeLibraryView(
                model: model,
                onImport: { showingImporter = true },
                onExport: presentExportPanel,
                onImportURLs: importURLs
            )
        }
    }

    private var sidebar: some View {
        VStack(spacing: 0) {
            List(ManagerSection.allCases, selection: $model.selectedSection) { section in
                Label(section.title, systemImage: section.symbol)
                    .tag(section)
                    .font(.system(size: 14, weight: .medium))
            }
            .scrollContentBackground(.hidden)

            VStack(alignment: .leading, spacing: 8) {
                Text("DREAM SKIN ENGINE")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundStyle(.secondary)
                Label(engineStatusText, systemImage: engineSymbol)
                    .font(.caption)
                    .foregroundStyle(engineColor)
                    .lineLimit(2)
                    .accessibilityLabel("引擎状态：\(engineStatusText)")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(.ultraThinMaterial)
        }
        .navigationTitle("Codex Skin")
        .frame(minWidth: 190)
    }

    private var duplicateAlertBinding: Binding<Bool> {
        Binding(
            get: { model.pendingReplacementURL != nil },
            set: { visible in if !visible { model.cancelPendingImport() } }
        )
    }

    private var restartAlertBinding: Binding<Bool> {
        Binding(
            get: { model.pendingRestartThemeID != nil },
            set: { visible in if !visible { model.cancelPendingRestartApply() } }
        )
    }

    private var localErrorBinding: Binding<Bool> {
        Binding(
            get: { localError != nil },
            set: { visible in if !visible { localError = nil } }
        )
    }

    private func handleImportResult(_ result: Result<URL, Error>) {
        switch result {
        case .success(let url):
            localError = nil
            if !importURLs([url]) {
                localError = "请选择一个有效的 .codexskin 主题包。"
            }
        case .failure(let error):
            localError = String(error.localizedDescription.prefix(300))
        }
    }

    @discardableResult
    package func importURLs(_ urls: [URL]) -> Bool {
        guard urls.count == 1,
              let url = urls.first,
              url.isFileURL,
              url.pathExtension.localizedCaseInsensitiveCompare("codexskin") == .orderedSame
        else { return false }

        localError = nil
        let scoped = url.startAccessingSecurityScopedResource()
        guard ThemePackageDeferredStore.isRegularPackage(url) else {
            if scoped {
                url.stopAccessingSecurityScopedResource()
            }
            return false
        }
        Task {
            defer {
                if scoped {
                    url.stopAccessingSecurityScopedResource()
                }
            }
            let requiresReplacement = await model.importPackage(url)
            guard requiresReplacement else { return }
            do {
                // The private copy is made before the caller's scope ends so replacement never reuses its URL.
                let staged = try ThemePackageDeferredStore.stage(url)
                model.storePendingReplacement(staged)
            } catch {
                localError = String(error.localizedDescription.prefix(300))
            }
        }
        return true
    }

    @MainActor
    private func presentExportPanel() {
        guard let theme = model.selectedTheme else { return }
        let panel = NSSavePanel()
        panel.allowedFileTypes = ["codexskin"]
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false
        panel.nameFieldStringValue = "\(ThemeExportName.safeExportName(theme.manifest.name, fallback: theme.manifest.id)).codexskin"
        guard panel.runModal() == .OK, let destination = panel.url else { return }
        Task { await model.exportSelectedTheme(to: destination) }
    }

    private var engineStatusText: String {
        guard let status = model.status else { return "等待检测" }
        if status.cdpOk && status.injectorAlive { return "在线 · \(status.themeName)" }
        if status.codexRunning { return "Codex 已运行，等待注入" }
        return "Codex 未运行"
    }

    private var engineSymbol: String {
        guard let status = model.status else { return "hourglass" }
        if status.cdpOk && status.injectorAlive { return "checkmark.seal.fill" }
        return status.codexRunning ? "exclamationmark.triangle.fill" : "power"
    }

    private var engineColor: Color {
        guard let status = model.status else { return .secondary }
        return status.cdpOk && status.injectorAlive ? VisualStyle.jade : .orange
    }
}
