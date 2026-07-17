import SwiftUI
import UniformTypeIdentifiers

package extension UTType {
    static let codexSkinPackage = UTType(exportedAs: "dev.codexskin.package", conformingTo: .zip)
}

private enum ManagerSection: String, CaseIterable, Identifiable {
    case library
    case recent

    var id: String { rawValue }
    var title: String { self == .library ? "主题武库" : "最近装备" }
    var symbol: String { self == .library ? "shield.lefthalf.filled" : "clock.arrow.circlepath" }
}

package struct ContentView: View {
    @ObservedObject package var model: AppModel
    @State private var selectedSection: ManagerSection = .library
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
                ScrollView {
                    VStack(alignment: .leading, spacing: 22) {
                        header
                        themeGrid
                        operationFooter
                    }
                    .padding(28)
                }
            }
        }
        .navigationSplitViewStyle(.balanced)
        .frame(minWidth: 820, minHeight: 580)
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
        .confirmationDialog("恢复 Codex 原版界面？", isPresented: $confirmingRestore, titleVisibility: .visible) {
            Button("恢复并重启 Codex", role: .destructive) {
                Task { await model.restoreOriginal() }
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("这会移除 Dream Skin 的当前视觉效果，并自动关闭后重新打开 Codex。")
        }
    }

    private var sidebar: some View {
        VStack(spacing: 0) {
            List(ManagerSection.allCases, selection: $selectedSection) { section in
                Label(section.title, systemImage: section.symbol)
                    .tag(section)
                    .font(.system(size: 14, weight: .medium))
            }
            .scrollContentBackground(.hidden)

            VStack(alignment: .leading, spacing: 8) {
                Text("DREAM SKIN ENGINE")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundStyle(.secondary)
                HStack(spacing: 7) {
                    Circle()
                        .fill(engineColor)
                        .frame(width: 8, height: 8)
                    Text(engineStatusText)
                        .font(.caption)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(.ultraThinMaterial)
        }
        .navigationTitle("Codex Skin")
        .frame(minWidth: 190)
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 18) {
            VStack(alignment: .leading, spacing: 5) {
                Text("CODEX · SKIN ARSENAL")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .tracking(2.2)
                    .foregroundStyle(VisualStyle.ice)
                Text(selectedSection == .recent ? "最近装备" : "主题武库")
                    .font(.system(size: 34, weight: .bold, design: .serif))
                Text("切换已经安装的主题，或导入完整的 .codexskin 武装包。")
                    .font(.callout)
                    .foregroundStyle(VisualStyle.muted)
            }
            Spacer()
            Button {
                showingImporter = true
            } label: {
                Label("导入主题", systemImage: "square.and.arrow.down.on.square")
            }
            .buttonStyle(.borderedProminent)
            .tint(VisualStyle.ice)
            .disabled(model.operation.isBusy)
            .accessibilityLabel("导入新的 Codex 主题包")

            Button(role: .destructive) {
                confirmingRestore = true
            } label: {
                Label("恢复原版", systemImage: "arrow.counterclockwise.circle")
            }
            .buttonStyle(.bordered)
            .disabled(model.operation.isBusy)
            .accessibilityLabel("恢复 Codex 原版界面并重启")
        }
    }

    @ViewBuilder
    private var themeGrid: some View {
        let visibleThemes = selectedSection == .recent ? model.recentThemes : model.themes
        if visibleThemes.isEmpty {
            VStack(spacing: 12) {
                Image(systemName: selectedSection == .recent ? "clock.badge.questionmark" : "shield.slash")
                    .font(.system(size: 40, weight: .light))
                    .foregroundStyle(VisualStyle.frost)
                Text(selectedSection == .recent ? "还没有最近使用的主题" : "没有找到已安装主题")
                    .font(.title3.weight(.semibold))
                Text("可从右上角导入一个完整的 .codexskin 主题包。")
                    .foregroundStyle(VisualStyle.muted)
            }
            .frame(maxWidth: .infinity, minHeight: 280)
            .background(VisualStyle.panel.opacity(0.65))
            .clipShape(WeaponPlateShape())
        } else {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 270, maximum: 420), spacing: 18)], spacing: 18) {
                ForEach(visibleThemes) { theme in
                    ThemeCardView(theme: theme, model: model)
                }
            }
        }
    }

    private var operationFooter: some View {
        HStack(spacing: 10) {
            Image(systemName: operationSymbol)
                .foregroundStyle(operationColor)
            Text(localError ?? operationText)
                .font(.callout)
                .lineLimit(2)
            Spacer()
            if model.operation.isBusy {
                ProgressView()
                    .controlSize(.small)
            }
            Button {
                Task { await model.refresh() }
            } label: {
                Label("刷新", systemImage: "arrow.clockwise")
                    .labelStyle(.iconOnly)
            }
            .buttonStyle(.plain)
            .disabled(model.operation.isBusy)
            .accessibilityLabel("刷新主题库和引擎状态")
        }
        .padding(13)
        .background(.ultraThinMaterial, in: WeaponPlateShape())
    }

    private var duplicateAlertBinding: Binding<Bool> {
        Binding(
            get: { model.pendingReplacementURL != nil },
            set: { visible in if !visible { model.cancelPendingImport() } }
        )
    }

    private func handleImportResult(_ result: Result<URL, Error>) {
        switch result {
        case .success(let url):
            localError = nil
            Task {
                let scoped = url.startAccessingSecurityScopedResource()
                defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                await model.importPackage(url)
            }
        case .failure(let error):
            localError = String(error.localizedDescription.prefix(300))
        }
    }

    private var engineStatusText: String {
        guard let status = model.status else { return "等待检测" }
        if status.cdpOk && status.injectorAlive { return "在线 · \(status.themeName)" }
        if status.codexRunning { return "Codex 已运行，等待注入" }
        return "Codex 未运行"
    }

    private var engineColor: Color {
        guard let status = model.status else { return .gray }
        return status.cdpOk && status.injectorAlive ? VisualStyle.jade : .orange
    }

    private var operationText: String {
        switch model.operation {
        case .idle: "准备就绪"
        case .validating: "正在验证主题包…"
        case .switching: "正在装备主题；热切换失败时会自动重启 Codex…"
        case .importing: "正在安全导入主题包…"
        case .restoring: "正在恢复原版界面并重启 Codex…"
        case .succeeded(let message), .failed(let message): message
        }
    }

    private var operationSymbol: String {
        switch model.operation {
        case .succeeded: "checkmark.seal.fill"
        case .failed: "exclamationmark.triangle.fill"
        case .switching: "shield.lefthalf.filled"
        case .importing, .validating: "square.and.arrow.down"
        case .restoring: "arrow.counterclockwise.circle.fill"
        case .idle: "snowflake"
        }
    }

    private var operationColor: Color {
        switch model.operation {
        case .failed: .red
        case .succeeded: VisualStyle.jade
        default: VisualStyle.ice
        }
    }
}
