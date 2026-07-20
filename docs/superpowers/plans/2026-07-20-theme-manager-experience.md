# Codex Skin Manager Theme Library Experience Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a native macOS status dashboard and searchable list-detail theme library with verified apply, restart consent, drag import, safe export, lifecycle controls, shortcuts, and responsive cold-armor styling.

**Architecture:** Keep `AppModel` as the only UI state owner and `EngineBridge` as the only Dream Skin command boundary. Split the current large `ContentView` into focused SwiftUI views, add a separately testable `ThemePackageExporter`, and extend the guarded engine protocol for pause/restart without allowing views to execute scripts directly.

**Tech Stack:** Swift 6 toolchain, Swift language mode 5, SwiftUI, Foundation, AppKit, Swift Package Manager, existing Bash Dream Skin engine scripts, `/usr/bin/zip` and `/usr/bin/unzip` invoked through typed `ProcessRunner` arguments.

## Global Constraints

- Minimum platform remains macOS 13.
- Do not add third-party package dependencies, fonts, icons, screenshots, or visual assets.
- Keep all network access out of this release; no online marketplace, remote download, analytics, or updater.
- Defer theme deletion, multi-asset Wangnov-compatible packages, AI theme design, and self-update flows; this release only manages installed compact themes plus local import/export.
- Keep the existing compact `.codexskin` contract: exactly one `theme.json` and one PNG/JPEG/WebP image, flat safe filenames, archive at most 20 MiB, expanded payload at most 32 MiB.
- Never execute or export theme-provided CSS, JavaScript, shell scripts, binaries, symlinks, or remote URLs.
- Do not modify Codex, `app.asar`, the official app signature, account data, model configuration, API keys, or Base URLs.
- Preserve existing icon resources, menu-bar support, restore confirmation, recent-theme persistence, and `ProcessRunner` output limits.
- Distinguish selected theme, last-used theme, and runtime-verified active theme in both model and UI.
- Support `1024×700`, `1440×900`, and wider windows without overlap, clipping, or an empty detail column.
- Respect Reduce Motion, keyboard navigation, VoiceOver labels, and non-color state indicators.
- Use TDD for each behavior change and commit after every independently passing task.

---

## File Structure

### Files to create

- `Sources/CodexSkinManagerCore/ThemeLibraryModels.swift` — navigation, filter, and sort enums plus pure theme-query logic.
- `Sources/CodexSkinManagerCore/ThemePackageExporter.swift` — safe deterministic compact-package export through typed process requests.
- `Sources/CodexSkinManagerCore/DashboardView.swift` — active-theme hero, engine status, and lifecycle controls.
- `Sources/CodexSkinManagerCore/ThemeLibraryView.swift` — searchable/filterable list or gallery and selection handling.
- `Sources/CodexSkinManagerCore/ThemeDetailView.swift` — large preview, metadata, active/selected distinction, and apply/export actions.
- `Sources/CodexSkinManagerCore/ThemeToolbar.swift` — import, export, refresh, search, filter, and sort controls.
- `Sources/CodexSkinManagerCore/OperationBanner.swift` — persistent operation progress, result, retry, and copy-error presentation.
- `EngineExtension/restart-dream-skin-macos.sh` — guarded explicit Codex restart followed by Dream Skin start.
- `Tests/CodexSkinManagerTests/ThemeLibraryQueryTests.swift` — pure search/filter/sort tests.
- `Tests/CodexSkinManagerTests/ThemePackageExporterTests.swift` — real ZIP structure, privacy, and replace-safety tests.

### Files to modify

- `Sources/CodexSkinManagerCore/ThemeModels.swift` — keep theme and engine data contracts; no view state remains here.
- `Sources/CodexSkinManagerCore/AppModel.swift` — selection, query state, restart consent, lifecycle actions, export action, verification, and retry intent.
- `Sources/CodexSkinManagerCore/EngineBridge.swift` — deep status, pause, and restart typed commands.
- `Sources/CodexSkinManagerCore/ContentView.swift` — reduce to navigation composition, import/export panels, drag handling, and confirmations.
- `Sources/CodexSkinManagerCore/MenuBarContentView.swift` — consume the same active status and limit recent menu rows to three.
- `Sources/CodexSkinManagerCore/ThemeCardView.swift` — make the narrow-layout gallery card selection-only.
- `Sources/CodexSkinManagerCore/VisualStyle.swift` — lower manga-ray intensity and add semantic panel/selection colors.
- `Sources/CodexSkinManager/CodexSkinManager.swift` — keyboard commands and `960×640` minimum window sizing.
- `EngineExtension/import-theme-pack-macos.sh` — add non-mutating `--validate-only` support for exported-package verification.
- `Scripts/build-app.sh` — bundle both engine extension scripts.
- `Scripts/install-app.sh` — atomically install both engine extension scripts when the engine exists.
- `Resources/Info.plist` — bump app version/build after the feature passes.
- `Tests/CodexSkinManagerTests/AppModelTests.swift` — model verification, consent, lifecycle, export, retry, and shared fake updates.
- `Tests/CodexSkinManagerTests/EngineBridgeTests.swift` — exact deep-status/pause/restart argument mapping.
- `Tests/CodexSkinManagerTests/UICompileTests.swift` — compile and structural assertions for all new views, drag import, shortcuts, and confirmations.
- `Tests/CodexSkinManagerTests/TestMain.swift` — run the two new suites.
- `README.md` — document the new library, export, drag import, shortcuts, and deferred online-market scope.

---

### Task 1: Add pure theme query models and explicit selection state

**Files:**
- Create: `Sources/CodexSkinManagerCore/ThemeLibraryModels.swift`
- Create: `Tests/CodexSkinManagerTests/ThemeLibraryQueryTests.swift`
- Modify: `Sources/CodexSkinManagerCore/AppModel.swift`
- Modify: `Tests/CodexSkinManagerTests/TestMain.swift`
- Modify: `Tests/CodexSkinManagerTests/AppModelTests.swift`
- Modify: `Tests/CodexSkinManagerTests/TestSupport.swift`

**Interfaces:**
- Produces: `ManagerSection`, `ThemeFilter`, `ThemeSort`, and `ThemeLibraryQuery.filtered(themes:recentIDs:) -> [ThemeRecord]`.
- Produces: `AppModel.selectedSection`, `selectedThemeID`, `searchText`, `themeFilter`, `themeSort`, `visibleThemes`, `selectedTheme`, and `selectTheme(_:)`.
- Consumes: existing `ThemeRecord`, `recentThemeIDs`, and `UserDefaults` persistence.

- [ ] **Step 1: Write the failing pure-query tests**

Add the suite and register it before `AppModelTests`:

