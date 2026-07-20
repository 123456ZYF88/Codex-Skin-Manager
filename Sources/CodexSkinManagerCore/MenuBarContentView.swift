import AppKit
import SwiftUI
import UniformTypeIdentifiers

package struct MenuBarContentView: View {
    @ObservedObject package var model: AppModel
    @Environment(\.openWindow) private var openWindow
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
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
                    Label(statusText, systemImage: statusSymbol)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .accessibilityLabel("引擎状态：\(statusText)")
                }
                Spacer()
                if model.operation.isBusy {
                    if reduceMotion {
                        Image(systemName: "hourglass")
                            .accessibilityLabel("正在处理主题操作")
                    } else {
                        ProgressView()
                            .controlSize(.small)
                            .accessibilityLabel("正在处理主题操作")
                    }
                }
            }

            Divider()
            Text("当前装备")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            if let activeTheme {
                Label(activeTheme.manifest.name, systemImage: "checkmark.seal.fill")
                    .foregroundStyle(VisualStyle.success)
                    .accessibilityLabel("当前启用主题：\(activeTheme.manifest.name)")
            } else {
                Label("Codex 原版", systemImage: "macwindow")
                    .foregroundStyle(.secondary)
            }

            if !model.menuBarRecentThemes.isEmpty {
                Divider()
                Text("最近装备")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                ForEach(model.menuBarRecentThemes) { theme in
                    Button {
                        Task { await model.applyMenuBarRecentTheme(theme) }
                    } label: {
                        HStack {
                            Image(systemName: theme.isActive ? "checkmark.seal.fill" : "shield.lefthalf.filled")
                            Text(theme.manifest.name)
                            Spacer()
                        }
                    }
                    .buttonStyle(.plain)
                    .disabled(theme.isActive || model.operation.isBusy)
                    .accessibilityLabel("应用最近主题：\(theme.manifest.name)")
                }
            }

            Divider()
            if canPause {
                Button {
                    Task { await model.pauseTheme() }
                } label: {
                    Label("暂停当前主题", systemImage: "pause.circle")
                }
                .disabled(model.operation.isBusy)
            }
            if canRestart {
                Button {
                    Task { await model.restartTheme() }
                } label: {
                    Label(restartTitle, systemImage: "arrow.clockwise.circle")
                }
                .disabled(model.operation.isBusy)
            }
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
                if !model.beginImport(url) {
                    localError = "请选择一个有效的 .codexskin 主题包，或等待当前操作完成。"
                }
            case .failure(let error):
                localError = String(error.localizedDescription.prefix(240))
            }
        }
        .alert("主题已经安装", isPresented: duplicateAlertBinding) {
            Button("替换", role: .destructive) { Task { await model.replacePendingImport() } }
            Button("取消", role: .cancel) { model.cancelPendingImport() }
        } message: {
            Text(model.pendingReplacementConfirmationText ?? "替换后仍需手动应用该主题。")
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

    private var activeTheme: ThemeRecord? {
        model.themes.first(where: \.isActive)
    }

    private var statusText: String {
        guard let status = model.status else { return "等待主题注入" }
        if status.session.lowercased() == "paused" { return "主题已暂停" }
        if !status.codexRunning { return "Codex 已停止" }
        if status.injectorAlive && status.cdpOk { return "主题运行中" }
        return "等待主题注入"
    }

    private var statusSymbol: String {
        guard let status = model.status else { return "hourglass" }
        if status.session.lowercased() == "paused" { return "pause.circle.fill" }
        if !status.codexRunning { return "power" }
        if status.injectorAlive && status.cdpOk { return "checkmark.seal.fill" }
        return "hourglass"
    }

    private var canPause: Bool {
        guard let status = model.status else { return false }
        return status.codexRunning && status.injectorAlive && status.cdpOk
    }

    private var canRestart: Bool {
        model.status != nil && !canPause
    }

    private var restartTitle: String {
        model.status?.codexRunning == true ? "重新启动并应用主题" : "启动 Codex 并应用主题"
    }
}
