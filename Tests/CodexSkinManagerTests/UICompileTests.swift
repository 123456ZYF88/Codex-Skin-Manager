import CodexSkinManagerCore
import Foundation

enum UICompileTests {
    static func run() async throws {
        try appBundleDeclaresIcon()
        try sidebarUsesConcreteSelectionTags()

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

    private static func appBundleDeclaresIcon() throws {
        let testFile = URL(fileURLWithPath: #filePath)
        let projectRoot = testFile
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let infoURL = projectRoot.appendingPathComponent("Resources/Info.plist")
        let plist = try PropertyListSerialization.propertyList(
            from: Data(contentsOf: infoURL),
            options: [],
            format: nil
        ) as? [String: Any]

        try expect(
            plist?["CFBundleIconFile"] as? String == "AppIcon",
            "Info.plist must declare AppIcon"
        )
        try expect(
            FileManager.default.fileExists(
                atPath: projectRoot.appendingPathComponent("Resources/AppIcon-1024.png").path
            ),
            "The 1024px icon source must be committed"
        )
        try expect(
            FileManager.default.fileExists(
                atPath: projectRoot.appendingPathComponent("Resources/AppIcon.icns").path
            ),
            "The generated ICNS resource must be committed"
        )

        let buildScript = try String(
            contentsOf: projectRoot.appendingPathComponent("Scripts/build-app.sh"),
            encoding: .utf8
        )
        try expect(
            buildScript.contains("Resources/AppIcon.icns"),
            "The app bundler must copy AppIcon.icns"
        )
    }

    private static func sidebarUsesConcreteSelectionTags() throws {
        let testFile = URL(fileURLWithPath: #filePath)
        let projectRoot = testFile
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let sourceURL = projectRoot
            .appendingPathComponent("Sources/CodexSkinManagerCore/ContentView.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)

        try expect(
            source.contains("@State private var selectedSection: ManagerSection = .library"),
            "Sidebar selection must always have a concrete section"
        )
        try expect(
            source.contains(".tag(section)"),
            "Sidebar rows must use concrete tags that match the selection binding"
        )
        try expect(
            !source.contains(".tag(Optional(section))"),
            "Optional sidebar tags prevent NavigationSplitView rows from selecting"
        )
    }
}
