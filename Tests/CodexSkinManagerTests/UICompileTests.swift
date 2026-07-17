import CodexSkinManagerCore
import Foundation

enum UICompileTests {
    static func run() async throws {
        await MainActor.run {
            let directory = URL(fileURLWithPath: "/tmp/ui-theme", isDirectory: true)
            let theme = ThemeRecord(
                libraryID: "ui-theme",
                manifest: ThemeManifest(
                    schemaVersion: 1,
                    id: "ui-theme",
                    name: "UI Theme",
                    image: "background.png",
                    appearance: "dark"
                ),
                directoryURL: directory,
                imageURL: directory.appendingPathComponent("background.png"),
                isActive: false
            )
            let model = AppModel(
                catalog: FakeThemeCatalog(themes: [theme]),
                engine: FakeEngine(),
                defaults: UserDefaults(suiteName: "CodexSkinManagerUICompileTests")!
            )

            _ = ContentView(model: model)
            _ = ThemeCardView(theme: theme, model: model)
            _ = MenuBarContentView(model: model)
        }
        print("PASS: UICompileTests")
    }
}
