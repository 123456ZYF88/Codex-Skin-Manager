import Foundation
import ImageIO

package protocol ThemePackageExporting: Sendable {
    func export(theme: ThemeRecord, to destination: URL) async throws -> URL
}

package struct ThemePackageExporter: ThemePackageExporting, Sendable {
    private let runner: any CommandRunning
    private let fileOperations: any ExportFileOperating

    package init(
        runner: any CommandRunning = ProcessRunner(),
        fileOperations: any ExportFileOperating = POSIXExportFileOperations()
    ) {
        self.runner = runner
        self.fileOperations = fileOperations
    }

    package func export(theme: ThemeRecord, to destination: URL) async throws -> URL {
        guard destination.pathExtension.lowercased() == "codexskin" else {
            throw ManagerError.invalidPackage("导出文件必须使用 .codexskin 扩展名。")
        }
        let imageName = theme.manifest.image
        guard !imageName.isEmpty,
              imageName != ".",
              imageName != "..",
              !imageName.hasPrefix("."),
              !imageName.contains("/"),
              !imageName.contains("\\")
        else {
            throw ManagerError.invalidPackage("主题图片必须使用安全的平坦文件名。")
        }
        let imageExtension = URL(fileURLWithPath: imageName).pathExtension.lowercased()
        guard ["png", "jpg", "jpeg", "webp"].contains(imageExtension) else {
            throw ManagerError.invalidPackage("主题图片必须是 PNG、JPEG 或 WebP。")
        }

        let fileManager = FileManager.default
        if (try? fileManager.destinationOfSymbolicLink(atPath: destination.path)) != nil {
            throw ManagerError.invalidPackage("导出目标不能是符号链接。")
        }

        let work = fileManager.temporaryDirectory
            .appendingPathComponent("CodexSkinManagerExport-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(
            at: work,
            withIntermediateDirectories: false,
            attributes: [.posixPermissions: 0o700]
        )
        defer { try? fileManager.removeItem(at: work) }

        let manifestURL = work.appendingPathComponent("theme.json")
        let imageURL = work.appendingPathComponent(imageName)
        let archiveURL = work.appendingPathComponent("package.codexskin")
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let manifestData = try encoder.encode(theme.manifest)
        guard manifestData.count <= 64 * 1_024 else {
            throw ManagerError.invalidPackage("主题清单不得超过 64 KB。")
        }
        try manifestData.write(to: manifestURL, options: .atomic)
        let maximumImageBytes = Int64(32 * 1_024 * 1_024 - manifestData.count)
        try fileOperations.snapshotSource(
            at: theme.imageURL,
            to: imageURL,
            maximumBytes: maximumImageBytes
        )
        try validateImage(at: imageURL, extension: imageExtension)

        let zip = try await runner.run(CommandRequest(
            executable: URL(fileURLWithPath: "/usr/bin/zip"),
            arguments: ["-X", "-j", archiveURL.path, manifestURL.path, imageURL.path],
            timeout: 20
        ))
        guard zip.exitCode == 0 else {
            throw ManagerError.invalidPackage("无法创建主题包。")
        }

        let maximumArchiveBytes = Int64(20 * 1_024 * 1_024)
        let validatedDigest = try fileOperations.archiveDigest(
            at: archiveURL,
            maximumBytes: maximumArchiveBytes
        )

        let list = try await runner.run(CommandRequest(
            executable: URL(fileURLWithPath: "/usr/bin/unzip"),
            arguments: ["-Z1", archiveURL.path],
            timeout: 10
        ))
        let entries = list.stdout.split(separator: "\n").map(String.init)
        guard list.exitCode == 0,
              entries.count == 2,
              Set(entries) == Set(["theme.json", imageName])
        else {
            throw ManagerError.invalidPackage("导出的主题包结构无效。")
        }

        let readbackDigest = try fileOperations.archiveDigest(
            at: archiveURL,
            maximumBytes: maximumArchiveBytes
        )
        guard readbackDigest == validatedDigest else {
            throw ManagerError.invalidPackage("导出的主题包在结构验证后发生了变化。")
        }

        // Recheck immediately before publication because ZIP creation leaves time for the target to change.
        if (try? fileManager.destinationOfSymbolicLink(atPath: destination.path)) != nil {
            throw ManagerError.invalidPackage("导出目标不能是符号链接。")
        }
        try fileOperations.publishArchive(
            at: archiveURL,
            to: destination,
            expectedDigest: validatedDigest,
            maximumBytes: maximumArchiveBytes
        )
        return destination
    }

    private func validateImage(at imageURL: URL, extension imageExtension: String) throws {
        let handle = try FileHandle(forReadingFrom: imageURL)
        let header = try handle.read(upToCount: 12) ?? Data()
        try handle.close()
        let bytes = [UInt8](header)
        let hasExpectedMagic: Bool
        switch imageExtension {
        case "png":
            hasExpectedMagic = bytes.starts(with: [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
        case "jpg", "jpeg":
            hasExpectedMagic = bytes.count >= 3 && bytes[0] == 0xFF && bytes[1] == 0xD8 && bytes[2] == 0xFF
        case "webp":
            hasExpectedMagic = bytes.count >= 12
                && Array(bytes[0..<4]) == Array("RIFF".utf8)
                && Array(bytes[8..<12]) == Array("WEBP".utf8)
        default:
            hasExpectedMagic = false
        }
        guard hasExpectedMagic,
              let source = CGImageSourceCreateWithURL(imageURL as CFURL, nil),
              CGImageSourceGetCount(source) == 1,
              CGImageSourceCreateImageAtIndex(source, 0, nil) != nil
        else {
            throw ManagerError.invalidPackage("主题图片内容无法解码或与扩展名不匹配。")
        }
    }
}
