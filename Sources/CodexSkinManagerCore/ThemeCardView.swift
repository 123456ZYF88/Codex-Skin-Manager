import AppKit
import SwiftUI

package struct ThemeCardView: View {
    package let theme: ThemeRecord
    @ObservedObject package var model: AppModel

    package init(theme: ThemeRecord, model: AppModel) {
        self.theme = theme
        self.model = model
    }

    package var body: some View {
        VStack(spacing: 0) {
            preview
                .aspectRatio(16 / 9, contentMode: .fit)

            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(theme.manifest.name)
                        .font(.system(size: 20, weight: .semibold, design: .serif))
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    if theme.isActive {
                        Label("已启用", systemImage: "snowflake")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(VisualStyle.frost)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(VisualStyle.ice.opacity(0.16), in: Capsule())
                    }
                }

                HStack {
                    Label(appearanceLabel, systemImage: "circle.lefthalf.filled")
                        .font(.caption)
                        .foregroundStyle(VisualStyle.muted)
                    Spacer()
                    Button {
                        Task { await model.apply(theme) }
                    } label: {
                        Label(theme.isActive ? "当前主题" : "装备主题", systemImage: theme.isActive ? "checkmark.seal.fill" : "shield.lefthalf.filled")
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(theme.isActive ? .gray : VisualStyle.ice)
                    .disabled(theme.isActive || model.operation.isBusy)
                    .accessibilityLabel(theme.isActive ? "当前已启用 \(theme.manifest.name)" : "应用主题 \(theme.manifest.name)")
                }
            }
            .padding(14)
        }
        .background(VisualStyle.panel)
        .clipShape(WeaponPlateShape())
        .overlay {
            WeaponPlateShape()
                .stroke(theme.isActive ? VisualStyle.ice : .white.opacity(0.16), lineWidth: theme.isActive ? 2 : 1)
        }
        .shadow(color: theme.isActive ? VisualStyle.ice.opacity(0.24) : .black.opacity(0.35), radius: 16, y: 8)
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private var preview: some View {
        if let image = NSImage(contentsOf: theme.imageURL) {
            Image(nsImage: image)
                .resizable()
                .scaledToFill()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipped()
                .overlay(alignment: .bottom) {
                    LinearGradient(colors: [.clear, VisualStyle.abyss.opacity(0.8)], startPoint: .top, endPoint: .bottom)
                        .frame(height: 70)
                }
        } else {
            ZStack {
                LinearGradient(colors: [VisualStyle.deepBlue, VisualStyle.abyss], startPoint: .topLeading, endPoint: .bottomTrailing)
                Image(systemName: "photo.on.rectangle.angled")
                    .font(.system(size: 38, weight: .light))
                    .foregroundStyle(VisualStyle.frost.opacity(0.75))
            }
        }
    }

    private var appearanceLabel: String {
        switch theme.manifest.appearance {
        case "light": "明亮"
        case "dark": "深色"
        default: "自动"
        }
    }
}
