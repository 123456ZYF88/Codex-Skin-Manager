import CodexSkinManagerCore
import Foundation

enum ThemeCatalogTests {
    static func run() throws {
        try loadsInstalledThemeAndMatchesActiveManifestID()
        try skipsMalformedManifest()
        try skipsUnsafeImages()
        try skipsSymlinkedThemeDirectory()
        try keepsDuplicateVisibleNames()
        try fallsBackToActiveName()
        print("PASS: ThemeCatalogTests")
    }

    private static func loadsInstalledThemeAndMatchesActiveManifestID() throws {
        let stateRoot = try makeTemporaryDirectory(prefix: "CodexSkinManagerCatalogTests")
        defer { try? FileManager.default.removeItem(at: stateRoot) }
        let installed = ThemeManifest(
            schemaVersion: 1,
            id: "theme-identity",
            name: "Library Theme",
            image: "background.png",
            appearance: "dark"
        )
        try writeTheme(installed, to: stateRoot.appendingPathComponent("themes/library-one"))
        try writeActiveTheme(installed, stateRoot: stateRoot)

        let themes = try ThemeCatalog(stateRoot: stateRoot).loadThemes()

        try expect(themes.count == 1, "expected one installed theme")
        try expect(themes[0].libraryID == "library-one", "library id must come from its directory")
        try expect(themes[0].isActive, "matching manifest id must be active")
    }

    private static func skipsMalformedManifest() throws {
        let stateRoot = try makeTemporaryDirectory(prefix: "CodexSkinManagerCatalogTests")
        defer { try? FileManager.default.removeItem(at: stateRoot) }
        let directory = stateRoot.appendingPathComponent("themes/broken", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data("{not-json}".utf8).write(to: directory.appendingPathComponent("theme.json"))
        try Data([1]).write(to: directory.appendingPathComponent("background.png"))

        let themes = try ThemeCatalog(stateRoot: stateRoot).loadThemes()
        try expect(themes.isEmpty, "malformed JSON must be skipped")
    }

    private static func skipsUnsafeImages() throws {
        let stateRoot = try makeTemporaryDirectory(prefix: "CodexSkinManagerCatalogTests")
        defer { try? FileManager.default.removeItem(at: stateRoot) }
        let missing = ThemeManifest(
            schemaVersion: 1,
            id: "missing",
            name: "Missing",
            image: "background.png",
            appearance: nil
        )
        let missingDirectory = stateRoot.appendingPathComponent("themes/missing", isDirectory: true)
        try FileManager.default.createDirectory(at: missingDirectory, withIntermediateDirectories: true)
        try JSONEncoder().encode(missing).write(to: missingDirectory.appendingPathComponent("theme.json"))
        let traversal = ThemeManifest(
            schemaVersion: 1,
            id: "traversal",
            name: "Traversal",
            image: "../outside.png",
            appearance: nil
        )
        let traversalDirectory = stateRoot.appendingPathComponent("themes/traversal", isDirectory: true)
        try FileManager.default.createDirectory(at: traversalDirectory, withIntermediateDirectories: true)
        try JSONEncoder().encode(traversal).write(to: traversalDirectory.appendingPathComponent("theme.json"))
        try Data([1]).write(to: stateRoot.appendingPathComponent("themes/outside.png"))

        let themes = try ThemeCatalog(stateRoot: stateRoot).loadThemes()
        try expect(themes.isEmpty, "unsafe images must be skipped")
    }

    private static func skipsSymlinkedThemeDirectory() throws {
        let stateRoot = try makeTemporaryDirectory(prefix: "CodexSkinManagerCatalogTests")
        defer { try? FileManager.default.removeItem(at: stateRoot) }
        let target = stateRoot.appendingPathComponent("outside-theme", isDirectory: true)
        let manifest = ThemeManifest(
            schemaVersion: 1,
            id: "linked",
            name: "Linked",
            image: "background.png",
            appearance: nil
        )
        try writeTheme(manifest, to: target)
        let themesDirectory = stateRoot.appendingPathComponent("themes", isDirectory: true)
        try FileManager.default.createDirectory(at: themesDirectory, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(
            at: themesDirectory.appendingPathComponent("linked"),
            withDestinationURL: target
        )

        let themes = try ThemeCatalog(stateRoot: stateRoot).loadThemes()
        try expect(themes.isEmpty, "symlinked theme must be skipped")
    }

    private static func keepsDuplicateVisibleNames() throws {
        let stateRoot = try makeTemporaryDirectory(prefix: "CodexSkinManagerCatalogTests")
        defer { try? FileManager.default.removeItem(at: stateRoot) }
        let first = ThemeManifest(
            schemaVersion: 1,
            id: "first-id",
            name: "Same Name",
            image: "background.png",
            appearance: nil
        )
        let second = ThemeManifest(
            schemaVersion: 1,
            id: "second-id",
            name: "Same Name",
            image: "background.png",
            appearance: nil
        )
        try writeTheme(first, to: stateRoot.appendingPathComponent("themes/library-a"))
        try writeTheme(second, to: stateRoot.appendingPathComponent("themes/library-b"))

        let themes = try ThemeCatalog(stateRoot: stateRoot).loadThemes()

        try expect(themes.map(\.libraryID) == ["library-a", "library-b"], "duplicate names must keep stable ids")
    }

    private static func fallsBackToActiveName() throws {
        let stateRoot = try makeTemporaryDirectory(prefix: "CodexSkinManagerCatalogTests")
        defer { try? FileManager.default.removeItem(at: stateRoot) }
        let inactive = ThemeManifest(
            schemaVersion: 1,
            id: "alpha",
            name: "Alpha",
            image: "background.png",
            appearance: nil
        )
        let installed = ThemeManifest(
            schemaVersion: 1,
            id: "installed-id",
            name: "Current Theme",
            image: "background.png",
            appearance: "dark"
        )
        let activeCopy = ThemeManifest(
            schemaVersion: 1,
            id: "generated-active-id",
            name: "Current Theme",
            image: "background.png",
            appearance: "dark"
        )
        try writeTheme(inactive, to: stateRoot.appendingPathComponent("themes/alpha"))
        try writeTheme(installed, to: stateRoot.appendingPathComponent("themes/library-current"))
        try writeActiveTheme(activeCopy, stateRoot: stateRoot)

        let themes = try ThemeCatalog(stateRoot: stateRoot).loadThemes()

        try expect(themes.first?.libraryID == "library-current", "active fallback must sort first")
        try expect(themes.first?.isActive == true, "name fallback must mark active")
        try expect(themes.filter(\.isActive).count == 1, "exactly one theme may be active")
    }

    private static func writeTheme(_ manifest: ThemeManifest, to directory: URL) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try JSONEncoder().encode(manifest).write(to: directory.appendingPathComponent("theme.json"))
        try Data([0x89, 0x50, 0x4E, 0x47]).write(to: directory.appendingPathComponent(manifest.image))
    }

    private static func writeActiveTheme(_ manifest: ThemeManifest, stateRoot: URL) throws {
        let directory = stateRoot.appendingPathComponent("theme", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try JSONEncoder().encode(manifest).write(to: directory.appendingPathComponent("theme.json"))
    }
}
