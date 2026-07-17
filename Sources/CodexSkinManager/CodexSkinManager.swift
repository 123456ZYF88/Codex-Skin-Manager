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
                Button("刷新主题库") { Task { await model.refresh() } }
                    .keyboardShortcut("r")
            }
        }

        MenuBarExtra("Codex Skin", systemImage: "paintpalette.fill") {
            MenuBarContentView(model: model)
        }
        .menuBarExtraStyle(.window)
    }
}
