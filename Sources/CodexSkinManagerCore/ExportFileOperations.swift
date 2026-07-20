import Darwin
import Foundation

package protocol ExportFileOperating: Sendable {
    func snapshotSource(at source: URL, to destination: URL, maximumBytes: Int64) throws
    func publishArchive(at source: URL, to destination: URL) throws
}

package struct POSIXExportFileOperations: ExportFileOperating, Sendable {
    package init() {}

    package func snapshotSource(at source: URL, to destination: URL, maximumBytes: Int64) throws {
        let sourceFD = Darwin.open(source.path, O_RDONLY | O_NOFOLLOW | O_CLOEXEC)
        guard sourceFD >= 0 else {
            throw ManagerError.invalidPackage("主题图片不是安全的普通文件。")
        }
        defer { Darwin.close(sourceFD) }

        var before = stat()
        guard fstat(sourceFD, &before) == 0,
              (before.st_mode & S_IFMT) == S_IFREG
        else {
            throw ManagerError.invalidPackage("主题图片不是安全的普通文件。")
        }
        guard before.st_size > 0, before.st_size <= maximumBytes else {
            throw ManagerError.invalidPackage("主题图片和清单展开后不得超过 32 MB。")
        }

        let destinationFD = Darwin.open(
            destination.path,
            O_WRONLY | O_CREAT | O_EXCL | O_CLOEXEC,
            S_IRUSR | S_IWUSR
        )
        guard destinationFD >= 0 else {
            throw ManagerError.invalidPackage("无法安全暂存主题图片。")
        }
        var completed = false
        defer {
            Darwin.close(destinationFD)
            if !completed { Darwin.unlink(destination.path) }
        }

        var remaining = before.st_size
        var buffer = [UInt8](repeating: 0, count: 64 * 1_024)
        while remaining > 0 {
            let requested = min(Int64(buffer.count), remaining)
            let count = buffer.withUnsafeMutableBytes { bytes in
                Darwin.read(sourceFD, bytes.baseAddress, Int(requested))
            }
            guard count > 0 else {
                throw ManagerError.invalidPackage("读取主题图片时文件发生了变化。")
            }
            try writeAll(buffer: buffer, count: count, to: destinationFD)
            remaining -= Int64(count)
        }

        var after = stat()
        var snapshot = stat()
        guard fstat(sourceFD, &after) == 0,
              fstat(destinationFD, &snapshot) == 0,
              after.st_dev == before.st_dev,
              after.st_ino == before.st_ino,
              after.st_size == before.st_size,
              snapshot.st_size == before.st_size
        else {
            throw ManagerError.invalidPackage("读取主题图片时文件发生了变化或超过 32 MB。")
        }
        guard fchmod(destinationFD, S_IRUSR | S_IWUSR) == 0,
              fsync(destinationFD) == 0
        else {
            throw ManagerError.invalidPackage("无法安全暂存主题图片。")
        }
        completed = true
    }

    package func publishArchive(at source: URL, to destination: URL) throws {
        let sourceFD = Darwin.open(source.path, O_RDONLY | O_NOFOLLOW | O_CLOEXEC)
        guard sourceFD >= 0 else {
            throw ManagerError.invalidPackage("无法读取待发布的主题包。")
        }
        defer { Darwin.close(sourceFD) }

        var sourceStat = stat()
        guard fstat(sourceFD, &sourceStat) == 0,
              (sourceStat.st_mode & S_IFMT) == S_IFREG
        else {
            throw ManagerError.invalidPackage("待发布的主题包不是普通文件。")
        }
        guard sourceStat.st_size > 0,
              sourceStat.st_size <= 20 * 1_024 * 1_024
        else {
            throw ManagerError.invalidPackage("导出的主题包不得超过 20 MB。")
        }

        let parent = destination.deletingLastPathComponent()
        let staged = parent.appendingPathComponent(
            ".\(destination.lastPathComponent).\(UUID().uuidString)"
        )
        let stagedFD = Darwin.open(
            staged.path,
            O_WRONLY | O_CREAT | O_EXCL | O_CLOEXEC,
            S_IRUSR | S_IWUSR
        )
        guard stagedFD >= 0 else {
            throw ManagerError.invalidPackage("无法创建安全的导出暂存文件。")
        }
        var published = false
        defer {
            Darwin.close(stagedFD)
            if !published { Darwin.unlink(staged.path) }
        }

        var remaining = sourceStat.st_size
        var buffer = [UInt8](repeating: 0, count: 64 * 1_024)
        while remaining > 0 {
            let requested = min(Int64(buffer.count), remaining)
            let count = buffer.withUnsafeMutableBytes { bytes in
                Darwin.read(sourceFD, bytes.baseAddress, Int(requested))
            }
            guard count > 0 else {
                throw ManagerError.invalidPackage("读取待发布主题包时文件发生了变化。")
            }
            try writeAll(buffer: buffer, count: count, to: stagedFD)
            remaining -= Int64(count)
        }

        var after = stat()
        var stagedStat = stat()
        guard fstat(sourceFD, &after) == 0,
              fstat(stagedFD, &stagedStat) == 0,
              after.st_dev == sourceStat.st_dev,
              after.st_ino == sourceStat.st_ino,
              after.st_size == sourceStat.st_size,
              stagedStat.st_size == sourceStat.st_size
        else {
            throw ManagerError.invalidPackage("待发布主题包发生了变化或超过 20 MB。")
        }
        guard fchmod(stagedFD, S_IRUSR | S_IWUSR) == 0,
              fsync(stagedFD) == 0
        else {
            throw ManagerError.invalidPackage("无法设置导出主题包的安全权限。")
        }
        guard Darwin.rename(staged.path, destination.path) == 0 else {
            throw ManagerError.invalidPackage("无法原子发布主题包。")
        }
        published = true
    }

    private func writeAll(buffer: [UInt8], count: Int, to fileDescriptor: Int32) throws {
        var written = 0
        while written < count {
            let result = buffer.withUnsafeBytes { bytes in
                Darwin.write(fileDescriptor, bytes.baseAddress!.advanced(by: written), count - written)
            }
            guard result > 0 else {
                throw ManagerError.invalidPackage("写入安全暂存文件失败。")
            }
            written += result
        }
    }
}