```swift
enum ThemeLibraryQueryTests {
    static func run() throws {
        try searchesNameAndIDCaseInsensitively()
        try filtersAppearanceAndRecents()
        try sortsByNameAndRecentOrder()
        print("PASS: ThemeLibraryQueryTests")
    }

    private static func searchesNameAndIDCaseInsensitively() throws {
        let themes = [
            makeThemeRecord(id: "frost-dragon", name: "寒龙子", appearance: "dark"),
            makeThemeRecord(id: "jade-palace", name: "碧落金阙", appearance: "light"),
        ]
        let byName = ThemeLibraryQuery(searchText: "寒龙", filter: .all, sort: .name)
            .filtered(themes: themes, recentIDs: [])
        let byID = ThemeLibraryQuery(searchText: "JADE", filter: .all, sort: .name)
            .filtered(themes: themes, recentIDs: [])
        try expect(byName.map(\.libraryID) == ["frost-dragon"], "name search mismatch")
        try expect(byID.map(\.libraryID) == ["jade-palace"], "id search mismatch")
    }

    private static func filtersAppearanceAndRecents() throws {
        let themes = [
            makeThemeRecord(id: "dark", name: "Dark", appearance: "dark"),
            makeThemeRecord(id: "light", name: "Light", appearance: "light"),
            makeThemeRecord(id: "auto", name: "Auto", appearance: nil),
        ]
        let light = ThemeLibraryQuery(searchText: "", filter: .light, sort: .name)
            .filtered(themes: themes, recentIDs: ["auto", "dark"])
        let recent = ThemeLibraryQuery(searchText: "", filter: .recent, sort: .recent)
            .filtered(themes: themes, recentIDs: ["auto", "dark"])
        try expect(light.map(\.libraryID) == ["light"], "light filter mismatch")
        try expect(recent.map(\.libraryID) == ["auto", "dark"], "recent filter mismatch")
    }

    private static func sortsByNameAndRecentOrder() throws {
        let themes = [
            makeThemeRecord(id: "b", name: "Beta", appearance: "dark"),
            makeThemeRecord(id: "a", name: "Alpha", appearance: "dark"),
        ]
        let named = ThemeLibraryQuery(searchText: "", filter: .all, sort: .name)
            .filtered(themes: themes, recentIDs: ["b", "a"])
        let recent = ThemeLibraryQuery(searchText: "", filter: .all, sort: .recent)
            .filtered(themes: themes, recentIDs: ["b", "a"])
        try expect(named.map(\.libraryID) == ["a", "b"], "name sort mismatch")
        try expect(recent.map(\.libraryID) == ["b", "a"], "recent sort mismatch")
    }
}
```

Add this reusable fixture to `TestSupport.swift`; this suite and every later suite must call the same helper so theme IDs, paths, and activity state stay consistent:

```swift
func makeThemeRecord(
    id: String,
    name: String? = nil,
    appearance: String? = "dark",
    isActive: Bool = false
) -> ThemeRecord {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("CodexSkinManagerTests-\(id)", isDirectory: true)
    return ThemeRecord(
        libraryID: id,
        manifest: ThemeManifest(
            schemaVersion: 1,
            id: id,
            name: name ?? id,
            image: "background.png",
            appearance: appearance
        ),
        directoryURL: directory,
        imageURL: directory.appendingPathComponent("background.png"),
        isActive: isActive
    )
}
```

- [ ] **Step 2: Run the tests to verify RED**

Run: `/bin/bash Scripts/test.sh`

Expected: compile failure because `ThemeLibraryQuery`, `ThemeFilter`, and `ThemeSort` do not exist.

- [ ] **Step 3: Implement the pure query types**

Create `ThemeLibraryModels.swift`:

```swift
import Foundation

package enum ManagerSection: String, CaseIterable, Identifiable, Sendable {
    case dashboard
    case library
    case recent

    package var id: String { rawValue }
    package var title: String {
        switch self {
        case .dashboard: "首页"
        case .library: "主题库"
        case .recent: "最近使用"
        }
    }
    package var symbol: String {
        switch self {
        case .dashboard: "house"
        case .library: "rectangle.grid.1x2"
        case .recent: "clock.arrow.circlepath"
        }
    }
}

package enum ThemeFilter: String, CaseIterable, Identifiable, Sendable {
    case all, dark, light, automatic, recent
    package var id: String { rawValue }
    package var title: String {
        switch self {
        case .all: "全部"
        case .dark: "深色"
        case .light: "明亮"
        case .automatic: "自动"
        case .recent: "最近使用"
        }
    }
}

package enum ThemeSort: String, CaseIterable, Identifiable, Sendable {
    case recent, name
    package var id: String { rawValue }
    package var title: String { self == .recent ? "最近使用" : "名称" }
}

package struct ThemeLibraryQuery: Equatable, Sendable {
    package var searchText: String
    package var filter: ThemeFilter
    package var sort: ThemeSort

    package func filtered(themes: [ThemeRecord], recentIDs: [String]) -> [ThemeRecord] {
        let needle = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        let recentIndex = Dictionary(uniqueKeysWithValues: recentIDs.enumerated().map { ($1, $0) })
        let matches = themes.filter { theme in
            let searchMatches = needle.isEmpty
                || theme.manifest.name.localizedCaseInsensitiveContains(needle)
                || theme.manifest.id.localizedCaseInsensitiveContains(needle)
                || theme.libraryID.localizedCaseInsensitiveContains(needle)
            guard searchMatches else { return false }
            switch filter {
            case .all: return true
            case .dark: return theme.manifest.appearance == "dark"
            case .light: return theme.manifest.appearance == "light"
            case .automatic: return theme.manifest.appearance != "dark" && theme.manifest.appearance != "light"
            case .recent: return recentIndex[theme.libraryID] != nil
            }
        }
        return matches.sorted { left, right in
            if left.isActive != right.isActive { return left.isActive }
            if sort == .recent {
                let leftIndex = recentIndex[left.libraryID] ?? Int.max
                let rightIndex = recentIndex[right.libraryID] ?? Int.max
                if leftIndex != rightIndex { return leftIndex < rightIndex }
            }
            let order = left.manifest.name.localizedStandardCompare(right.manifest.name)
            if order != .orderedSame { return order == .orderedAscending }
            return left.libraryID.localizedStandardCompare(right.libraryID) == .orderedAscending
        }
    }
}
```

- [ ] **Step 4: Add AppModel selection/query state and retention**

Add these published properties and computed values:

