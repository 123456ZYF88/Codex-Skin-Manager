import CodexSkinManagerCore
import Foundation

enum UICompileTests {
    static func run() async throws {
        try appBundleDeclaresIcon()
        try themeExtensionInstallationIsExplicitAndAtomic()
        try sidebarUsesConcreteSelectionTags()
        try mainWindowUsesDedicatedWorkspaceViews()
        try themeCardsUseKeyboardFocusableSelectionButtons()
        try recentToolbarDoesNotExposeIgnoredFilter()
        try importAndExportUseSafeNativeWorkflows()
        try duplicateConfirmationShowsBothIdentities()
        try appCommandsUseTypedRequestsAndExpectedShortcuts()
        try menuBarUsesSharedStateAndLifecycleActions()
        try retryAvailabilityGetterIsPure()
        try accessibilityAndColdArmorVisualsStayRestrained()

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
            _ = ThemeLibraryView(model: model, onImport: {}, onExport: {}, onImportURLs: { _ in false })
            _ = ThemeDetailView(theme: theme, model: model, onExport: {})
            _ = ThemeToolbar(model: model, onImport: {}, onExport: {})
            _ = OperationBanner(model: model)
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

    private static func importAndExportUseSafeNativeWorkflows() throws {
        let contentSource = try String(
            contentsOf: projectRoot().appendingPathComponent("Sources/CodexSkinManagerCore/ContentView.swift"),
            encoding: .utf8
        )
        let librarySource = try String(
            contentsOf: projectRoot().appendingPathComponent("Sources/CodexSkinManagerCore/ThemeLibraryView.swift"),
            encoding: .utf8
        )
        let modelSource = try String(
            contentsOf: projectRoot().appendingPathComponent("Sources/CodexSkinManagerCore/AppModel.swift"),
            encoding: .utf8
        )

        try expect(librarySource.contains(".dropDestination(for: URL.self)"), "theme library must accept theme packages by drag and drop")
        try expect(contentSource.contains("importURLs(_ urls: [URL]) -> Bool"), "file picker and drops must share one URL import handler")
        try expect(
            modelSource.range(of: "startAccessingSecurityScopedResource()")!.lowerBound
                < modelSource.range(of: "ThemePackageDeferredStore.isRegularPackage(packageURL)")!.lowerBound,
            "the import security scope must begin before regular-file metadata is read"
        )
        try expect(contentSource.contains("model.beginImport(url)"), "ContentView must delegate import reservation to the shared coordinator")
        try expect(modelSource.contains("ThemePackageDeferredStore.stage(packageURL"), "duplicate imports must be staged before their security scope ends")
        try expect(modelSource.contains("Task { [self] in"), "import transactions must retain AppModel until their security scope is released")
        try expect(contentSource.contains("NSSavePanel"), "export must use the native save panel")
        try expect(
            contentSource.contains("allowedContentTypes = [.codexSkinPackage]"),
            "save panel must use the non-deprecated content-type API for .codexskin"
        )
        try expect(!contentSource.contains("allowedFileTypes"), "save panel must not use the deprecated file-type API")
    }

    private static func recentToolbarDoesNotExposeIgnoredFilter() throws {
        let source = try String(
            contentsOf: projectRoot().appendingPathComponent("Sources/CodexSkinManagerCore/ThemeToolbar.swift"),
            encoding: .utf8
        )
        try expect(
            source.contains("if model.selectedSection != .recent") && source.contains("Picker(\"筛选\""),
            "Recent must hide the filter control whose value is intentionally ignored"
        )
    }

    private static func duplicateConfirmationShowsBothIdentities() throws {
        for file in ["ContentView.swift", "MenuBarContentView.swift"] {
            let source = try String(
                contentsOf: projectRoot().appendingPathComponent("Sources/CodexSkinManagerCore/\(file)"),
                encoding: .utf8
            )
            try expect(
                source.contains("model.pendingReplacementConfirmationText"),
                "\(file) must render the shared incoming/existing duplicate identity text"
            )
        }
    }

    private static func appCommandsUseTypedRequestsAndExpectedShortcuts() throws {
        let appSource = try String(
            contentsOf: projectRoot().appendingPathComponent("Sources/CodexSkinManager/CodexSkinManager.swift"),
            encoding: .utf8
        )
        let modelSource = try String(
            contentsOf: projectRoot().appendingPathComponent("Sources/CodexSkinManagerCore/AppModel.swift"),
            encoding: .utf8
        )
        let contentSource = try String(
            contentsOf: projectRoot().appendingPathComponent("Sources/CodexSkinManagerCore/ContentView.swift"),
            encoding: .utf8
        )

        for shortcut in [
            ".keyboardShortcut(\"o\", modifiers: .command)",
            ".keyboardShortcut(\"e\", modifiers: [.command, .shift])",
            ".keyboardShortcut(.return, modifiers: .command)",
            ".keyboardShortcut(\"r\", modifiers: [.command, .shift])",
            ".keyboardShortcut(\"r\", modifiers: .command)",
            ".keyboardShortcut(\"f\", modifiers: .command)",
        ] {
            try expect(appSource.contains(shortcut), "App commands must declare shortcut \(shortcut)")
        }
        for command in ["importTheme", "exportTheme", "applySelected", "restoreOriginal", "refresh", "focusSearch"] {
            try expect(appSource.contains("model.request(.\(command))"), "App commands must publish typed request \(command)")
        }
        try expect(
            !appSource.contains("model.refresh()")
                && !appSource.contains("model.apply(")
                && !appSource.contains("model.restoreOriginal()"),
            "App commands must not bypass typed model requests"
        )
        try expect(modelSource.contains("package enum ManagerCommand: Equatable, Sendable"), "ManagerCommand must be typed and sendable")
        try expect(modelSource.contains("var commandRequest: (command: ManagerCommand, nonce: UUID)?"), "AppModel must publish a typed nonce request")
        try expect(modelSource.contains("package func request(_ command: ManagerCommand)"), "AppModel must own command publication")
        try expect(contentSource.contains(".onChange(of: model.commandRequest?.nonce)"), "ContentView must consume each command nonce once")
        try expect(
            modelSource.contains("package func consumeCommandRequest(nonce: UUID?) -> ManagerCommand?"),
            "AppModel must arbitrate command consumption across multiple windows"
        )
        try expect(
            contentSource.contains("model.consumeCommandRequest(nonce: nonce)"),
            "ContentView must claim a shared command before opening UI"
        )
        let librarySource = try String(
            contentsOf: projectRoot().appendingPathComponent("Sources/CodexSkinManagerCore/ThemeLibraryView.swift"),
            encoding: .utf8
        )
        let toolbarSource = try String(
            contentsOf: projectRoot().appendingPathComponent("Sources/CodexSkinManagerCore/ThemeToolbar.swift"),
            encoding: .utf8
        )
        try expect(
            contentSource.contains("@State private var commandPresentation = WindowCommandPresentationState()")
                && contentSource.contains("commandPresentation.reduce(claimed: command, nonce: nonce)")
                && contentSource.contains("searchFocusNonce: commandPresentation.searchFocusNonce"),
            "Only the winning ContentView must reduce a claimed command into window-local presentation"
        )
        try expect(
            librarySource.contains("searchFocusNonce: UUID?")
                && librarySource.contains("ThemeToolbar(")
                && librarySource.contains("searchFocusNonce: searchFocusNonce"),
            "ThemeLibraryView must pass the window-local focus trigger to ThemeToolbar"
        )
        try expect(
            toolbarSource.contains(".task(id: searchFocusNonce)")
                && !toolbarSource.contains("model.commandRequest"),
            "ThemeToolbar must observe only its window-local focus trigger"
        )
    }

    private static func menuBarUsesSharedStateAndLifecycleActions() throws {
        let source = try String(
            contentsOf: projectRoot().appendingPathComponent("Sources/CodexSkinManagerCore/MenuBarContentView.swift"),
            encoding: .utf8
        )

        try expect(source.contains("model.menuBarRecentThemes"), "Menu bar must use the model's three-item recent projection")
        try expect(source.contains("private var activeTheme: ThemeRecord?"), "Menu bar must show the active theme independently from selection")
        for stateText in ["主题运行中", "主题已暂停", "等待主题注入", "Codex 已停止"] {
            try expect(source.contains(stateText), "Menu bar must expose non-color status text for \(stateText)")
        }
        try expect(source.contains("Task { await model.pauseTheme() }"), "Menu bar pause must reuse AppModel lifecycle action")
        try expect(source.contains("Task { await model.restartTheme() }"), "Menu bar restart must reuse AppModel lifecycle action")
        try expect(!source.contains("model.selectedTheme"), "Menu bar activity must never be inferred from selection")
    }

    private static func accessibilityAndColdArmorVisualsStayRestrained() throws {
        let root = projectRoot()
        let menuSource = try String(
            contentsOf: root.appendingPathComponent("Sources/CodexSkinManagerCore/MenuBarContentView.swift"),
            encoding: .utf8
        )
        let bannerSource = try String(
            contentsOf: root.appendingPathComponent("Sources/CodexSkinManagerCore/OperationBanner.swift"),
            encoding: .utf8
        )
        let cardSource = try String(
            contentsOf: root.appendingPathComponent("Sources/CodexSkinManagerCore/ThemeCardView.swift"),
            encoding: .utf8
        )
        let dashboardSource = try String(
            contentsOf: root.appendingPathComponent("Sources/CodexSkinManagerCore/DashboardView.swift"),
            encoding: .utf8
        )
        let detailSource = try String(
            contentsOf: root.appendingPathComponent("Sources/CodexSkinManagerCore/ThemeDetailView.swift"),
            encoding: .utf8
        )
        let visualSource = try String(
            contentsOf: root.appendingPathComponent("Sources/CodexSkinManagerCore/VisualStyle.swift"),
            encoding: .utf8
        )

        try expect(menuSource.contains("@Environment(\\.accessibilityReduceMotion)"), "Animated menu progress must respect Reduce Motion")
        try expect(bannerSource.contains("@Environment(\\.accessibilityReduceMotion)"), "Animated operation progress must respect Reduce Motion")
        try expect(cardSource.contains("@FocusState") && cardSource.contains("isFocused"), "Theme cards must draw a visible keyboard focus ring")
        try expect(cardSource.contains("主题预览 \\(theme.manifest.name)"), "Theme card previews must expose their theme name")
        try expect(dashboardSource.contains("当前主题预览 \\(activeTheme?.manifest.name"), "Dashboard preview must expose the active theme name")
        try expect(detailSource.contains("主题预览 \\(theme.manifest.name)"), "Detail preview must expose its theme name")
        try expect(menuSource.contains(".accessibilityLabel") && bannerSource.contains(".accessibilityLabel"), "Icon-only and animated status controls need accessibility labels")

        for token in [
            "selection = Color(red: 0.27, green: 0.78, blue: 1.0)",
            "success = Color(red: 0.28, green: 0.92, blue: 0.73)",
            "warning = Color(red: 1.0, green: 0.66, blue: 0.24)",
            "panelStrong = Color(red: 0.04, green: 0.075, blue: 0.12).opacity(0.96)",
            "panelQuiet = Color(red: 0.045, green: 0.085, blue: 0.14).opacity(0.74)",
        ] {
            try expect(visualSource.contains(token), "VisualStyle must define semantic token \(token)")
        }
        try expect(visualSource.contains("for index in 0..<18"), "Manga burst must use only 18 rays")
        try expect(visualSource.contains("VisualStyle.selection.opacity(0.07)"), "Strong manga rays must be restrained")
        try expect(visualSource.contains(".white.opacity(0.02)"), "Minor manga rays must be restrained")
        try expect(cardSource.contains("isEmphasized"), "Only selected or active cards may receive ice emphasis")
        try expect(cardSource.contains("VisualStyle.panelQuiet"), "Ordinary theme cards must use the quiet panel treatment")
    }

    private static func retryAvailabilityGetterIsPure() throws {
        let source = try String(
            contentsOf: projectRoot().appendingPathComponent("Sources/CodexSkinManagerCore/AppModel.swift"),
            encoding: .utf8
        )
        try expect(
            source.contains("guard !operation.isBusy, let retryIntent else { return false }\n        return retryTargetExists(for: retryIntent)"),
            "retryAvailable must be a pure projection with no state mutation"
        )
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
                && buildScript.contains("/bin/cp \"$PROJECT_ROOT/EngineExtension/$extension\"")
                && buildScript.contains("/bin/chmod 700 \"$TEMP_APP/Contents/Resources/EngineExtension/$extension\""),
            "build must explicitly copy and harden only the trusted bundled extension filenames"
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
            engineInstall.contains("\"$ENGINE_SCRIPTS/.import-theme-pack-macos.sh.$$\"")
                && engineInstall.contains("\"$ENGINE_SCRIPTS/.restart-dream-skin-macos.sh.$$\"")
                && engineInstall.contains("/bin/rm -f \"$EXTENSION_TEMP\""),
            "failed extension installation must clean only an exact trusted temporary path"
        )
        try expect(
            installScript.contains("theme importing, switching, pausing, restoring, and restarting are unavailable"),
            "missing-engine warning must cover import and every unavailable lifecycle action"
        )
        try expect(!buildScript.contains("EngineExtension/*.sh"), "bundling must not discover extension scripts with a glob")
    }

    private static func projectRoot() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}
