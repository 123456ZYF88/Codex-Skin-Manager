import CodexSkinManagerCore
import SwiftUI

@main
struct CodexSkinManagerApp: App {
    @StateObject private var model: AppModel

    init() {
        _model = StateObject(wrappedValue: AppModel.live())
    }

    var body: some Scene {
        WindowGroup("Codex Skin Manager", id: "main") {
            ContentView(model: model)
        }
        .defaultSize(width: 1040, height: 720)
        .commands {
            CommandMenu("主题") {
                Button("导入主题…") { model.request(.importTheme) }
                    .keyboardShortcut("o", modifiers: .command)
                    .disabled(model.operation.isBusy)
                Button("导出所选主题…") { model.request(.exportTheme) }
                    .keyboardShortcut("e", modifiers: [.command, .shift])
                    .disabled(model.selectedTheme == nil || model.operation.isBusy)

                Divider()

                Button("应用所选主题") { model.request(.applySelected) }
                    .keyboardShortcut(.return, modifiers: .command)
                    .disabled(model.selectedTheme == nil || model.operation.isBusy)
                Button("恢复 Codex 原版…") { model.request(.restoreOriginal) }
                    .keyboardShortcut("r", modifiers: [.command, .shift])
                    .disabled(model.operation.isBusy)

                Divider()

                Button("刷新主题库") { model.request(.refresh) }
                    .keyboardShortcut("r", modifiers: .command)
                    .disabled(model.operation.isBusy)
                Button("搜索主题") { model.request(.focusSearch) }
                    .keyboardShortcut("f", modifiers: .command)
            }
        }

        MenuBarExtra("Codex Skin", systemImage: "paintpalette.fill") {
            MenuBarContentView(model: model)
        }
        .menuBarExtraStyle(.window)
    }
}