```swift
@Published package var selectedSection: ManagerSection = .dashboard
@Published package var selectedThemeID: String?
@Published package var searchText = ""
@Published package var themeFilter: ThemeFilter = .all
@Published package var themeSort: ThemeSort = .recent

package var visibleThemes: [ThemeRecord] {
    let effectiveFilter: ThemeFilter = selectedSection == .recent ? .recent : themeFilter
    return ThemeLibraryQuery(searchText: searchText, filter: effectiveFilter, sort: themeSort)
        .filtered(themes: themes, recentIDs: recentThemeIDs)
}

package var selectedTheme: ThemeRecord? {
    guard let selectedThemeID else { return nil }
    return themes.first { $0.libraryID == selectedThemeID }
}

package func selectTheme(_ theme: ThemeRecord?) {
    selectedThemeID = theme?.libraryID
}
```

At the end of `reloadState()`, preserve a valid selection, otherwise select the active theme, then the first visible theme:

```swift
let available = Set(themes.map(\.libraryID))
if let selectedThemeID, available.contains(selectedThemeID) {
    // Preserve the user's inspected theme even when it is not active.
} else {
    selectedThemeID = themes.first(where: \.isActive)?.libraryID ?? themes.first?.libraryID
}
```

Increase stored recents to eight in `recordRecent` and `pruneRecentThemes`; expose `menuBarRecentThemes` as `Array(recentThemes.prefix(3))` so the menu remains compact.

- [ ] **Step 5: Add model tests for selection versus activity**

Add a test that selects an inactive theme and asserts `selectedThemeID` changes while `themes.first(where: \.isActive)` does not. Add a refresh test that removes the selected theme from `FakeThemeCatalog` and asserts selection falls back to the active or first theme.

- [ ] **Step 6: Run all tests to verify GREEN**

Run: `/bin/bash Scripts/test.sh`

Expected: all existing suites plus `ThemeLibraryQueryTests` pass.

- [ ] **Step 7: Commit**

```bash
git add Sources/CodexSkinManagerCore/ThemeLibraryModels.swift Sources/CodexSkinManagerCore/AppModel.swift Tests/CodexSkinManagerTests/ThemeLibraryQueryTests.swift Tests/CodexSkinManagerTests/AppModelTests.swift Tests/CodexSkinManagerTests/TestSupport.swift Tests/CodexSkinManagerTests/TestMain.swift
git commit -m "Add theme library query state"
```

---

### Task 2: Require restart consent and verify the applied theme

**Files:**
- Modify: `Sources/CodexSkinManagerCore/AppModel.swift`
- Modify: `Sources/CodexSkinManagerCore/EngineBridge.swift`
- Modify: `Tests/CodexSkinManagerTests/AppModelTests.swift`
- Modify: `Tests/CodexSkinManagerTests/EngineBridgeTests.swift`

**Interfaces:**
- Produces: `AppModel.pendingRestartThemeID`, `confirmPendingRestartApply()`, and `cancelPendingRestartApply()`.
- Changes: `EngineBridge.status()` calls `status-dream-skin-macos.sh --json --deep`.
- Guarantees: `.succeeded("已应用 …")` is emitted only when the target library record is active and engine status is healthy.

- [ ] **Step 1: Write failing restart-consent and verification tests**

Add tests covering these exact cases:

```swift
@MainActor
private static func runningWithoutCDPRequiresConsent() async throws {
    let catalog = FakeThemeCatalog(themes: [makeThemeRecord(id: "cold", name: "Cold")])
    let engine = FakeEngine()
    await engine.setStatus(EngineStatus(
        session: "off", port: 9341, injectorAlive: false,
        cdpOk: false, codexRunning: true, themeName: ""
    ))
    let model = AppModel(catalog: catalog, engine: engine, defaults: makeDefaults())
    await model.refresh()
    await model.apply(catalog.themes[0])
    try expect(model.pendingRestartThemeID == "cold", "restart consent must retain the theme id")
    try expect((await engine.snapshot()).switchedIDs.isEmpty, "theme must not switch before consent")
}

@MainActor
private static func applyRequiresVerifiedTarget() async throws {
    let theme = makeThemeRecord(id: "target", name: "Target")
    let catalog = FakeThemeCatalog(themes: [theme])
    let engine = FakeEngine(onSwitch: { _ in })
    let model = AppModel(catalog: catalog, engine: engine, defaults: makeDefaults())
    await model.refresh()
    await model.apply(theme)
    try expect(model.operation == .failed("主题切换完成，但未验证到目标主题。"), "unverified apply must fail")
}
```

Update the success fake so `onSwitch` calls `catalog.setActiveLibraryID(id)` and the subsequent catalog load marks only that record active.

- [ ] **Step 2: Verify RED**

Run: `/bin/bash Scripts/test.sh`

Expected: compile failure for missing restart-consent properties and behavior failure for unverified apply.

- [ ] **Step 3: Make engine status a deep probe**

Change only the typed arguments:

```swift
let result = try await runScript(
    named: "status-dream-skin-macos.sh",
    arguments: ["--json", "--deep"],
    timeout: 8
)
```

Update `EngineBridgeTests.mapsTypedCommandsWithoutShellInterpolation()` to expect `requests[0].arguments == ["--json", "--deep"]`.

- [ ] **Step 4: Implement consent and verified apply**

Add:

```swift
@Published package private(set) var pendingRestartThemeID: String?

package func apply(_ theme: ThemeRecord) async {
    guard !operation.isBusy else { return }
    let current = (try? await engine.status()) ?? status
    status = current
    if current?.codexRunning == true && current?.cdpOk != true {
        pendingRestartThemeID = theme.libraryID
        operation = .idle
        return
    }
    await performApply(theme)
}

package func confirmPendingRestartApply() async {
    guard !operation.isBusy,
          let id = pendingRestartThemeID,
          let theme = themes.first(where: { $0.libraryID == id })
    else { return }
    pendingRestartThemeID = nil
    await performApply(theme)
}

package func cancelPendingRestartApply() {
    guard !operation.isBusy else { return }
    pendingRestartThemeID = nil
}

private func performApply(_ theme: ThemeRecord) async {
    operation = .switching
    do {
        try await engine.switchTheme(libraryID: theme.libraryID)
        try await reloadState()
        guard status?.injectorAlive == true,
              status?.cdpOk == true,
              themes.first(where: { $0.libraryID == theme.libraryID })?.isActive == true
        else {
            throw ManagerError.invalidResponse("主题切换完成，但未验证到目标主题。")
        }
        recordRecent(theme.libraryID)
        selectedThemeID = theme.libraryID
        operation = .succeeded("已应用 \(theme.manifest.name)")
    } catch {
        operation = .failed(message(for: error))
    }
}
```

The fake catalog must rebuild immutable `ThemeRecord` values with `isActive` derived from its locked `activeLibraryID`; do not mutate UI state from the engine actor.

- [ ] **Step 5: Add cancel/confirm tests and run GREEN**

Test that cancel leaves the engine untouched, and confirm switches once, marks the target active, records the recent ID, and clears `pendingRestartThemeID`.

