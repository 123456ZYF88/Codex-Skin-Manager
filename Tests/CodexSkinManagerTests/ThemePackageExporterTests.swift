import Darwin
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

actor ArchiveInflatingRunner: CommandRunning {
    private var requestCount = 0

    func run(_ request: CommandRequest) async throws -> CommandResult {
        let result = try await ProcessRunner().run(request)
        requestCount += 1
        if requestCount == 2 {
            let archive = URL(fileURLWithPath: request.arguments[1])
            let handle = try FileHandle(forWritingTo: archive)
            try handle.truncate(atOffset: 20 * 1_024 * 1_024 + 1)
            try handle.close()
        }
        return result
    }
}

actor ArchiveSameSizeMutatingRunner: CommandRunning {
    private var requestCount = 0

    func run(_ request: CommandRequest) async throws -> CommandResult {
        let result = try await ProcessRunner().run(request)
        requestCount += 1
        if requestCount == 2 {
            let archive = URL(fileURLWithPath: request.arguments[1])
            let descriptor = Darwin.open(archive.path, O_WRONLY | O_CLOEXEC)
            guard descriptor >= 0 else {
                throw TestFailure(description: "same-size archive mutation fixture could not open archive")
            }
            defer { Darwin.close(descriptor) }
            var replacement: UInt8 = 0
            guard Darwin.pwrite(descriptor, &replacement, 1, 0) == 1,
                  Darwin.fsync(descriptor) == 0
            else {
                throw TestFailure(description: "same-size archive mutation fixture could not overwrite archive")
            }
        }
        return result
    }
}

struct SourceSwappingFileOperations: ExportFileOperating {
    let replacement: URL
    private let base = POSIXExportFileOperations()

    func snapshotSource(at source: URL, to destination: URL, maximumBytes: Int64) throws {
        try FileManager.default.removeItem(at: source)
        try FileManager.default.createSymbolicLink(at: source, withDestinationURL: replacement)
        try base.snapshotSource(at: source, to: destination, maximumBytes: maximumBytes)
    }

    func archiveDigest(at source: URL, maximumBytes: Int64) throws -> Data {
        try base.archiveDigest(at: source, maximumBytes: maximumBytes)
    }

    func publishArchive(at source: URL, to destination: URL, expectedDigest: Data, maximumBytes: Int64) throws {
        try base.publishArchive(
            at: source,
            to: destination,
            expectedDigest: expectedDigest,
            maximumBytes: maximumBytes
        )
    }
}

struct SourceGrowingFileOperations: ExportFileOperating {
    private let base = POSIXExportFileOperations()

    func snapshotSource(at source: URL, to destination: URL, maximumBytes: Int64) throws {
        let handle = try FileHandle(forWritingTo: source)
        try handle.truncate(atOffset: UInt64(maximumBytes + 1))
        try handle.close()
        try base.snapshotSource(at: source, to: destination, maximumBytes: maximumBytes)
    }

    func archiveDigest(at source: URL, maximumBytes: Int64) throws -> Data {
        try base.archiveDigest(at: source, maximumBytes: maximumBytes)
    }

    func publishArchive(at source: URL, to destination: URL, expectedDigest: Data, maximumBytes: Int64) throws {
        try base.publishArchive(
            at: source,
            to: destination,
            expectedDigest: expectedDigest,
            maximumBytes: maximumBytes
        )
    }
}

struct PublicationSymlinkSwapFileOperations: ExportFileOperating {
    let protectedTarget: URL
    private let base = POSIXExportFileOperations()

    func snapshotSource(at source: URL, to destination: URL, maximumBytes: Int64) throws {
        try base.snapshotSource(at: source, to: destination, maximumBytes: maximumBytes)
    }

    func archiveDigest(at source: URL, maximumBytes: Int64) throws -> Data {
        try base.archiveDigest(at: source, maximumBytes: maximumBytes)
    }

    func publishArchive(at source: URL, to destination: URL, expectedDigest: Data, maximumBytes: Int64) throws {
        try FileManager.default.createSymbolicLink(at: destination, withDestinationURL: protectedTarget)
        try base.publishArchive(
            at: source,
            to: destination,
            expectedDigest: expectedDigest,
            maximumBytes: maximumBytes
        )
    }
}

struct ArchiveGrowingAtPublicationFileOperations: ExportFileOperating {
    private let base = POSIXExportFileOperations()

    func snapshotSource(at source: URL, to destination: URL, maximumBytes: Int64) throws {
        try base.snapshotSource(at: source, to: destination, maximumBytes: maximumBytes)
    }

    func archiveDigest(at source: URL, maximumBytes: Int64) throws -> Data {
        try base.archiveDigest(at: source, maximumBytes: maximumBytes)
    }

