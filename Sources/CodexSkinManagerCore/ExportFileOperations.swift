import CryptoKit
import Darwin
import Foundation

package protocol ExportFileOperating: Sendable {
    func snapshotSource(at source: URL, to destination: URL, maximumBytes: Int64) throws
    func archiveDigest(at source: URL, maximumBytes: Int64) throws -> Data
    func publishArchive(
        at source: URL,
        to destination: URL,
        expectedDigest: Data,
        maximumBytes: Int64
    ) throws
}

package struct POSIXExportFileOperations: ExportFileOperating, Sendable {
    private let didInspectSource: @Sendable (URL) throws -> Void
    private let beforePublicationIdentityCheck: @Sendable (Int32, String) throws -> Void

    package init(
        didInspectSource: @escaping @Sendable (URL) throws -> Void = { _ in },
        beforePublicationIdentityCheck: @escaping @Sendable (Int32, String) throws -> Void = { _, _ in }
    ) {
        self.didInspectSource = didInspectSource
        self.beforePublicationIdentityCheck = beforePublicationIdentityCheck
    }

    package func snapshotSource(at source: URL, to destination: URL, maximumBytes: Int64) throws {
        let sourceFD = Darwin.open(source.path, O_RDONLY | O_NOFOLLOW | O_CLOEXEC)
        guard sourceFD >= 0 else {
            throw ManagerError.invalidPackage("主题图片不是安全的普通文件。")
        }
        defer { Darwin.close(sourceFD) }

        var before = stat()
        guard fstat(sourceFD, &before) == 0,
              isRegularFile(before)
        else {
            throw ManagerError.invalidPackage("主题图片不是安全的普通文件。")
        }
        guard before.st_size > 0, before.st_size <= maximumBytes else {
            throw ManagerError.invalidPackage("主题图片和清单展开后不得超过 32 MB。")
        }

        // This seam makes same-inode mutation tests deterministic; production uses the no-op default.
        try didInspectSource(source)

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

        try copyExactBytes(
            from: sourceFD,
            to: destinationFD,
            count: before.st_size,
            readFailure: "读取主题图片时文件发生了变化。"
        )

        var after = stat()
        var snapshot = stat()
        guard fstat(sourceFD, &after) == 0,
              fstat(destinationFD, &snapshot) == 0,
              sameStableFile(before, after),
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

    package func archiveDigest(at source: URL, maximumBytes: Int64) throws -> Data {
        let sourceFD = Darwin.open(source.path, O_RDONLY | O_NOFOLLOW | O_CLOEXEC)
        guard sourceFD >= 0 else {
            throw ManagerError.invalidPackage("无法读取待验证的主题包。")
        }
        defer { Darwin.close(sourceFD) }

        var before = stat()
        guard fstat(sourceFD, &before) == 0,
              isRegularFile(before),
              before.st_size > 0,
              before.st_size <= maximumBytes
        else {
            throw ManagerError.invalidPackage("导出的主题包不得超过 20 MB。")
        }
        let digest = try digest(
            of: sourceFD,
            count: before.st_size,
            readFailure: "读取待验证主题包时文件发生了变化。"
        )
        var after = stat()
        guard fstat(sourceFD, &after) == 0,
              sameStableFile(before, after)
        else {
            throw ManagerError.invalidPackage("待验证主题包发生了变化或超过 20 MB。")
        }
        return digest
    }

    package func publishArchive(
        at source: URL,
        to destination: URL,
        expectedDigest: Data,
        maximumBytes: Int64
    ) throws {
        let sourceFD = Darwin.open(source.path, O_RDONLY | O_NOFOLLOW | O_CLOEXEC)
        guard sourceFD >= 0 else {
            throw ManagerError.invalidPackage("无法读取待发布的主题包。")
        }
        defer { Darwin.close(sourceFD) }

        var sourceBefore = stat()
        guard fstat(sourceFD, &sourceBefore) == 0,
              isRegularFile(sourceBefore),
              sourceBefore.st_size > 0,
              sourceBefore.st_size <= maximumBytes
        else {
            throw ManagerError.invalidPackage("导出的主题包不得超过 20 MB。")
        }

        let parent = destination.deletingLastPathComponent()
        let destinationName = destination.lastPathComponent
        guard !destinationName.isEmpty,
              destinationName != ".",
              destinationName != "..",
              !destinationName.contains("/")
        else {
            throw ManagerError.invalidPackage("导出目标文件名无效。")
        }
        let parentFD = Darwin.open(parent.path, O_RDONLY | O_DIRECTORY | O_CLOEXEC)
        guard parentFD >= 0 else {
            throw ManagerError.invalidPackage("无法打开导出目标目录。")
        }
        defer { Darwin.close(parentFD) }

        // The entry is never exposed as a sibling in the user-visible directory before rename.
        let stagingDirectoryName = ".codexskin-export-\(UUID().uuidString)"
        guard Darwin.mkdirat(parentFD, stagingDirectoryName, S_IRWXU) == 0 else {
            throw ManagerError.invalidPackage("无法创建私有导出暂存目录。")
        }
        var stagingDirectoryCreated = true
        defer {
            if stagingDirectoryCreated {
                Darwin.unlinkat(parentFD, stagingDirectoryName, AT_REMOVEDIR)
            }
        }

        let stagingDirectoryFD = Darwin.openat(
            parentFD,
            stagingDirectoryName,
            O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC
        )
        guard stagingDirectoryFD >= 0 else {
            throw ManagerError.invalidPackage("无法打开私有导出暂存目录。")
        }
        defer { Darwin.close(stagingDirectoryFD) }
        guard fchmod(stagingDirectoryFD, S_IRWXU) == 0 else {
            throw ManagerError.invalidPackage("无法设置私有导出暂存目录权限。")
        }

        let stagedEntryName = "archive.codexskin"
        let stagedFD = Darwin.openat(
            stagingDirectoryFD,
            stagedEntryName,
            O_RDWR | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC,
            S_IRUSR | S_IWUSR
        )
        guard stagedFD >= 0 else {
            throw ManagerError.invalidPackage("无法创建安全的导出暂存文件。")
        }
        var published = false
        defer {
            Darwin.close(stagedFD)
            if !published {
                Darwin.unlinkat(stagingDirectoryFD, stagedEntryName, 0)
            }
        }

        var sourceHasher = SHA256()
        try copyExactBytes(
            from: sourceFD,
            to: stagedFD,
            count: sourceBefore.st_size,
            readFailure: "读取待发布主题包时文件发生了变化。",
            hasher: &sourceHasher
        )
        let copiedDigest = Data(sourceHasher.finalize())
        var sourceAfter = stat()
        guard fstat(sourceFD, &sourceAfter) == 0,
              sameStableFile(sourceBefore, sourceAfter),
              copiedDigest == expectedDigest
        else {
            throw ManagerError.invalidPackage("待发布主题包发生了变化或摘要不匹配。")
        }
        guard fchmod(stagedFD, S_IRUSR | S_IWUSR) == 0,
              fsync(stagedFD) == 0,
              fsync(stagingDirectoryFD) == 0
        else {
            throw ManagerError.invalidPackage("无法设置导出主题包的安全权限。")
        }

        // This seam deterministically exercises replacement after creation but before final proof.
        try beforePublicationIdentityCheck(stagingDirectoryFD, stagedEntryName)

        var stagedBefore = stat()
        var entryBefore = stat()
        guard fstat(stagedFD, &stagedBefore) == 0,
              fstatat(stagingDirectoryFD, stagedEntryName, &entryBefore, AT_SYMLINK_NOFOLLOW) == 0,
              isRegularFile(stagedBefore),
              sameDirectoryEntry(stagedBefore, entryBefore),
              stagedBefore.st_nlink > 0,
              stagedBefore.st_size == sourceBefore.st_size
        else {
            throw ManagerError.invalidPackage("导出暂存文件路径身份已发生变化。")
        }
        let stagedDigest = try digest(
            of: stagedFD,
            count: stagedBefore.st_size,
            readFailure: "读取导出暂存文件时文件发生了变化。"
        )
        var stagedAfter = stat()
        var entryAfter = stat()
        guard fstat(stagedFD, &stagedAfter) == 0,
              fstatat(stagingDirectoryFD, stagedEntryName, &entryAfter, AT_SYMLINK_NOFOLLOW) == 0,
              sameStableFile(stagedBefore, stagedAfter),
              sameDirectoryEntry(stagedAfter, entryAfter),
              stagedAfter.st_nlink > 0,
              stagedDigest == expectedDigest
        else {
            throw ManagerError.invalidPackage("导出暂存文件身份或摘要已发生变化。")
        }

        // macOS has no rename-by-file-descriptor primitive. The private directory FD and the
        // adjacent identity proof close normal pathname races; a hostile same-UID process can
        // still race these two syscalls because it can override owner-only directory permissions.
        guard Darwin.renameat(
            stagingDirectoryFD,
            stagedEntryName,
            parentFD,
            destinationName
        ) == 0 else {
            throw ManagerError.invalidPackage("无法原子发布主题包。")
        }
        published = true
        _ = Darwin.fsync(parentFD)
        if Darwin.unlinkat(parentFD, stagingDirectoryName, AT_REMOVEDIR) == 0 {
            stagingDirectoryCreated = false
        }
    }

    private func copyExactBytes(
        from sourceFD: Int32,
        to destinationFD: Int32,
        count: Int64,
        readFailure: String,
        hasher: inout SHA256
    ) throws {
        var remaining = count
        var buffer = [UInt8](repeating: 0, count: 64 * 1_024)
        while remaining > 0 {
            let requested = min(Int64(buffer.count), remaining)
            let readCount = try readSome(
                from: sourceFD,
                into: &buffer,
                count: Int(requested),
                failure: readFailure
            )
            guard readCount > 0 else {
                throw ManagerError.invalidPackage(readFailure)
            }
            hasher.update(data: Data(buffer.prefix(readCount)))
            try writeAll(buffer: buffer, count: readCount, to: destinationFD)
            remaining -= Int64(readCount)
        }
    }

    private func copyExactBytes(
        from sourceFD: Int32,
        to destinationFD: Int32,
        count: Int64,
        readFailure: String
    ) throws {
        var unusedHasher = SHA256()
        try copyExactBytes(
            from: sourceFD,
            to: destinationFD,
            count: count,
            readFailure: readFailure,
            hasher: &unusedHasher
        )
    }

    private func digest(of fileDescriptor: Int32, count: Int64, readFailure: String) throws -> Data {
        guard Darwin.lseek(fileDescriptor, 0, SEEK_SET) == 0 else {
            throw ManagerError.invalidPackage(readFailure)
        }
        var hasher = SHA256()
        var remaining = count
        var buffer = [UInt8](repeating: 0, count: 64 * 1_024)
        while remaining > 0 {
            let requested = min(Int64(buffer.count), remaining)
            let readCount = try readSome(
                from: fileDescriptor,
                into: &buffer,
                count: Int(requested),
                failure: readFailure
            )
            guard readCount > 0 else {
                throw ManagerError.invalidPackage(readFailure)
            }
            hasher.update(data: Data(buffer.prefix(readCount)))
            remaining -= Int64(readCount)
        }
        return Data(hasher.finalize())
    }

    private func readSome(
        from fileDescriptor: Int32,
        into buffer: inout [UInt8],
        count: Int,
        failure: String
    ) throws -> Int {
        while true {
            let result = buffer.withUnsafeMutableBytes { bytes in
                Darwin.read(fileDescriptor, bytes.baseAddress, count)
            }
            if result >= 0 { return result }
            if errno != EINTR {
                throw ManagerError.invalidPackage(failure)
            }
        }
    }

    private func writeAll(buffer: [UInt8], count: Int, to fileDescriptor: Int32) throws {
        var written = 0
        while written < count {
            let result = buffer.withUnsafeBytes { bytes in
                Darwin.write(fileDescriptor, bytes.baseAddress!.advanced(by: written), count - written)
            }
            if result > 0 {
                written += result
            } else if result < 0, errno == EINTR {
                continue
            } else {
                throw ManagerError.invalidPackage("写入安全暂存文件失败。")
            }
        }
    }

    private func isRegularFile(_ value: stat) -> Bool {
        (value.st_mode & S_IFMT) == S_IFREG
    }

    private func sameStableFile(_ before: stat, _ after: stat) -> Bool {
        before.st_dev == after.st_dev
            && before.st_ino == after.st_ino
            && before.st_size == after.st_size
            && before.st_mtimespec.tv_sec == after.st_mtimespec.tv_sec
            && before.st_mtimespec.tv_nsec == after.st_mtimespec.tv_nsec
            && before.st_ctimespec.tv_sec == after.st_ctimespec.tv_sec
            && before.st_ctimespec.tv_nsec == after.st_ctimespec.tv_nsec
    }

    private func sameDirectoryEntry(_ descriptor: stat, _ entry: stat) -> Bool {
        descriptor.st_dev == entry.st_dev
            && descriptor.st_ino == entry.st_ino
            && (entry.st_mode & S_IFMT) == S_IFREG
    }
}