Run: `/bin/bash Scripts/test.sh`

Expected: all suites pass.

- [ ] **Step 6: Commit**

```bash
git add Sources/CodexSkinManagerCore/AppModel.swift Sources/CodexSkinManagerCore/EngineBridge.swift Tests/CodexSkinManagerTests/AppModelTests.swift Tests/CodexSkinManagerTests/EngineBridgeTests.swift
git commit -m "Verify theme application before activation"
```

---

### Task 3: Add pause and explicit restart lifecycle controls

**Files:**
- Create: `EngineExtension/restart-dream-skin-macos.sh`
- Modify: `Sources/CodexSkinManagerCore/EngineBridge.swift`
- Modify: `Sources/CodexSkinManagerCore/AppModel.swift`
- Modify: `Scripts/build-app.sh`
- Modify: `Scripts/install-app.sh`
- Modify: `Tests/CodexSkinManagerTests/EngineBridgeTests.swift`
- Modify: `Tests/CodexSkinManagerTests/AppModelTests.swift`
- Modify: `Tests/CodexSkinManagerTests/UICompileTests.swift`

**Interfaces:**
- Changes `EngineControlling` to include `pauseTheme() async throws` and `restartTheme() async throws`.
- Produces `AppModel.pauseTheme()` and `restartTheme()`.
- Adds `ManagerOperation.pausing` and `.restarting` as busy states.

- [ ] **Step 1: Write failing exact-command tests**

Extend the recording runner sequence and assert:

```swift
try await bridge.pauseTheme()
try await bridge.restartTheme()
try expect(requests[pauseIndex].executable.lastPathComponent == "pause-dream-skin-macos.sh", "pause script mismatch")
try expect(requests[pauseIndex].arguments.isEmpty, "pause must not interpolate arguments")
try expect(requests[restartIndex].executable.lastPathComponent == "restart-dream-skin-macos.sh", "restart script mismatch")
try expect(requests[restartIndex].arguments.isEmpty, "restart must not interpolate arguments")
```

Add model tests that a busy switch blocks pause/restart, successful pause refreshes status, and successful restart refreshes status.

- [ ] **Step 2: Verify RED**

Run: `/bin/bash Scripts/test.sh`

Expected: compile failure because the protocol and model lifecycle methods are missing.

- [ ] **Step 3: Implement protocol and bridge methods**

Add to `EngineControlling` and `EngineBridge`:

```swift
func pauseTheme() async throws
func restartTheme() async throws

package func pauseTheme() async throws {
    let result = try await runScript(named: "pause-dream-skin-macos.sh", arguments: [], timeout: 30)
    try requireSuccess(result)
}

package func restartTheme() async throws {
    let result = try await runScript(named: "restart-dream-skin-macos.sh", arguments: [], timeout: 90)
    try requireSuccess(result)
}
```

Update every fake engine with counters for pause/restart and no-op implementations.

- [ ] **Step 4: Create the guarded restart extension**

Create exactly this wrapper and keep all process discovery/termination inside trusted upstream helpers:

```bash
#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd -P)"
. "$SCRIPT_DIR/common-macos.sh"

discover_codex_app
require_macos_runtime
ensure_state_root

if codex_is_running; then
  stop_codex true
fi

exec "$SCRIPT_DIR/start-dream-skin-macos.sh" --restart-existing
```

- [ ] **Step 5: Bundle and atomically install both extension scripts**

Replace the one-off import copy in `build-app.sh` with a loop over explicit filenames:

```bash
for extension in import-theme-pack-macos.sh restart-dream-skin-macos.sh; do
  /bin/cp "$PROJECT_ROOT/EngineExtension/$extension" \
    "$TEMP_APP/Contents/Resources/EngineExtension/$extension"
  /bin/chmod 700 "$TEMP_APP/Contents/Resources/EngineExtension/$extension"
done
```

In `install-app.sh`, install to validated `ENGINE_SCRIPTS` through per-file temporary paths and atomic `mv`; do not use globs or delete unrelated engine scripts.

- [ ] **Step 6: Implement model operations**

Add `.pausing` and `.restarting` to `ManagerOperation.isBusy`, then implement:

```swift
package func pauseTheme() async {
    guard !operation.isBusy else { return }
    operation = .pausing
    do {
        try await engine.pauseTheme()
        try await reloadState()
        operation = .succeeded("主题已暂停")
    } catch {
        operation = .failed(message(for: error))
    }
}

package func restartTheme() async {
    guard !operation.isBusy else { return }
    operation = .restarting
    do {
        try await engine.restartTheme()
        try await reloadState()
        operation = .succeeded("Codex 已重新启动并应用主题")
    } catch {
        operation = .failed(message(for: error))
    }
}
```

- [ ] **Step 7: Verify shell syntax, tests, and bundle declarations**

Run:

```bash
/bin/bash -n EngineExtension/restart-dream-skin-macos.sh
/bin/bash Scripts/test.sh
```

Expected: shell syntax exits 0; all tests pass; `UICompileTests` confirms both extension filenames are copied by `build-app.sh`.

- [ ] **Step 8: Commit**

```bash
git add EngineExtension/restart-dream-skin-macos.sh Sources/CodexSkinManagerCore/EngineBridge.swift Sources/CodexSkinManagerCore/AppModel.swift Scripts/build-app.sh Scripts/install-app.sh Tests/CodexSkinManagerTests/EngineBridgeTests.swift Tests/CodexSkinManagerTests/AppModelTests.swift Tests/CodexSkinManagerTests/UICompileTests.swift
git commit -m "Add theme lifecycle controls"
```

---

### Task 4: Build and validate safe theme export

**Files:**
- Create: `Sources/CodexSkinManagerCore/ThemePackageExporter.swift`
- Create: `Tests/CodexSkinManagerTests/ThemePackageExporterTests.swift`
- Modify: `EngineExtension/import-theme-pack-macos.sh`
- Modify: `Sources/CodexSkinManagerCore/EngineBridge.swift`
- Modify: `Sources/CodexSkinManagerCore/AppModel.swift`
- Modify: `Tests/CodexSkinManagerTests/TestMain.swift`
- Modify: `Tests/CodexSkinManagerTests/AppModelTests.swift`

**Interfaces:**
- Produces `ThemePackageExporting.export(theme:to:) async throws -> URL`.
- Produces `ThemePackageExporter(runner:)` using typed `/usr/bin/zip` and `/usr/bin/unzip` requests.
- Produces `EngineControlling.validateThemePackage(packageURL:) async throws` backed by importer `--validate-only`.
- Produces `AppModel.exportSelectedTheme(to:)` and `ManagerOperation.exporting`.

- [ ] **Step 1: Write the failing exporter suite**

The suite must create a real temporary theme using a 1×1 PNG payload, export it, and inspect the archive:

