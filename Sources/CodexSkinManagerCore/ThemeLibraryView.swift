import SwiftUI

package struct ThemeLibraryView: View {
    @ObservedObject package var model: AppModel
    package let onImport: () -> Void
    package let onExport: () -> Void
    package let onImportURLs: ([URL]) -> Bool
    package let searchFocusNonce: UUID?
    @State private var isImportTargeted = false

    package init(
        model: AppModel,
        onImport: @escaping () -> Void,
        onExport: @escaping () -> Void,
        onImportURLs: @escaping ([URL]) -> Bool,
        searchFocusNonce: UUID? = nil
    ) {
        self.model = model
        self.onImport = onImport
        self.onExport = onExport
        self.onImportURLs = onImportURLs
        self.searchFocusNonce = searchFocusNonce
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

            ThemeToolbar(
                model: model,
                onImport: onImport,
                onExport: onExport,
                searchFocusNonce: searchFocusNonce
            )

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
        .overlay {
            if isImportTargeted {
                WeaponPlateShape()
                    .stroke(VisualStyle.ice, style: StrokeStyle(lineWidth: 2, dash: [8, 5]))
                    .background(VisualStyle.ice.opacity(0.10))
                    .overlay {
                        Text("释放以导入主题包")
                            .font(.title3.weight(.bold))
                            .foregroundStyle(VisualStyle.frost)
                    }
                    .padding(16)
                    .allowsHitTesting(false)
            }
        }
        .dropDestination(for: URL.self) { urls, _ in
            onImportURLs(urls)
        } isTargeted: { isImportTargeted = $0 }
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
            Image(systemName: emptyStateSymbol)
                .font(.system(size: 38, weight: .light))
                .foregroundStyle(VisualStyle.frost)
            Text(emptyStateTitle)
                .font(.title3.weight(.semibold))
            Text(emptyStateMessage)
                .foregroundStyle(VisualStyle.muted)
            if model.selectedSection == .library && model.themes.isEmpty {
                Button("导入主题", action: onImport)
                    .buttonStyle(.borderedProminent)
            } else if model.selectedSection == .library {
                Button("清除筛选") {
                    model.searchText = ""
                    model.themeFilter = .all
                }
                .buttonStyle(.bordered)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 240)
        .accessibilityElement(children: .combine)
    }

    private var emptyStateSymbol: String {
        if model.selectedSection == .recent { return "clock.badge.questionmark" }
        return model.themes.isEmpty ? "shield.slash" : "line.3.horizontal.decrease.circle"
    }

    private var emptyStateTitle: String {
        if model.selectedSection == .recent { return "还没有最近使用的主题" }
        return model.themes.isEmpty ? "没有找到已安装主题" : "当前筛选没有匹配主题"
    }

    private var emptyStateMessage: String {
        if model.selectedSection == .recent { return "应用主题后会出现在这里" }
        return model.themes.isEmpty ? "导入 .codexskin 主题包以开始使用。" : "调整搜索或筛选条件后再试。"
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
        .background(VisualStyle.panelQuiet)
        .accessibilityElement(children: .combine)
    }
}