    func publishArchive(at source: URL, to destination: URL, expectedDigest: Data, maximumBytes: Int64) throws {
        let handle = try FileHandle(forWritingTo: source)
        try handle.truncate(atOffset: 20 * 1_024 * 1_024 + 1)
        try handle.close()
        try base.publishArchive(
            at: source,
            to: destination,
            expectedDigest: expectedDigest,
            maximumBytes: maximumBytes
        )
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
        try await rejectsUnsupportedImageExtension()
        try await rejectsDisguisedImagePayload()
        try await rejectsOversizedManifest()
        try await rejectsOversizedSourceSnapshot()
        try await rejectsOversizedArchiveBeforePublication()
        try await rejectsSourceSwappedToSymlinkAtSnapshotBoundary()
        try await rejectsSourceGrowthAtSnapshotBoundary()
        try await rejectsSameSizeSourceMutationDuringSnapshot()
        try await rejectsSameSizeArchiveMutationAfterReadback()
        try await rejectsArchiveGrowthAtPublicationBoundary()
        try await safelyReplacesSymlinkIntroducedInsidePublicationWindow()
        try await rejectsStagedEntryReplacementBeforeRename()
        print("PASS: ThemePackageExporterTests")
    }

    private static func rejectsSameSizeSourceMutationDuringSnapshot() async throws {
        let root = try makeTemporaryDirectory(prefix: "exporter-source-same-size-mutation")
        defer { try? FileManager.default.removeItem(at: root) }
        let theme = try writeExportTheme(in: root, id: "source-same-size-mutation")
        let operations = POSIXExportFileOperations(didInspectSource: { source in
            let descriptor = Darwin.open(source.path, O_WRONLY | O_CLOEXEC)
            guard descriptor >= 0 else {
                throw TestFailure(description: "same-size source mutation fixture could not open source")
            }
            defer { Darwin.close(descriptor) }
            var replacement: UInt8 = 0
            guard Darwin.pwrite(descriptor, &replacement, 1, 0) == 1,
                  Darwin.fsync(descriptor) == 0
            else {
                throw TestFailure(description: "same-size source mutation fixture could not overwrite source")
            }
        })

        do {
            _ = try await ThemePackageExporter(fileOperations: operations).export(
                theme: theme,
                to: root.appendingPathComponent("source-same-size-mutation.codexskin")
            )
            throw TestFailure(description: "same-size source mutation must be rejected")
        } catch ManagerError.invalidPackage(let message) {
            try expect(message.contains("发生了变化"), "same-size source mutation rejection must be actionable")
        }
    }

    private static func rejectsSameSizeArchiveMutationAfterReadback() async throws {
        let root = try makeTemporaryDirectory(prefix: "exporter-archive-same-size-mutation")
        defer { try? FileManager.default.removeItem(at: root) }
        let theme = try writeExportTheme(in: root, id: "archive-same-size-mutation")
        let destination = root.appendingPathComponent("archive-same-size-mutation.codexskin")

        do {
            _ = try await ThemePackageExporter(runner: ArchiveSameSizeMutatingRunner()).export(
                theme: theme,
                to: destination
            )
            throw TestFailure(description: "same-size archive mutation after readback must be rejected")
        } catch ManagerError.invalidPackage(let message) {
            try expect(message.contains("发生了变化"), "same-size archive mutation rejection must be actionable")
        }
        try expect(!FileManager.default.fileExists(atPath: destination.path), "mutated archive must not publish")
    }

    private static func rejectsStagedEntryReplacementBeforeRename() async throws {
        let root = try makeTemporaryDirectory(prefix: "exporter-staged-entry-replacement")
        defer { try? FileManager.default.removeItem(at: root) }
        let theme = try writeExportTheme(in: root, id: "staged-entry-replacement")
        let destination = root.appendingPathComponent("staged-entry-replacement.codexskin")
        let protectedTarget = root.appendingPathComponent("protected-target.codexskin")
        let destinationSentinel = Data("destination must remain unchanged".utf8)
        let protectedSentinel = Data("target must remain unchanged".utf8)
        try destinationSentinel.write(to: destination)
        try protectedSentinel.write(to: protectedTarget)
        let operations = POSIXExportFileOperations(beforePublicationIdentityCheck: { directoryFD, entryName in
            guard Darwin.unlinkat(directoryFD, entryName, 0) == 0,
                  Darwin.symlinkat(protectedTarget.path, directoryFD, entryName) == 0
            else {
                throw TestFailure(description: "staged entry replacement fixture could not replace pathname")
            }
        })

        do {
            _ = try await ThemePackageExporter(fileOperations: operations).export(
                theme: theme,
                to: destination
            )
            throw TestFailure(description: "replaced staged entry must be rejected")
        } catch ManagerError.invalidPackage(let message) {
            try expect(message.contains("身份"), "staged entry replacement rejection must be actionable")
        }
        let destinationContents = try Data(contentsOf: destination)
        let protectedContents = try Data(contentsOf: protectedTarget)
        let remainingEntries = try FileManager.default.contentsOfDirectory(atPath: root.path)
        try expect(destinationContents == destinationSentinel, "destination must remain unchanged")
        try expect(protectedContents == protectedSentinel, "protected target must remain unchanged")
        try expect(
            !remainingEntries.contains(where: { $0.hasPrefix(".codexskin-export-") }),
            "rejected publication must clean only its private staging directory"
        )
    }