```swift
enum ThemePackageExporterTests {
    static func run() async throws {
        try await exportsExactlyManifestAndImage()
        try await replacesDestinationWithoutStaleEntries()
        print("PASS: ThemePackageExporterTests")
    }

    private static func exportsExactlyManifestAndImage() async throws {
        let root = try makeTemporaryDirectory(prefix: "exporter")
        defer { try? FileManager.default.removeItem(at: root) }
        let theme = try writeExportTheme(in: root, id: "safe-theme")
        let destination = root.appendingPathComponent("safe-theme.codexskin")
        let output = try await ThemePackageExporter().export(theme: theme, to: destination)
        let entries = try await ProcessRunner().run(CommandRequest(
            executable: URL(fileURLWithPath: "/usr/bin/unzip"),
            arguments: ["-Z1", output.path], timeout: 10
        ))
        try expect(entries.exitCode == 0, "exported archive must be readable")
        try expect(Set(entries.stdout.split(separator: "\n").map(String.init)) == ["theme.json", "background.png"], "archive entries mismatch")
        try expect(!entries.stdout.contains(root.path), "archive must not contain absolute paths")
    }
}
```

Add this exact real-file fixture to `TestSupport.swift`; it decodes a fixed 1×1 PNG and writes a deterministic manifest:

```swift
func writeExportTheme(in root: URL, id: String) throws -> ThemeRecord {
    let directory = root.appendingPathComponent(id, isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
    let manifest = ThemeManifest(
        schemaVersion: 1,
        id: id,
        name: "Safe Theme",
        image: "background.png",
        appearance: "dark"
    )
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    try encoder.encode(manifest).write(
        to: directory.appendingPathComponent("theme.json"),
        options: .atomic
    )
    let png = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAusB9Y9Z4ZkAAAAASUVORK5CYII=")!
    let imageURL = directory.appendingPathComponent("background.png")
    try png.write(to: imageURL, options: .atomic)
    return ThemeRecord(
        libraryID: id,
        manifest: manifest,
        directoryURL: directory,
        imageURL: imageURL,
        isActive: false
    )
}
```

The fixed PNG payload is:

```text
iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAusB9Y9Z4ZkAAAAASUVORK5CYII=
```

- [ ] **Step 2: Verify RED**

Run: `/bin/bash Scripts/test.sh`

Expected: compile failure because `ThemePackageExporter` does not exist.

- [ ] **Step 3: Implement the exporter with staged, atomic publication**

Create the protocol and implementation with these exact safety rules:

```swift
package protocol ThemePackageExporting: Sendable {
    func export(theme: ThemeRecord, to destination: URL) async throws -> URL
}

package struct ThemePackageExporter: ThemePackageExporting, Sendable {
    private let runner: any CommandRunning

    package init(runner: any CommandRunning = ProcessRunner()) {
        self.runner = runner
    }

    package func export(theme: ThemeRecord, to destination: URL) async throws -> URL {
        guard destination.pathExtension.lowercased() == "codexskin" else {
            throw ManagerError.invalidPackage("导出文件必须使用 .codexskin 扩展名。")
        }
        let values = try theme.imageURL.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
        guard values.isRegularFile == true, values.isSymbolicLink != true else {
            throw ManagerError.invalidPackage("主题图片不是安全的普通文件。")
        }

        let fileManager = FileManager.default
        let work = fileManager.temporaryDirectory
            .appendingPathComponent("CodexSkinManagerExport-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: work, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        defer { try? fileManager.removeItem(at: work) }

        let manifestURL = work.appendingPathComponent("theme.json")
        let imageURL = work.appendingPathComponent(theme.manifest.image)
        let archiveURL = work.appendingPathComponent("package.codexskin")
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(theme.manifest).write(to: manifestURL, options: .atomic)
        try fileManager.copyItem(at: theme.imageURL, to: imageURL)

        let zip = try await runner.run(CommandRequest(
            executable: URL(fileURLWithPath: "/usr/bin/zip"),
            arguments: ["-X", "-j", archiveURL.path, manifestURL.path, imageURL.path],
            timeout: 20
        ))
        guard zip.exitCode == 0 else { throw ManagerError.invalidPackage("无法创建主题包。") }

        let list = try await runner.run(CommandRequest(
            executable: URL(fileURLWithPath: "/usr/bin/unzip"),
            arguments: ["-Z1", archiveURL.path], timeout: 10
        ))
        let entries = list.stdout.split(separator: "\n").map(String.init)
        guard list.exitCode == 0, entries.count == 2,
              Set(entries) == Set(["theme.json", theme.manifest.image])
        else { throw ManagerError.invalidPackage("导出的主题包结构无效。") }

        let parent = destination.deletingLastPathComponent()
        let published = parent.appendingPathComponent(".\(destination.lastPathComponent).\(UUID().uuidString)")
        try fileManager.copyItem(at: archiveURL, to: published)
        if fileManager.fileExists(atPath: destination.path) {
            _ = try fileManager.replaceItemAt(destination, withItemAt: published)
        } else {
            try fileManager.moveItem(at: published, to: destination)
        }
        return destination
    }
}
```

Add `ManagerError.invalidPackage(String)` and map it through `errorDescription`. Before publication, also reject an existing destination that is a symlink and set final permissions to `0600`.

- [ ] **Step 4: Add non-mutating importer validation**

Extend argument parsing with `VALIDATE_ONLY=false` and `--validate-only`. After payload, ID, and metadata validation—but before duplicate lookup or any write under `themes/`—emit:

```bash
if [ "$VALIDATE_ONLY" = "true" ]; then
  if [ "$JSON_OUTPUT" = "true" ]; then
    emit_json true validated 'Theme package validated successfully.' "$THEME_ID" "$THEME_NAME"
  else
    /usr/bin/printf 'Validated: %s\n' "$THEME_NAME"
  fi
  exit 0
fi
```

Update usage text to include `[--validate-only]`. Add `EngineControlling.validateThemePackage(packageURL:)` and map it to:

```swift
let result = try await runScript(
    named: "import-theme-pack-macos.sh",
    arguments: ["--file", packageURL.path, "--validate-only", "--json"],
    timeout: 45
)
try requireSuccess(result)
```

- [ ] **Step 5: Integrate export into AppModel**

Inject `exporter: any ThemePackageExporting` into the initializer, default it in `live()`, and add:

```swift
@Published package private(set) var lastExportURL: URL?

package func exportSelectedTheme(to destination: URL) async {
    guard !operation.isBusy, let theme = selectedTheme else { return }
    operation = .exporting
    do {
        let output = try await exporter.export(theme: theme, to: destination)
        try await engine.validateThemePackage(packageURL: output)
        lastExportURL = output
        operation = .succeeded("已导出 \(theme.manifest.name)")
    } catch {
        operation = .failed(message(for: error))
    }
}
```

