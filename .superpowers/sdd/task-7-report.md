# Task 7 Report: Commands, Menu Bar, Accessibility, and Visual Restraint

## Status

Implemented and verified. No version, packaging, or installation changes were made.

## RED / GREEN evidence

1. Command, menu-bar, accessibility, and visual structure tests were added first. `/bin/bash Scripts/test.sh` compiled successfully and failed with `App commands must declare shortcut .keyboardShortcut("o", modifiers: .command)`.
2. After the first implementation, all six suites passed. The only warning was the existing deprecated `NSSavePanel.allowedFileTypes` API.
3. A focused RED required `allowedContentTypes = [.codexSkinPackage]`; the suite failed with `save panel must use the non-deprecated content-type API for .codexskin`. The migration then passed without warnings.
4. A real AppModel behavior test was added after restoring the baseline recent projection. RED failed with `menu bar must show three recent themes without duplicating the active theme`; GREEN filters the active theme and returns at most three recent themes.
5. A final RED asserted model-level command claiming across multiple windows and failed with `AppModel must arbitrate command consumption across multiple windows`. GREEN added a shared nonce claim so only one ContentView can open a native panel for a request.

## Commands and shared menu-bar state

- Added typed `ManagerCommand` cases for import, export, apply, restore, refresh, and search focus.
- App commands only publish `AppModel.request`; `ContentView` observes the UUID nonce, claims it once through the shared model, and invokes the existing consent-aware actions or confirmation state.
- Search requests switch to the library and focus the real search field through the same retained typed request.
- Added the requested shortcuts: Command-O, Command-Shift-E, Command-Return, Command-Shift-R, Command-R, and Command-F.
- Menu-bar content derives the active theme from `ThemeRecord.isActive`, never selection, and separately displays up to three non-active recent themes from `menuBarRecentThemes`.
- Engine status has explicit text and symbols for active, paused, waiting, and stopped. Pause appears only for a verified active session; restart appears for paused, waiting, or stopped sessions. Buttons reuse `AppModel` lifecycle methods.
- Existing menu-bar import replacement and restore confirmation flows remain intact.

## Accessibility and visual changes

- Menu and operation progress views read `accessibilityReduceMotion`; Reduce Motion replaces indeterminate animation with a labelled static hourglass.
- Preview images and fallbacks include theme-name labels. Existing icon-only refresh/copy controls remain labelled.
- Theme cards expose selected/active text plus symbols and draw an explicit two-point focus ring.
- Added semantic selection, success, warning, strong-panel, and quiet-panel tokens with the specified values.
- Reduced manga rays from 26 to 18, strong opacity from 0.12 to 0.07, and minor opacity from 0.035 to 0.02.
- Selected or active cards receive ice emphasis; ordinary cards use a one-pixel quiet border with no glow. Existing weapon-plate shapes and assets are retained.

## Verification

- `/bin/bash Scripts/test.sh`: PASS, six suites, no warnings.
- `swift build`: PASS, no warnings.
- `git diff --check`: PASS.

## Files changed

- `Sources/CodexSkinManager/CodexSkinManager.swift`
- `Sources/CodexSkinManagerCore/AppModel.swift`
- `Sources/CodexSkinManagerCore/ContentView.swift`
- `Sources/CodexSkinManagerCore/DashboardView.swift`
- `Sources/CodexSkinManagerCore/MenuBarContentView.swift`
- `Sources/CodexSkinManagerCore/OperationBanner.swift`
- `Sources/CodexSkinManagerCore/ThemeCardView.swift`
- `Sources/CodexSkinManagerCore/ThemeDetailView.swift`
- `Sources/CodexSkinManagerCore/ThemeLibraryView.swift`
- `Sources/CodexSkinManagerCore/ThemeToolbar.swift`
- `Sources/CodexSkinManagerCore/VisualStyle.swift`
- `Tests/CodexSkinManagerTests/AppModelTests.swift`
- `Tests/CodexSkinManagerTests/UICompileTests.swift`
- `.superpowers/sdd/task-7-report.md`

## Concerns

- SwiftUI view structure is compile- and source-verified, but this task did not include an interactive VoiceOver or keyboard-navigation UI session.
- No new visual assets were added, so the visual change is intentionally limited to semantic colors, borders, shadows, and ray restraint.
