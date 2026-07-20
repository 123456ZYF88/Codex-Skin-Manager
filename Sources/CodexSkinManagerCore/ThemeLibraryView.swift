import SwiftUI

package struct ThemeLibraryView: View {
    @ObservedObject package var model: AppModel
    package let onImport: () -> Void
    package let onExport: () -> Void

    package init(model: AppModel, onImport: @escaping () -> Void, onExport: @escaping () -> Void) {
        self.model = model
        self.onImport = onImport
        self.onExport = onExport
    }

    package var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 5) {
                Text(model.selectedSection == .recent ? "最近装备" : "主题武库")
                    .font(.system(size: 32, weight: .bold, design: .serif))
                Text("选择主题只会打开详情，不会立即应用。")
                    .font(.callout)
                    .foregroundStyle(VisualStyle.muted)
            }

            ThemeToolbar(model: model, onImport: onImport, onExport: onExport)

            ViewThatFits(in: .horizontal) {
                HSplitView {
                    themeList.frame(minWidth: 280, idealWidth: 340, maxWidth: 390)
                    detail.frame(minWidth: 520)
                }
                .frame(minWidth: 800)

                narrowGallery
            }
        }
        .padding(24)
    }

    private var themeList: some View {
        Group {
            if model.visibleThemes.isEmpty {
                emptyState
            } else {
                List(selection: $model.selectedThemeID) {
                    ForEach(model.visibleThemes) { theme in
                        ThemeCardView(theme: theme, model: model)
                            .tag(theme.libraryID)
                            .listRowInsets(EdgeInsets(top: 8, leading: 8, bottom: 8, trailing: 8))
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
        }
    }

    @ViewBuilder
    private var detail: some View {
        if let theme = model.selectedTheme {
            ThemeDetailView(theme: theme, model: model, onExport: onExport)
        } else {
            emptyDetail
        }
    }

    private var narrowGallery: some View {
        ScrollView {
            VStack(spacing: 18) {
                if model.visibleThemes.isEmpty {
                    emptyState
                } else {
                    LazyVGrid(
                        columns: [GridItem(.adaptive(minimum: 240, maximum: 360), spacing: 16)],
                        spacing: 16
                    ) {
                        ForEach(model.visibleThemes) { theme in
                            ThemeCardView(theme: theme, model: model)
                        }
                    }
                }

                if let theme = model.selectedTheme {
                    ThemeDetailView(theme: theme, model: model, onExport: onExport)
                }
            }
        }
        .frame(minWidth: 0)
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: model.selectedSection == .recent ? "clock.badge.questionmark" : "shield.slash")
                .font(.system(size: 38, weight: .light))
                .foregroundStyle(VisualStyle.frost)
            Text(model.selectedSection == .recent ? "还没有最近使用的主题" : "没有匹配的主题")
                .font(.title3.weight(.semibold))
            Text("调整搜索或筛选条件，也可以导入 .codexskin 主题包。")
                .foregroundStyle(VisualStyle.muted)
        }
        .frame(maxWidth: .infinity, minHeight: 240)
        .accessibilityElement(children: .combine)
    }

    private var emptyDetail: some View {
        VStack(spacing: 10) {
            Image(systemName: "sidebar.right")
                .font(.system(size: 38, weight: .light))
                .foregroundStyle(VisualStyle.frost)
            Text("选择一个主题查看详情")
                .font(.title3.weight(.semibold))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(VisualStyle.panel.opacity(0.45))
        .accessibilityElement(children: .combine)
    }
}