Add `.exporting` to `ManagerOperation.isBusy`. A failed validation must leave any prior `lastExportURL` unchanged and surface an actionable error.

- [ ] **Step 6: Run focused and full verification**

Run:

```bash
/bin/bash -n EngineExtension/import-theme-pack-macos.sh
/bin/bash Scripts/test.sh
```

Expected: syntax exits 0; exporter suite and all previous suites pass.

- [ ] **Step 7: Commit**

```bash
git add Sources/CodexSkinManagerCore/ThemePackageExporter.swift Sources/CodexSkinManagerCore/EngineBridge.swift Sources/CodexSkinManagerCore/AppModel.swift EngineExtension/import-theme-pack-macos.sh Tests/CodexSkinManagerTests/ThemePackageExporterTests.swift Tests/CodexSkinManagerTests/AppModelTests.swift Tests/CodexSkinManagerTests/EngineBridgeTests.swift Tests/CodexSkinManagerTests/TestMain.swift
git commit -m "Add safe compact theme export"
```

---

### Task 5: Split the main window into dashboard, library, detail, toolbar, and banner

**Files:**
- Create: `Sources/CodexSkinManagerCore/DashboardView.swift`
- Create: `Sources/CodexSkinManagerCore/ThemeLibraryView.swift`
- Create: `Sources/CodexSkinManagerCore/ThemeDetailView.swift`
- Create: `Sources/CodexSkinManagerCore/ThemeToolbar.swift`
- Create: `Sources/CodexSkinManagerCore/OperationBanner.swift`
- Modify: `Sources/CodexSkinManagerCore/ContentView.swift`
- Modify: `Sources/CodexSkinManagerCore/ThemeCardView.swift`
- Modify: `Tests/CodexSkinManagerTests/UICompileTests.swift`

**Interfaces:**
- `DashboardView(model:onOpenLibrary:onRestore:)` consumes lifecycle methods and active theme.
- `ThemeLibraryView(model:onImport:onExport:)` owns only layout and selection.
- `ThemeDetailView(theme:model:onExport:)` renders selected metadata and calls `model.apply`.
- `ThemeToolbar(model:onImport:onExport:)` binds model query state.
- `OperationBanner(model:onRetry:)` displays the last operation and never runs an arbitrary script.

- [ ] **Step 1: Write failing UI compile and source-structure assertions**

Instantiate every new view in `UICompileTests` and add source checks:

```swift
_ = DashboardView(model: model, onOpenLibrary: {}, onRestore: {})
_ = ThemeLibraryView(model: model, onImport: {}, onExport: {})
_ = ThemeDetailView(theme: theme, model: model, onExport: {})
_ = ThemeToolbar(model: model, onImport: {}, onExport: {})
_ = OperationBanner(model: model, onRetry: {})
```

Assert `ContentView.swift` contains the five type names and no longer declares `private var themeGrid` or a local `ManagerSection`.

- [ ] **Step 2: Verify RED**

Run: `/bin/bash Scripts/test.sh`

Expected: compile failure because the five views do not exist.

- [ ] **Step 3: Build the dashboard**

Implement a complete `DashboardView` with:

- active `ThemeRecord` from `model.themes.first(where: \.isActive)`;
- 16:9 `NSImage` preview or safe fallback;
- four text-and-icon status rows for Codex, injector, CDP, and theme;
- `启动/重新应用` calling `model.restartTheme()`;
- `暂停主题` calling `model.pauseTheme()`;
- `浏览主题库` callback;
- destructive `恢复原版` callback;
- disabled actions while `model.operation.isBusy`;
- accessibility labels that include the current state text.

Use `WeaponPlateShape` only for the hero and action panel; do not nest decorative cards.

- [ ] **Step 4: Build the toolbar and library container**

`ThemeToolbar` must bind `model.searchText`, `themeFilter`, and `themeSort`, use a `TextField` with `search` accessibility label, and disable export when `model.selectedTheme == nil`.

`ThemeLibraryView` must use `ViewThatFits(in: .horizontal)`:

```swift
ViewThatFits(in: .horizontal) {
    HSplitView {
        themeList.frame(minWidth: 280, idealWidth: 340, maxWidth: 390)
        detail.frame(minWidth: 520)
    }
    narrowGallery
}
```

The list uses `selection: $model.selectedThemeID`; gallery cards call `model.selectTheme(theme)` and never call `model.apply`.

- [ ] **Step 5: Build the detail and operation banner**

`ThemeDetailView` must show preview, name, manifest ID, library ID when different, appearance, active badge, and these actions:

- active theme: disabled `当前主题` plus enabled `重新应用`;
- inactive theme: primary `装备主题`;
- all valid themes: secondary `导出主题`.

`OperationBanner` maps every `ManagerOperation` case to an icon, status text, semantic color, progress indicator when busy, and `重试` only when `model.retryAvailable` is true. The copy-error button writes only the model's already-sanitized message to `NSPasteboard.general`.

- [ ] **Step 6: Replace ContentView composition**

`ContentView` becomes a `NavigationSplitView` whose detail switches on `model.selectedSection`:

```swift
switch model.selectedSection {
case .dashboard:
    DashboardView(
        model: model,
        onOpenLibrary: { model.selectedSection = .library },
        onRestore: { confirmingRestore = true }
    )
case .library, .recent:
    ThemeLibraryView(
        model: model,
        onImport: { showingImporter = true },
        onExport: presentExportPanel
    )
}
```

Keep import duplicate and restore confirmation dialogs. Add a restart-consent alert bound to `pendingRestartThemeID`; confirm calls `confirmPendingRestartApply`, cancel calls `cancelPendingRestartApply`.

- [ ] **Step 7: Verify GREEN and commit**

Run: `/bin/bash Scripts/test.sh`

Expected: all suites pass and all new views compile.

```bash
git add Sources/CodexSkinManagerCore/ContentView.swift Sources/CodexSkinManagerCore/DashboardView.swift Sources/CodexSkinManagerCore/ThemeLibraryView.swift Sources/CodexSkinManagerCore/ThemeDetailView.swift Sources/CodexSkinManagerCore/ThemeToolbar.swift Sources/CodexSkinManagerCore/OperationBanner.swift Sources/CodexSkinManagerCore/ThemeCardView.swift Tests/CodexSkinManagerTests/UICompileTests.swift
git commit -m "Build dashboard and theme detail workspace"
```

---

### Task 6: Add drag import, save-panel export, retry intent, and empty states

