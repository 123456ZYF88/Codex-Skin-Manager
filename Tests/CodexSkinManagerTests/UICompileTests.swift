import CodexSkinManagerCore
import Foundation

enum UICompileTests {
    static func run() async throws {
        try appBundleDeclaresIcon()
        try themeExtensionInstallationIsExplicitAndAtomic()
        try sidebarUsesConcreteSelectionTags()
        try mainWindowUsesDedicatedWorkspaceViews()
        try themeCardsUseKeyboardFocusableSelectionButtons()

        await MainActor.run {
            let theme = makeThemeRecord(id: "ui-theme", name: "UI Theme")
            let model = AppModel(
                catalog: FakeThemeCatalog(themes: [theme]),
                engine: FakeEngine(),
                defaults: UserDefaults(suiteName: "CodexSkinManagerUICompileTests")!
            )

            _ = ContentView(model: model)
            _ = ThemeCardView(theme: theme, model: model)
            _ = DashboardView(model: model, onOpenLibrary: {}, onRestore: {})
            _ = ThemeLibraryView(model: model, onImport: {}, onExport: {})
            _ = ThemeDetailView(theme: theme, model: model, onExport: {})
            _ = ThemeToolbar(model: model, onImport: {}, onExport: {})
            _ = OperationBanner(model: model, onRetry: {})
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
        try expect(
            buildScript.contains("import-theme-pack-macos.sh")
                && buildScript.contains("restart-dream-skin-macos.sh"),
            "The app bundler must copy the trusted importer and restart extensions"
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
            source.contains("selection: $model.selectedSection"),
            "Sidebar selection must bind the concrete section owned by AppModel"
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

    private static func mainWindowUsesDedicatedWorkspaceViews() throws {
        let contentSource = try String(
            contentsOf: projectRoot().appendingPathComponent("Sources/CodexSkinManagerCore/ContentView.swift"),
            encoding: .utf8
        )
        let librarySource = try String(
            contentsOf: projectRoot().appendingPathComponent("Sources/CodexSkinManagerCore/ThemeLibraryView.swift"),
            encoding: .utf8
        )

        for typeName in [
            "DashboardView",
            "ThemeLibraryView",
            "OperationBanner",
        ] {
            try expect(contentSource.contains(typeName), "ContentView must compose \(typeName)")
        }
        for typeName in ["ThemeToolbar", "ThemeDetailView"] {
            try expect(librarySource.contains(typeName), "ThemeLibraryView must compose \(typeName)")
            try expect(
                !contentSource.contains(typeName),
                "ContentView must not satisfy \(typeName) composition through comments or unused references"
            )
        }
        try expect(
            !contentSource.contains("private var themeGrid"),
            "ContentView must delegate theme layout to ThemeLibraryView"
        )
        try expect(
            !contentSource.contains("enum ManagerSection"),
            "ContentView must use the shared ManagerSection model"
        )
    }

    private static func themeCardsUseKeyboardFocusableSelectionButtons() throws {
        let source = try String(
            contentsOf: projectRoot().appendingPathComponent("Sources/CodexSkinManagerCore/ThemeCardView.swift"),
            encoding: .utf8
        )

        try expect(
            source.contains("Button(action: { model.selectTheme(theme) })"),
            "Theme cards must use a keyboard-focusable Button for selection"
        )
        try expect(source.contains(".buttonStyle(.plain)"), "Theme card selection buttons must preserve card styling")
        try expect(!source.contains(".onTapGesture"), "Theme card selection must not rely on pointer-only tap gestures")
        try expect(!source.contains("model.apply"), "Theme cards must select without applying themes")
    }

    private static func themeExtensionInstallationIsExplicitAndAtomic() throws {
        let projectRoot = projectRoot()
        let restartScript = try String(
            contentsOf: projectRoot.appendingPathComponent("EngineExtension/restart-dream-skin-macos.sh"),
            encoding: .utf8
        )
        let buildScript = try String(
            contentsOf: projectRoot.appendingPathComponent("Scripts/build-app.sh"),
            encoding: .utf8
        )
        let installScript = try String(
            contentsOf: projectRoot.appendingPathComponent("Scripts/install-app.sh"),
            encoding: .utf8
        )

        try expect(
            restartScript.contains(". \"$SCRIPT_DIR/common-macos.sh\"")
                && restartScript.contains("stop_codex true")
                && restartScript.contains("exec \"$SCRIPT_DIR/start-dream-skin-macos.sh\" --restart-existing"),
            "restart wrapper must use only trusted lifecycle helpers"
        )
        let sourcedHelpers = restartScript
            .split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { $0.hasPrefix(". ") || $0.hasPrefix("source ") }
        try expect(
            sourcedHelpers == [". \"$SCRIPT_DIR/common-macos.sh\""],
            "restart wrapper must source only common-macos.sh"
        )
        try expect(
            !restartScript.contains("pgrep") && !restartScript.contains("pkill") && !restartScript.contains("/bin/kill"),
            "restart wrapper must delegate process discovery and termination to common-macos.sh"
        )
        try expect(
            buildScript.contains("for extension in import-theme-pack-macos.sh restart-dream-skin-macos.sh; do")
                && buildScript.contains("/bin/cp \"$PROJECT_ROOT/EngineExtension/$extension\""),
            "build must explicitly copy only the trusted extension filenames"
        )

        let engineInstall = installScript.components(separatedBy: "ENGINE_ROOT=").last ?? ""
        try expect(
            engineInstall.contains("for extension in import-theme-pack-macos.sh restart-dream-skin-macos.sh; do")
                && engineInstall.contains("EXTENSION_TEMP=\"$ENGINE_SCRIPTS/.$extension.$$\"")
                && engineInstall.contains("/usr/bin/install -m 700 \"$EXTENSION_SOURCE\" \"$EXTENSION_TEMP\"")
                && engineInstall.contains("/bin/chmod 700 \"$EXTENSION_TEMP\"")
                && engineInstall.contains("/bin/mv -f \"$EXTENSION_TEMP\" \"$ENGINE_SCRIPTS/$extension\""),
            "install must use a 0700 temporary file and atomic per-extension replacement"
        )
        try expect(
            !buildScript.contains("EngineExtension/*.sh")
                && !engineInstall.contains("*")
                && !engineInstall.contains("/bin/rm")
                && !engineInstall.contains("rm -rf"),
            "extension installation must not use globs or delete unrelated engine scripts"
        )
    }

    private static func projectRoot() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}
