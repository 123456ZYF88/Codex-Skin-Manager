import Foundation

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
        let imageValues = try theme.imageURL.resourceValues(
            forKeys: [.isRegularFileKey, .isSymbolicLinkKey]
        )
        guard imageValues.isRegularFile == true, imageValues.isSymbolicLink != true else {
            throw ManagerError.invalidPackage("主题图片不是安全的普通文件。")
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
        try encoder.encode(theme.manifest).write(to: manifestURL, options: .atomic)
        try fileManager.copyItem(at: theme.imageURL, to: imageURL)

        let zip = try await runner.run(CommandRequest(
            executable: URL(fileURLWithPath: "/usr/bin/zip"),
            arguments: ["-X", "-j", archiveURL.path, manifestURL.path, imageURL.path],
            timeout: 20
        ))
        guard zip.exitCode == 0 else {
            throw ManagerError.invalidPackage("无法创建主题包。")
        }

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

        let parent = destination.deletingLastPathComponent()
        let published = parent.appendingPathComponent(
            ".\(destination.lastPathComponent).\(UUID().uuidString)"
        )
        // Recheck immediately before publication because ZIP creation leaves time for the target to change.
        if (try? fileManager.destinationOfSymbolicLink(atPath: destination.path)) != nil {
            throw ManagerError.invalidPackage("导出目标不能是符号链接。")
        }
        do {
            try fileManager.copyItem(at: archiveURL, to: published)
            // Restrict the staged inode before its atomic publication so no readable window exists.
            try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: published.path)
            if fileManager.fileExists(atPath: destination.path) {
                _ = try fileManager.replaceItemAt(destination, withItemAt: published)
            } else {
                try fileManager.moveItem(at: published, to: destination)
            }
            try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: destination.path)
        } catch {
            try? fileManager.removeItem(at: published)
            throw error
        }
        return destination
    }
}