**Files:**
- Modify: `Sources/CodexSkinManagerCore/ContentView.swift`
- Modify: `Sources/CodexSkinManagerCore/AppModel.swift`
- Modify: `Sources/CodexSkinManagerCore/ThemeLibraryView.swift`
- Modify: `Sources/CodexSkinManagerCore/OperationBanner.swift`
- Modify: `Tests/CodexSkinManagerTests/AppModelTests.swift`
- Modify: `Tests/CodexSkinManagerTests/UICompileTests.swift`

**Interfaces:**
- Produces `AppModel.retryLastAction()` and `retryAvailable` from a private typed `RetryIntent`.
- Produces `ContentView.importURLs(_:) -> Bool` for both file importer and `.dropDestination(for: URL.self)`.
- Produces `ContentView.presentExportPanel()` using `NSSavePanel` and `model.exportSelectedTheme(to:)`.

- [ ] **Step 1: Write failing retry and structure tests**

Add model tests that:

- failed apply stores `.apply(themeID)` and retry switches the same ID;
- failed pause stores `.pause`;
- success clears the retry intent;
- restore failure stores `.restore`;
- import validation failure does not retry a stale security-scoped URL automatically.

Add UI source assertions for `.dropDestination(for: URL.self)`, `NSSavePanel`, and `allowedFileTypes = ["codexskin"]`.

- [ ] **Step 2: Verify RED**

Run: `/bin/bash Scripts/test.sh`

Expected: failure for missing retry and drag/export source.

- [ ] **Step 3: Implement typed retry intent**

Use a private enum, never a closure capturing stale file access:

```swift
private enum RetryIntent: Equatable, Sendable {
    case apply(String)
    case pause
    case restart
    case restore
    case export(String, URL)
}

package var retryAvailable: Bool { retryIntent != nil && !operation.isBusy }

package func retryLastAction() async {
    guard !operation.isBusy, let intent = retryIntent else { return }
    switch intent {
    case .apply(let id):
        guard let theme = themes.first(where: { $0.libraryID == id }) else { return }
        await performApply(theme)
    case .pause: await pauseTheme()
    case .restart: await restartTheme()
    case .restore: await restoreOriginal()
    case .export(let id, let destination):
        guard selectedThemeID == id else { return }
        await exportSelectedTheme(to: destination)
    }
}
```

Set the intent immediately before each operation; clear it only on verified success. Import is deliberately excluded because file security scope may have ended.

- [ ] **Step 4: Implement shared URL import and drag target**

Create one handler that accepts exactly one regular `.codexskin` URL, opens security scope inside the asynchronous operation, and returns `false` for unsupported drops. Both `.fileImporter` and `.dropDestination` must call this handler.

Add an `isImportTargeted` state to `ThemeLibraryView`; while targeted, draw a dashed ice-blue `WeaponPlateShape` overlay with the text `释放以导入主题包`. Do not let the overlay intercept buttons outside an active drag.

- [ ] **Step 5: Implement safe save-panel export**

Use `NSSavePanel` on the main actor:

```swift
private func presentExportPanel() {
    guard let theme = model.selectedTheme else { return }
    let panel = NSSavePanel()
    panel.allowedFileTypes = ["codexskin"]
    panel.canCreateDirectories = true
    panel.isExtensionHidden = false
    panel.nameFieldStringValue = "\(safeExportName(theme.manifest.name)).codexskin"
    guard panel.runModal() == .OK, let url = panel.url else { return }
    Task { await model.exportSelectedTheme(to: url) }
}
```

`safeExportName` keeps Unicode letters/numbers, `-`, and `_`, converts other runs to `-`, trims separators, and falls back to `theme.manifest.id`.

- [ ] **Step 6: Add distinct empty states**

Library empty: show `没有找到已安装主题` and `导入主题`. Filter empty: show `当前筛选没有匹配主题` and `清除筛选`. Detail empty: show `选择一个主题查看详情`. Recent empty: show `应用主题后会出现在这里`.

- [ ] **Step 7: Run tests and commit**

Run: `/bin/bash Scripts/test.sh`

Expected: all suites pass.

```bash
git add Sources/CodexSkinManagerCore/ContentView.swift Sources/CodexSkinManagerCore/AppModel.swift Sources/CodexSkinManagerCore/ThemeLibraryView.swift Sources/CodexSkinManagerCore/OperationBanner.swift Tests/CodexSkinManagerTests/AppModelTests.swift Tests/CodexSkinManagerTests/UICompileTests.swift
git commit -m "Add drag import and export workflow"
```

---

### Task 7: Add keyboard commands, shared menu-bar state, accessibility, and visual restraint

**Files:**
- Modify: `Sources/CodexSkinManager/CodexSkinManager.swift`
- Modify: `Sources/CodexSkinManagerCore/MenuBarContentView.swift`
- Modify: `Sources/CodexSkinManagerCore/VisualStyle.swift`
- Modify: `Sources/CodexSkinManagerCore/DashboardView.swift`
- Modify: `Sources/CodexSkinManagerCore/ThemeLibraryView.swift`
- Modify: `Sources/CodexSkinManagerCore/ThemeDetailView.swift`
- Modify: `Sources/CodexSkinManagerCore/ThemeToolbar.swift`
- Modify: `Sources/CodexSkinManagerCore/OperationBanner.swift`
- Modify: `Tests/CodexSkinManagerTests/UICompileTests.swift`

**Interfaces:**
- Produces app-level commands for import, export, apply, restore, refresh, and search focus.
- Produces `AppModel.commandRequest` or typed command nonce consumed by `ContentView`; commands must not open duplicate panels.
- Keeps menu-bar rows limited to `model.menuBarRecentThemes` and status derived from the same `EngineStatus`.

- [ ] **Step 1: Write failing shortcut and accessibility structure assertions**

Assert the app source contains exact shortcuts:

```swift
.keyboardShortcut("o", modifiers: .command)
.keyboardShortcut("e", modifiers: [.command, .shift])
.keyboardShortcut(.return, modifiers: .command)
.keyboardShortcut("r", modifiers: [.command, .shift])
.keyboardShortcut("f", modifiers: .command)
```

Assert new view sources contain `.accessibilityLabel`, `accessibilityReduceMotion`, and non-color status text.

- [ ] **Step 2: Verify RED**

Run: `/bin/bash Scripts/test.sh`

Expected: UI structure test failure.

- [ ] **Step 3: Implement app commands through typed model requests**

Define:

```swift
package enum ManagerCommand: Equatable, Sendable {
    case importTheme
    case exportTheme
    case applySelected
    case restoreOriginal
    case focusSearch
}

@Published package private(set) var commandRequest: (command: ManagerCommand, nonce: UUID)?
package func request(_ command: ManagerCommand) {
    commandRequest = (command, UUID())
}
```

App commands only call `model.request`. `ContentView.onChange(of: commandRequest?.nonce)` performs the UI action once. Apply calls the existing consent-aware `model.apply`; restore sets the existing confirmation flag.

