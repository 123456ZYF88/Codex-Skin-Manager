import AppKit
import SwiftUI

package struct DashboardView: View {
    @ObservedObject package var model: AppModel
    package let onOpenLibrary: () -> Void
    package let onRestore: () -> Void

    package init(model: AppModel, onOpenLibrary: @escaping () -> Void, onRestore: @escaping () -> Void) {
        self.model = model
        self.onOpenLibrary = onOpenLibrary
        self.onRestore = onRestore
    }

    package var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("DREAM SKIN CONTROL")
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .tracking(2.2)
                        .foregroundStyle(VisualStyle.ice)
                    Text("主题首页")
                        .font(.system(size: 34, weight: .bold, design: .serif))
                    Text("查看当前主题与注入状态，并控制 Codex 的主题生命周期。")
                        .font(.callout)
                        .foregroundStyle(VisualStyle.muted)
                }

                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .top, spacing: 22) {
                        hero.frame(minWidth: 460)
                        actionPanel.frame(minWidth: 280, idealWidth: 320, maxWidth: 360)
                    }
                    VStack(spacing: 18) {
                        hero
                        actionPanel
                    }
                }
            }
            .padding(28)
        }
    }

    private var activeTheme: ThemeRecord? {
        model.themes.first(where: \.isActive)
    }

    private var hero: some View {
        VStack(alignment: .leading, spacing: 0) {
            preview
                .aspectRatio(16 / 9, contentMode: .fit)
            VStack(alignment: .leading, spacing: 7) {
                Text(activeTheme?.manifest.name ?? "Codex 原版")
                    .font(.system(size: 27, weight: .bold, design: .serif))
                Label(appearanceText, systemImage: "circle.lefthalf.filled")
                    .font(.callout)
                    .foregroundStyle(VisualStyle.muted)
            }
            .padding(18)
        }
        .background(VisualStyle.panelStrong)
        .clipShape(WeaponPlateShape())
        .overlay { WeaponPlateShape().stroke(VisualStyle.selection.opacity(0.42), lineWidth: 1) }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("当前主题，\(activeTheme?.manifest.name ?? "Codex 原版")，\(appearanceText)")
    }

    @ViewBuilder
    private var preview: some View {
        if let url = activeTheme?.imageURL, let image = NSImage(contentsOf: url) {
            Image(nsImage: image)
                .resizable()
                .scaledToFill()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipped()
                .accessibilityLabel("当前主题预览 \(activeTheme?.manifest.name ?? "Codex 原版")")
        } else {
            ZStack {
                LinearGradient(
                    colors: [VisualStyle.deepBlue, VisualStyle.abyss],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                Image(systemName: "sparkles.rectangle.stack")
                    .font(.system(size: 52, weight: .light))
                    .foregroundStyle(VisualStyle.frost.opacity(0.8))
            }
            .accessibilityLabel("当前主题预览 \(activeTheme?.manifest.name ?? "Codex 原版")")
        }
    }

    private var actionPanel: some View {
        VStack(alignment: .leading, spacing: 15) {
            Text("运行状态")
                .font(.headline)
            statusRow(title: "Codex", icon: "macwindow", state: codexState, color: codexColor)
            statusRow(title: "注入器", icon: "syringe", state: injectorState, color: injectorColor)
            statusRow(title: "CDP", icon: "network", state: cdpState, color: cdpColor)
            statusRow(title: "主题", icon: "paintpalette", state: themeState, color: themeColor)

            Divider().overlay(.white.opacity(0.14))

            Button {
                Task { await model.restartTheme() }
            } label: {
                Label(model.status?.codexRunning == true ? "重新应用" : "启动主题", systemImage: "play.circle.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(VisualStyle.ice)

            Button {
                Task { await model.pauseTheme() }
            } label: {
                Label("暂停主题", systemImage: "pause.circle")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)

            Button(action: onOpenLibrary) {
                Label("浏览主题库", systemImage: "rectangle.grid.1x2")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)

            Button(role: .destructive, action: onRestore) {
                Label("恢复原版", systemImage: "arrow.counterclockwise.circle")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
        }
        .padding(18)
        .background(.ultraThinMaterial, in: WeaponPlateShape())
        .overlay { WeaponPlateShape().stroke(.white.opacity(0.14), lineWidth: 1) }
        .disabled(model.operation.isBusy)
    }

    private func statusRow(title: String, icon: String, state: String, color: Color) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .foregroundStyle(color)
                .frame(width: 20)
            Text(title)
                .foregroundStyle(VisualStyle.muted)
            Spacer()
            Text(state)
                .font(.callout.weight(.semibold))
                .foregroundStyle(color)
                .lineLimit(1)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title)：\(state)")
    }

    private var codexState: String {
        guard let status = model.status else { return "等待检测" }
        return status.codexRunning ? "运行中" : "未运行"
    }

    private var injectorState: String {
        guard let status = model.status else { return "等待检测" }
        return status.injectorAlive ? "已连接" : "未连接"
    }

    private var cdpState: String {
        guard let status = model.status else { return "等待检测" }
        return status.cdpOk ? "已验证" : "未验证"
    }

    private var themeState: String {
        activeTheme?.manifest.name ?? "原版"
    }

    private var codexColor: Color { model.status?.codexRunning == true ? VisualStyle.success : VisualStyle.warning }
    private var injectorColor: Color { model.status?.injectorAlive == true ? VisualStyle.success : VisualStyle.warning }
    private var cdpColor: Color { model.status?.cdpOk == true ? VisualStyle.success : VisualStyle.warning }
    private var themeColor: Color { activeTheme == nil ? .secondary : VisualStyle.selection }

    private var appearanceText: String {
        switch activeTheme?.manifest.appearance {
        case "light": "明亮外观"
        case "dark": "深色外观"
        default: "自动外观"
        }
    }
}