    private static func rejectsSourceSwappedToSymlinkAtSnapshotBoundary() async throws {
        let root = try makeTemporaryDirectory(prefix: "exporter-source-swap")
        defer { try? FileManager.default.removeItem(at: root) }
        let theme = try writeExportTheme(in: root, id: "source-swap")
        let replacement = root.appendingPathComponent("replacement.png")
        try Data(contentsOf: theme.imageURL).write(to: replacement)
        let operations = SourceSwappingFileOperations(replacement: replacement)

        do {
            _ = try await ThemePackageExporter(fileOperations: operations).export(
                theme: theme,
                to: root.appendingPathComponent("source-swap.codexskin")
            )
            throw TestFailure(description: "source swapped to symlink must be rejected")
        } catch ManagerError.invalidPackage(let message) {
            try expect(message.contains("普通文件"), "source swap rejection must be actionable")
        }
    }

    private static func rejectsSourceGrowthAtSnapshotBoundary() async throws {
        let root = try makeTemporaryDirectory(prefix: "exporter-source-growth")
        defer { try? FileManager.default.removeItem(at: root) }
        let theme = try writeExportTheme(in: root, id: "source-growth")

        do {
            _ = try await ThemePackageExporter(fileOperations: SourceGrowingFileOperations()).export(
                theme: theme,
                to: root.appendingPathComponent("source-growth.codexskin")
            )
            throw TestFailure(description: "source growth at snapshot boundary must be rejected")
        } catch ManagerError.invalidPackage(let message) {
            try expect(message.contains("32 MB"), "source growth rejection must be actionable")
        }
    }

    private static func safelyReplacesSymlinkIntroducedInsidePublicationWindow() async throws {
        let root = try makeTemporaryDirectory(prefix: "exporter-publication-window")
        defer { try? FileManager.default.removeItem(at: root) }
        let theme = try writeExportTheme(in: root, id: "publication-window")
        let destination = root.appendingPathComponent("publication-window.codexskin")
        let protectedTarget = root.appendingPathComponent("protected-target.codexskin")
        let sentinel = Data("must remain unchanged".utf8)
        try sentinel.write(to: protectedTarget)
        let operations = PublicationSymlinkSwapFileOperations(protectedTarget: protectedTarget)

        let output = try await ThemePackageExporter(fileOperations: operations).export(
            theme: theme,
            to: destination
        )

        let targetContents = try Data(contentsOf: protectedTarget)
        let entries = try await archiveEntries(at: output)
        try expect(targetContents == sentinel, "publication race must not modify symlink target")
        try expect(entries.exitCode == 0, "publication race output must remain a readable archive")
        try expect(
            Set(entries.stdout.split(separator: "\n").map(String.init)) == ["theme.json", "background.png"],
            "publication race output entries mismatch"
        )
        let attributes = try FileManager.default.attributesOfItem(atPath: output.path)
        let permissions = attributes[FileAttributeKey.posixPermissions] as? NSNumber
        try expect(permissions?.intValue == 0o600, "publication race output must be 0600")
    }

    private static func rejectsArchiveGrowthAtPublicationBoundary() async throws {
        let root = try makeTemporaryDirectory(prefix: "exporter-archive-publication-growth")
        defer { try? FileManager.default.removeItem(at: root) }
        let theme = try writeExportTheme(in: root, id: "archive-publication-growth")
        let destination = root.appendingPathComponent("archive-publication-growth.codexskin")

        do {
            _ = try await ThemePackageExporter(
                fileOperations: ArchiveGrowingAtPublicationFileOperations()
            ).export(theme: theme, to: destination)
            throw TestFailure(description: "archive growth at publication boundary must be rejected")
        } catch ManagerError.invalidPackage(let message) {
            try expect(message.contains("20 MB"), "publication archive growth rejection must be actionable")
        }
        try expect(!FileManager.default.fileExists(atPath: destination.path), "grown archive must not publish")
    }