- [ ] **Step 4: Align the menu bar**

Use `menuBarRecentThemes`, show separate text for active, paused, waiting, and stopped sessions, and add pause/restart buttons only when relevant. Keep import and restore confirmations; never infer active state from the selected theme.

- [ ] **Step 5: Tune the cold-armor visual system**

Update semantic tokens:

```swift
package static let selection = Color(red: 0.27, green: 0.78, blue: 1.0)
package static let success = Color(red: 0.28, green: 0.92, blue: 0.73)
package static let warning = Color(red: 1.0, green: 0.66, blue: 0.24)
package static let panelStrong = Color(red: 0.04, green: 0.075, blue: 0.12).opacity(0.96)
package static let panelQuiet = Color(red: 0.045, green: 0.085, blue: 0.14).opacity(0.74)
```

Reduce manga rays from 26 to 18, strong-ray opacity from `0.12` to `0.07`, and minor-ray opacity from `0.035` to `0.02`. Only selected/active rows receive ice glow; ordinary rows use a one-pixel quiet border.

- [ ] **Step 6: Respect Reduce Motion and accessibility**

Each animated view reads `@Environment(\.accessibilityReduceMotion)` and uses no animation when true. All icon-only controls need labels; active/selected states use text plus symbols; preview images use theme names as labels; keyboard focus rings remain visible.

- [ ] **Step 7: Run tests and commit**

Run: `/bin/bash Scripts/test.sh`

Expected: all suites pass.

```bash
git add Sources/CodexSkinManager/CodexSkinManager.swift Sources/CodexSkinManagerCore/MenuBarContentView.swift Sources/CodexSkinManagerCore/VisualStyle.swift Sources/CodexSkinManagerCore/DashboardView.swift Sources/CodexSkinManagerCore/ThemeLibraryView.swift Sources/CodexSkinManagerCore/ThemeDetailView.swift Sources/CodexSkinManagerCore/ThemeToolbar.swift Sources/CodexSkinManagerCore/OperationBanner.swift Tests/CodexSkinManagerTests/UICompileTests.swift
git commit -m "Polish theme manager navigation and accessibility"
```

---

### Task 8: Build, install, visually verify, document, and release the upgrade

**Files:**
- Modify: `Resources/Info.plist`
- Modify: `README.md`
- Test: all files under `Tests/CodexSkinManagerTests/`
- Verify: installed `/Users/zhangyifan/Applications/Codex Skin Manager.app`

**Interfaces:**
- Final app version: `1.1.0`.
- Final build number: `3`.
- Produces a clean `main` candidate with no uncommitted files and no privacy-bearing artifacts.

- [ ] **Step 1: Run the complete automated suite**

Run:

```bash
/bin/bash Scripts/test.sh
git diff --check
```

Expected: every suite passes; `git diff --check` emits no output.

- [ ] **Step 2: Perform an isolated export/import round trip**

Create a temporary theme library and destination under a `mktemp -d` directory. Run `ThemePackageExporterTests` through the normal suite, then invoke the installed importer with `--validate-only --json` against the exported fixture. Confirm JSON contains `"pass":true` and `"code":"validated"`. Do not import the fixture into the user's real theme library.

- [ ] **Step 3: Update version and README**

Set:

```xml
<key>CFBundleShortVersionString</key>
<string>1.1.0</string>
<key>CFBundleVersion</key>
<string>3</string>
```

README must document status dashboard, searchable list-detail library, drag import, safe export, restart consent, shortcuts, and the explicit absence of an online marketplace/multi-asset package format in 1.1.0.

- [ ] **Step 4: Build and install the app**

Run: `/bin/bash Scripts/install-app.sh`

Expected: tests pass during build, codesign verification passes, both engine extension scripts install atomically, and the app installs at `/Users/zhangyifan/Applications/Codex Skin Manager.app`.

- [ ] **Step 5: Verify bundle metadata and signature**

Run:

```bash
plutil -p '/Users/zhangyifan/Applications/Codex Skin Manager.app/Contents/Info.plist'
codesign --verify --deep --strict --verbose=2 '/Users/zhangyifan/Applications/Codex Skin Manager.app'
```

Expected: version `1.1.0`, build `3`, icon `AppIcon`; codesign reports valid and satisfies its designated requirement.

- [ ] **Step 6: Perform visual QA in the real app**

Open the installed app and capture/inspect these states at `1024×700` and `1440×900`:

1. dashboard with an active theme;
2. library list-detail with an inactive selected theme;
3. recent-empty and filtered-empty states;
4. drag-target overlay;
5. restart-consent dialog;
6. successful operation banner;
7. failed operation banner with retry/copy controls;
8. narrow gallery with no empty detail column.

Verify no overlap, clipping, invisible controls, excessive glow, or misleading active badges. Repeat with Reduce Motion enabled and keyboard-only navigation from sidebar through search, theme selection, apply, and restore confirmation.

- [ ] **Step 7: Privacy and repository audit**

Run:

```bash
git status --short
git diff --name-only origin/main...HEAD
git diff --stat origin/main...HEAD
rg -n '/Users/|API[_ -]?Key|Bearer |password|token' --glob '!docs/superpowers/**' .
```

Expected: only intended source/docs/resources are present; no exported user themes, screenshots containing private tasks, logs, credentials, absolute user paths, or generated temp files are staged. Legitimate test-only `/tmp` paths may remain; review each match.

- [ ] **Step 8: Final test and commit**

Run: `/bin/bash Scripts/test.sh`

Expected: all suites pass after version/docs changes.

```bash
git add Resources/Info.plist README.md
git commit -m "Release theme library experience upgrade"
```

- [ ] **Step 9: Finish the branch**

Use `superpowers:verification-before-completion`, then `superpowers:finishing-a-development-branch`. Merge only after fresh tests pass. Push the chosen branch, verify the remote hash equals local, and emit the relevant Codex Git directives only after each Git action succeeds.

---

## Implementation Order and Review Gates

1. Task 1 establishes pure query and selection semantics.
2. Task 2 makes apply consent-aware and runtime-verified before any new UI depends on it.
3. Task 3 adds lifecycle controls through the existing guarded engine boundary.
4. Task 4 adds the independently testable safe exporter and non-mutating validation.
5. Task 5 builds the new UI from already-tested model APIs.
6. Task 6 completes file workflows and retry semantics.
7. Task 7 adds shortcuts, shared menu behavior, accessibility, and final visual tuning.
8. Task 8 performs the real app, signature, visual, privacy, and release checks.

Each task must be reviewed against its `Interfaces` block before the next task begins. Do not combine Tasks 2–4 into one commit: restart consent, lifecycle scripts, and archive export have separate risk and rollback boundaries.
