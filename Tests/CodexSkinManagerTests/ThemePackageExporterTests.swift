import CodexSkinManagerCore
import Foundation

actor DestinationSwappingRunner: CommandRunning {
    private let destination: URL
    private let target: URL
    private var requestCount = 0

    init(destination: URL, target: URL) {
        self.destination = destination
        self.target = target
    }

    func run(_ request: CommandRequest) async throws -> CommandResult {
        let result = try await ProcessRunner().run(request)
        requestCount += 1
        if requestCount == 1 {
            try FileManager.default.createSymbolicLink(at: destination, withDestinationURL: target)
        }
        return result
    }
}

enum ThemePackageExporterTests {
    static func run() async throws {
        try await exportsExactlyManifestAndImage()
        try await replacesDestinationWithoutStaleEntries()
        try await rejectsSymlinkDestinationWithoutChangingTarget()
        try await rejectsBrokenSymlinkDestination()
        try await rechecksDestinationSymlinkBeforePublication()
        try await rejectsSymlinkSourceImage()
        try await rejectsUnsafeManifestImagePath()
        print("PASS: ThemePackageExporterTests")
    }

    private static func exportsExactlyManifestAndImage() async throws {
        let root = try makeTemporaryDirectory(prefix: "exporter")
        defer { try? FileManager.default.removeItem(at: root) }
        let theme = try writeExportTheme(in: root, id: "safe-theme")
        let destination = root.appendingPathComponent("safe-theme.codexskin")

        let output = try await ThemePackageExporter().export(theme: theme, to: destination)
        let entries = try await archiveEntries(at: output)
        let attributes = try FileManager.default.attributesOfItem(atPath: output.path)
        let permissions = attributes[FileAttributeKey.posixPermissions] as? NSNumber

        try expect(entries.exitCode == 0, "exported archive must be readable")
        try expect(
            Set(entries.stdout.split(separator: "\n").map(String.init)) == ["theme.json", "background.png"],
            "archive entries mismatch"
        )
        try expect(!entries.stdout.contains(root.path), "archive must not contain absolute paths")
        try expect(permissions?.intValue == 0o600, "published archive permissions must be 0600")
    }

    private static func replacesDestinationWithoutStaleEntries() async throws {
        let root = try makeTemporaryDirectory(prefix: "exporter-replace")
        defer { try? FileManager.default.removeItem(at: root) }
        let theme = try writeExportTheme(in: root, id: "replacement")
        let destination = root.appendingPathComponent("replacement.codexskin")
        let stale = root.appendingPathComponent("stale.txt")
        try Data("stale".utf8).write(to: stale)
        let seeded = try await ProcessRunner().run(CommandRequest(
            executable: URL(fileURLWithPath: "/usr/bin/zip"),
            arguments: ["-j", destination.path, stale.path],
            timeout: 10
        ))
        try expect(seeded.exitCode == 0, "stale destination fixture must be created")

        _ = try await ThemePackageExporter().export(theme: theme, to: destination)
        let entries = try await archiveEntries(at: destination)

        try expect(entries.exitCode == 0, "replacement archive must be readable")
        try expect(
            Set(entries.stdout.split(separator: "\n").map(String.init)) == ["theme.json", "background.png"],
            "replacement must not preserve stale archive entries"
        )
    }

    private static func rejectsSymlinkDestinationWithoutChangingTarget() async throws {
        let root = try makeTemporaryDirectory(prefix: "exporter-destination-link")
        defer { try? FileManager.default.removeItem(at: root) }
        let theme = try writeExportTheme(in: root, id: "linked-destination")
        let target = root.appendingPathComponent("protected.codexskin")
        let destination = root.appendingPathComponent("linked.codexskin")
        let sentinel = Data("protected".utf8)
        try sentinel.write(to: target)
        try FileManager.default.createSymbolicLink(at: destination, withDestinationURL: target)

        do {
            _ = try await ThemePackageExporter().export(theme: theme, to: destination)
            throw TestFailure(description: "symlink destination must be rejected")
        } catch ManagerError.invalidPackage(let message) {
            try expect(message.contains("符号链接"), "symlink rejection must be actionable")
        }

        let targetContents = try Data(contentsOf: target)
        try expect(targetContents == sentinel, "symlink target must remain unchanged")
    }