    private static func rejectsUnsupportedImageExtension() async throws {
        let root = try makeTemporaryDirectory(prefix: "exporter-extension")
        defer { try? FileManager.default.removeItem(at: root) }
        let original = try writeExportTheme(in: root, id: "unsupported-extension")
        let theme = replacingManifestImage(of: original, with: "background.gif")

        do {
            _ = try await ThemePackageExporter().export(
                theme: theme,
                to: root.appendingPathComponent("unsupported-extension.codexskin")
            )
            throw TestFailure(description: "unsupported image extension must be rejected")
        } catch ManagerError.invalidPackage(let message) {
            try expect(message.contains("PNG、JPEG 或 WebP"), "extension rejection must be actionable")
        }
    }

    private static func rejectsDisguisedImagePayload() async throws {
        let root = try makeTemporaryDirectory(prefix: "exporter-disguised-image")
        defer { try? FileManager.default.removeItem(at: root) }
        let theme = try writeExportTheme(in: root, id: "disguised-image")
        try Data("not a png".utf8).write(to: theme.imageURL, options: .atomic)

        do {
            _ = try await ThemePackageExporter().export(
                theme: theme,
                to: root.appendingPathComponent("disguised-image.codexskin")
            )
            throw TestFailure(description: "disguised image payload must be rejected")
        } catch ManagerError.invalidPackage(let message) {
            try expect(message.contains("无法解码"), "image decoding rejection must be actionable")
        }
    }

    private static func rejectsOversizedSourceSnapshot() async throws {
        let root = try makeTemporaryDirectory(prefix: "exporter-oversized-source")
        defer { try? FileManager.default.removeItem(at: root) }
        let theme = try writeExportTheme(in: root, id: "oversized-source")
        let handle = try FileHandle(forWritingTo: theme.imageURL)
        try handle.truncate(atOffset: 32 * 1_024 * 1_024 + 1)
        try handle.close()

        do {
            _ = try await ThemePackageExporter().export(
                theme: theme,
                to: root.appendingPathComponent("oversized-source.codexskin")
            )
            throw TestFailure(description: "oversized source snapshot must be rejected")
        } catch ManagerError.invalidPackage(let message) {
            try expect(message.contains("32 MB"), "source size rejection must be actionable")
        }
    }

    private static func rejectsOversizedManifest() async throws {
        let root = try makeTemporaryDirectory(prefix: "exporter-oversized-manifest")
        defer { try? FileManager.default.removeItem(at: root) }
        let original = try writeExportTheme(in: root, id: "oversized-manifest")
        let manifest = ThemeManifest(
            schemaVersion: original.manifest.schemaVersion,
            id: original.manifest.id,
            name: String(repeating: "x", count: 65_536),
            image: original.manifest.image,
            appearance: original.manifest.appearance
        )
        let theme = ThemeRecord(
            libraryID: original.libraryID,
            manifest: manifest,
            directoryURL: original.directoryURL,
            imageURL: original.imageURL,
            isActive: original.isActive
        )

        do {
            _ = try await ThemePackageExporter().export(
                theme: theme,
                to: root.appendingPathComponent("oversized-manifest.codexskin")
            )
            throw TestFailure(description: "oversized manifest must be rejected")
        } catch ManagerError.invalidPackage(let message) {
            try expect(message.contains("64 KB"), "manifest size rejection must be actionable")
        }
    }

    private static func rejectsOversizedArchiveBeforePublication() async throws {
        let root = try makeTemporaryDirectory(prefix: "exporter-oversized-archive")
        defer { try? FileManager.default.removeItem(at: root) }
        let theme = try writeExportTheme(in: root, id: "oversized-archive")
        let destination = root.appendingPathComponent("oversized-archive.codexskin")

        do {
            _ = try await ThemePackageExporter(runner: ArchiveInflatingRunner()).export(
                theme: theme,
                to: destination
            )
            throw TestFailure(description: "oversized archive must be rejected before publication")
        } catch ManagerError.invalidPackage(let message) {
            try expect(message.contains("20 MB"), "archive size rejection must be actionable")
        }
        try expect(!FileManager.default.fileExists(atPath: destination.path), "oversized archive must not publish")
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

    private static func replacingManifestImage(of theme: ThemeRecord, with image: String) -> ThemeRecord {
        let manifest = ThemeManifest(
            schemaVersion: theme.manifest.schemaVersion,
            id: theme.manifest.id,
            name: theme.manifest.name,
            image: image,
            appearance: theme.manifest.appearance
        )
        return ThemeRecord(
            libraryID: theme.libraryID,
            manifest: manifest,
            directoryURL: theme.directoryURL,
            imageURL: theme.imageURL,
            isActive: theme.isActive
        )
    }
}
