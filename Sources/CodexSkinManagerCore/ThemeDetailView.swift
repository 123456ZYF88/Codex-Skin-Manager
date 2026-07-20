import AppKit
import SwiftUI

package struct ThemeDetailView: View {
    package let theme: ThemeRecord
    @ObservedObject package var model: AppModel
    package let onExport: () -> Void

    package init(theme: ThemeRecord, model: AppModel, onExport: @escaping () -> Void) {
        self.theme = theme
        self.model = model
        self.onExport = onExport
    }

    package var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                preview
                    .aspectRatio(16 / 9, contentMode: .fit)
                    .clipShape(WeaponPlateShape())
                    .overlay { WeaponPlateShape().stroke(VisualStyle.ice.opacity(0.45), lineWidth: 1) }

                HStack(alignment: .firstTextBaseline) {
                    Text(theme.manifest.name)
                        .font(.system(size: 30, weight: .bold, design: .serif))
                    Spacer()
                    if theme.isActive {
                        Label("已启用", systemImage: "checkmark.seal.fill")
                            .font(.callout.weight(.semibold))
                            .foregroundStyle(VisualStyle.jade)
                    }
                }

                VStack(alignment: .leading, spacing: 10) {
                    metadataRow(title: "Manifest ID", value: theme.manifest.id)
                    if theme.libraryID != theme.manifest.id {
                        metadataRow(title: "Library ID", value: theme.libraryID)
                    }
                    metadataRow(title: "外观", value: appearanceText)
                }

                Divider().overlay(.white.opacity(0.14))

                HStack(spacing: 10) {
                    if theme.isActive {
                        Button("当前主题") {}
                            .disabled(true)
                        Button {
                            Task { await model.apply(theme) }
                        } label: {
                            Label("重新应用", systemImage: "arrow.clockwise.circle.fill")
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(VisualStyle.ice)
                    } else {
                        Button {
                            Task { await model.apply(theme) }
                        } label: {
                            Label("装备主题", systemImage: "shield.lefthalf.filled")
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(VisualStyle.ice)
                    }

                    Button(action: onExport) {
                        Label("导出主题", systemImage: "square.and.arrow.up")
                    }
                    .buttonStyle(.bordered)
                }
                .disabled(model.operation.isBusy)
            }
            .padding(22)
        }
        .background(VisualStyle.panel.opacity(0.78))
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
                .accessibilityLabel("主题预览 \(theme.manifest.name)")
        } else {
            ZStack {
                LinearGradient(
                    colors: [VisualStyle.deepBlue, VisualStyle.abyss],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                Image(systemName: "photo.on.rectangle.angled")
                    .font(.system(size: 46, weight: .light))
                    .foregroundStyle(VisualStyle.frost.opacity(0.75))
            }
            .accessibilityLabel("主题预览不可用")
        }
    }

    private func metadataRow(title: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 14) {
            Text(title)
                .foregroundStyle(VisualStyle.muted)
                .frame(width: 90, alignment: .leading)
            Text(value)
                .font(.system(.callout, design: .monospaced))
                .textSelection(.enabled)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title)：\(value)")
    }

    private var appearanceText: String {
        switch theme.manifest.appearance {
        case "light": "明亮"
        case "dark": "深色"
        default: "自动"
        }
    }
}