    private static func rejectsSymlinkSourceImage() async throws {
        let root = try makeTemporaryDirectory(prefix: "exporter-source-link")
        defer { try? FileManager.default.removeItem(at: root) }
        let regularTheme = try writeExportTheme(in: root, id: "linked-source")
        let link = regularTheme.directoryURL.appendingPathComponent("linked.png")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: regularTheme.imageURL)
        let theme = ThemeRecord(
            libraryID: regularTheme.libraryID,
            manifest: regularTheme.manifest,
            directoryURL: regularTheme.directoryURL,
            imageURL: link,
            isActive: false
        )

        do {
            _ = try await ThemePackageExporter().export(
                theme: theme,
                to: root.appendingPathComponent("linked-source.codexskin")
            )
            throw TestFailure(description: "symlink source image must be rejected")
        } catch ManagerError.invalidPackage(let message) {
            try expect(message.contains("普通文件"), "source image rejection must be actionable")
        }
    }

    private static func rechecksDestinationSymlinkBeforePublication() async throws {
        let root = try makeTemporaryDirectory(prefix: "exporter-raced-destination-link")
        defer { try? FileManager.default.removeItem(at: root) }
        let theme = try writeExportTheme(in: root, id: "raced-linked-destination")
        let target = root.appendingPathComponent("raced-protected.codexskin")
        let destination = root.appendingPathComponent("raced-link.codexskin")
        let sentinel = Data("raced-protected".utf8)
        try sentinel.write(to: target)
        let runner = DestinationSwappingRunner(destination: destination, target: target)

        do {
            _ = try await ThemePackageExporter(runner: runner).export(theme: theme, to: destination)
            throw TestFailure(description: "destination changed to symlink before publication must be rejected")
        } catch ManagerError.invalidPackage(let message) {
            try expect(message.contains("符号链接"), "publication-time symlink rejection must be actionable")
        }

        let targetContents = try Data(contentsOf: target)
        try expect(targetContents == sentinel, "publication race must not change the symlink target")
    }

    private static func rejectsBrokenSymlinkDestination() async throws {
        let root = try makeTemporaryDirectory(prefix: "exporter-broken-destination-link")
        defer { try? FileManager.default.removeItem(at: root) }
        let theme = try writeExportTheme(in: root, id: "broken-linked-destination")
        let missingTarget = root.appendingPathComponent("missing.codexskin")
        let destination = root.appendingPathComponent("broken-link.codexskin")
        try FileManager.default.createSymbolicLink(at: destination, withDestinationURL: missingTarget)

        do {
            _ = try await ThemePackageExporter().export(theme: theme, to: destination)
            throw TestFailure(description: "broken symlink destination must be rejected")
        } catch ManagerError.invalidPackage(let message) {
            try expect(message.contains("符号链接"), "broken symlink rejection must be actionable")
        }

        let linkTarget = try FileManager.default.destinationOfSymbolicLink(atPath: destination.path)
        try expect(linkTarget == missingTarget.path, "broken symlink must remain unchanged")
    }

    private static func rejectsUnsafeManifestImagePath() async throws {
        let root = try makeTemporaryDirectory(prefix: "exporter-unsafe-name")
        defer { try? FileManager.default.removeItem(at: root) }
        let regularTheme = try writeExportTheme(in: root, id: "unsafe-name")
        let manifest = ThemeManifest(
            schemaVersion: regularTheme.manifest.schemaVersion,
            id: regularTheme.manifest.id,
            name: regularTheme.manifest.name,
            image: "../escaped.png",
            appearance: regularTheme.manifest.appearance
        )
        let theme = ThemeRecord(
            libraryID: regularTheme.libraryID,
            manifest: manifest,
            directoryURL: regularTheme.directoryURL,
            imageURL: regularTheme.imageURL,
            isActive: false
        )

        do {
            _ = try await ThemePackageExporter().export(
                theme: theme,
                to: root.appendingPathComponent("unsafe-name.codexskin")
            )
            throw TestFailure(description: "unsafe manifest image path must be rejected")
        } catch ManagerError.invalidPackage(let message) {
            try expect(message.contains("文件名"), "unsafe image name rejection must be actionable")
        }

        try expect(
            !FileManager.default.fileExists(atPath: root.deletingLastPathComponent().appendingPathComponent("escaped.png").path),
            "unsafe image path must not escape the staging directory"
        )
    }

    private static func archiveEntries(at archive: URL) async throws -> CommandResult {
        try await ProcessRunner().run(CommandRequest(
            executable: URL(fileURLWithPath: "/usr/bin/unzip"),
            arguments: ["-Z1", archive.path],
            timeout: 10
        ))
    }
}
