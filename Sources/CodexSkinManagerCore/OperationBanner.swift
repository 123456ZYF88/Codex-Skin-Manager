import AppKit
import SwiftUI

package struct OperationBanner: View {
    @ObservedObject package var model: AppModel

    package init(model: AppModel) {
        self.model = model
    }

    package var body: some View {
        HStack(spacing: 10) {
            Image(systemName: presentation.icon)
                .foregroundStyle(presentation.color)
            Text(presentation.text)
                .font(.callout)
                .lineLimit(2)
            Spacer(minLength: 12)
            if model.operation.isBusy {
                ProgressView()
                    .controlSize(.small)
                    .accessibilityLabel(presentation.text)
            }
            if model.retryAvailable {
                Button("重试") {
                    Task { await model.retryLastAction() }
                }
                    .buttonStyle(.bordered)
                    .accessibilityLabel("重试上一个失败的操作")
            }
            if let message = failureMessage {
                Button {
                    let pasteboard = NSPasteboard.general
                    pasteboard.clearContents()
                    pasteboard.setString(message, forType: .string)
                } label: {
                    Label("复制错误", systemImage: "doc.on.doc")
                        .labelStyle(.iconOnly)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("复制已清理的错误详情")
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 11)
        .background(.ultraThinMaterial)
        .overlay(alignment: .top) { Rectangle().fill(presentation.color.opacity(0.35)).frame(height: 1) }
        .accessibilityElement(children: .contain)
    }

    private var failureMessage: String? {
        if case .failed(let message) = model.operation { return message }
        return nil
    }

    private var presentation: (icon: String, text: String, color: Color) {
        switch model.operation {
        case .idle:
            ("snowflake", "准备就绪", VisualStyle.ice)
        case .validating:
            ("checkmark.shield", "正在验证主题包…", .orange)
        case .switching:
            ("shield.lefthalf.filled", "正在装备主题…", .orange)
        case .importing:
            ("square.and.arrow.down", "正在安全导入主题包…", .orange)
        case .exporting:
            ("square.and.arrow.up", "正在导出并验证主题包…", .orange)
        case .restoring:
            ("arrow.counterclockwise.circle.fill", "正在恢复原版并重启 Codex…", .orange)
        case .pausing:
            ("pause.circle.fill", "正在暂停主题…", .orange)
        case .restarting:
            ("arrow.clockwise.circle.fill", "正在重启 Codex 并应用主题…", .orange)
        case .succeeded(let message):
            ("checkmark.seal.fill", message, VisualStyle.jade)
        case .failed(let message):
            ("exclamationmark.triangle.fill", message, .red)
        }
    }
}
