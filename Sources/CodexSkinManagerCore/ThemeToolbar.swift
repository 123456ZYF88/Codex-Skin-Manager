import SwiftUI

package struct ThemeToolbar: View {
    @ObservedObject package var model: AppModel
    package let onImport: () -> Void
    package let onExport: () -> Void

    package init(model: AppModel, onImport: @escaping () -> Void, onExport: @escaping () -> Void) {
        self.model = model
        self.onImport = onImport
        self.onExport = onExport
    }

    package var body: some View {
        HStack(spacing: 10) {
            TextField("搜索主题", text: $model.searchText)
                .textFieldStyle(.roundedBorder)
                .frame(minWidth: 180, idealWidth: 240, maxWidth: 300)
                .accessibilityLabel("search")

            Picker("筛选", selection: $model.themeFilter) {
                ForEach(ThemeFilter.allCases) { filter in
                    Text(filter.title).tag(filter)
                }
            }
            .labelsHidden()
            .frame(width: 110)
            .accessibilityLabel("主题筛选")

            Picker("排序", selection: $model.themeSort) {
                ForEach(ThemeSort.allCases) { sort in
                    Text(sort.title).tag(sort)
                }
            }
            .labelsHidden()
            .frame(width: 110)
            .accessibilityLabel("主题排序")

            Spacer(minLength: 8)

            Button(action: onImport) {
                Label("导入主题", systemImage: "square.and.arrow.down")
            }
            .accessibilityLabel("导入新的 Codex 主题包")

            Button(action: onExport) {
                Label("导出主题", systemImage: "square.and.arrow.up")
            }
            .disabled(model.selectedTheme == nil || model.operation.isBusy)
            .accessibilityLabel("导出所选主题")

            Button {
                Task { await model.refresh() }
            } label: {
                Label("刷新", systemImage: "arrow.clockwise")
                    .labelStyle(.iconOnly)
            }
            .disabled(model.operation.isBusy)
            .accessibilityLabel("刷新主题库和引擎状态")
        }
        .disabled(model.operation.isBusy)
    }
}
