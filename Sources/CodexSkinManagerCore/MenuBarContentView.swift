import AppKit
import SwiftUI
import UniformTypeIdentifiers

package struct MenuBarContentView: View {
    @ObservedObject package var model: AppModel
    @Environment(\.openWindow) private var openWindow
    @State private var showingImporter = false
    @State private var confirmingRestore = false
    @State private var localError: String?

    package init(model: AppModel) {
        self.model = model
    }

    package var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "paintpalette.fill")
                    .foregroundStyle(VisualStyle.ice)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Codex Skin Arsenal")
                        .font(.headline)
                    Text(statusText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer()
                if model.operation.isBusy { ProgressView().controlSize(.small) }
            }

            if !model.recentThemes.isEmpty {
                Divider()
                Text("最近装备")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                ForEach(model.recentThemes) { theme in
                    Button {
                        Task { await model.apply(theme) }
                    } label: {
                        HStack {
                            Image(systemName: theme.isActive ? "checkmark.seal.fill" : "shield.lefthalf.filled")
                            Text(theme.manifest.name)
                            Spacer()
                        }
                    }
                    .buttonStyle(.plain)
                    .disabled(theme.isActive || model.operation.isBusy)
                }
            }

            Divider()
            Button { openWindow(id: "main") } label: {
                Label("打开主题武库", systemImage: "macwindow")
            }
            Button { showingImporter = true } label: {
                Label("导入主题包…", systemImage: "square.and.arrow.down")
            }
            .disabled(model.operation.isBusy)
            Button(role: .destructive) { confirmingRestore = true } label: {
                Label("恢复 Codex 原版…", systemImage: "arrow.counterclockwise.circle")
            }
            .disabled(model.operation.isBusy)

            if let localError {
                Text(localError)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .lineLimit(2)
            }

            Divider()
            Button { NSApplication.shared.terminate(nil) } label: {
                Label("退出 Codex Skin Manager", systemImage: "power")
            }
        }
        .padding(14)
        .frame(width: 320)
        .task { await model.refresh() }
        .fileImporter(isPresented: $showingImporter, allowedContentTypes: [.codexSkinPackage]) { result in
            switch result {
            case .success(let url):
                localError = nil
                Task {
                    let scoped = url.startAccessingSecurityScopedResource()
                    defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                    await model.importPackage(url)
                }
            case .failure(let error):
                localError = String(error.localizedDescription.prefix(240))
            }
        }
        .alert("主题已经安装", isPresented: duplicateAlertBinding) {
            Button("替换", role: .destructive) { Task { await model.replacePendingImport() } }
            Button("取消", role: .cancel) { model.cancelPendingImport() }
        } message: {
            Text("替换后仍需手动应用该主题。")
        }
        .confirmationDialog("恢复 Codex 原版界面？", isPresented: $confirmingRestore, titleVisibility: .visible) {
            Button("恢复并重启 Codex", role: .destructive) { Task { await model.restoreOriginal() } }
            Button("取消", role: .cancel) {}
        } message: {
            Text("Codex 会自动关闭并重新打开。")
        }
    }

    private var duplicateAlertBinding: Binding<Bool> {
        Binding(
            get: { model.pendingReplacementURL != nil },
            set: { visible in if !visible { model.cancelPendingImport() } }
        )
    }

    private var statusText: String {
        if case .failed(let message) = model.operation { return message }
        if case .succeeded(let message) = model.operation { return message }
        guard let status = model.status else { return "正在检测 Dream Skin…" }
        return status.themeName.isEmpty ? "Dream Skin" : "当前：\(status.themeName)"
    }
}
