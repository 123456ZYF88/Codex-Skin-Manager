import Foundation

package protocol ThemePackageFileOperating: Sendable {
    func itemExists(at url: URL) -> Bool
    func isDirectory(at url: URL) -> Bool
    func isSymbolicLink(at url: URL) throws -> Bool
    func isRegularFile(at url: URL) throws -> Bool
    func createDirectory(at url: URL, permissions: Int) throws
    func setPermissions(_ permissions: Int, at url: URL) throws
    func permissions(at url: URL) throws -> Int
    func copyItem(at source: URL, to destination: URL) throws
    func removeItem(at url: URL) throws
}

package struct POSIXThemePackageFileOperations: ThemePackageFileOperating, @unchecked Sendable {
    package init() {}

    package func itemExists(at url: URL) -> Bool { FileManager.default.fileExists(atPath: url.path) }
    package func isDirectory(at url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) && isDirectory.boolValue
    }
    package func isSymbolicLink(at url: URL) throws -> Bool {
        try url.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink == true
    }
    package func isRegularFile(at url: URL) throws -> Bool {
        try url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true
    }
    package func createDirectory(at url: URL, permissions: Int) throws {
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true, attributes: [.posixPermissions: permissions])
    }
    package func setPermissions(_ permissions: Int, at url: URL) throws {
        try FileManager.default.setAttributes([.posixPermissions: permissions], ofItemAtPath: url.path)
    }
    package func permissions(at url: URL) throws -> Int {
        guard let value = try FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions] as? Int else {
            throw ManagerError.invalidResponse("无法读取导入暂存权限。")
        }
        return value
    }
    package func copyItem(at source: URL, to destination: URL) throws { try FileManager.default.copyItem(at: source, to: destination) }
    package func removeItem(at url: URL) throws { try FileManager.default.removeItem(at: url) }
}

package enum ThemePackageDeferredStore {
    package static func isRegularPackage(_ url: URL, operations: any ThemePackageFileOperating = POSIXThemePackageFileOperations()) -> Bool {
        guard url.isFileURL,
              url.pathExtension.localizedCaseInsensitiveCompare("codexskin") == .orderedSame,
              (try? operations.isRegularFile(at: url)) == true,
              (try? operations.isSymbolicLink(at: url)) != true
        else { return false }
        return true
    }

    package static func stage(
        _ source: URL,
        root: URL = defaultRoot(),
        operations: any ThemePackageFileOperating = POSIXThemePackageFileOperations()
    ) throws -> URL {
        guard isRegularPackage(source, operations: operations) else {
            throw ManagerError.invalidResponse("导入包必须是普通 .codexskin 文件。")
        }
        try prepareRoot(root, operations: operations)
        let destination = root.appendingPathComponent("\(UUID().uuidString).codexskin")
        do {
            try operations.copyItem(at: source, to: destination)
            try operations.setPermissions(0o600, at: destination)
            guard isRegularPackage(destination, operations: operations),
                  try operations.permissions(at: destination) == 0o600
            else { throw ManagerError.invalidResponse("导入暂存文件安全校验失败。") }
            return destination
        } catch {
            try? operations.removeItem(at: destination)
            throw error
        }
    }

    private static func prepareRoot(_ root: URL, operations: any ThemePackageFileOperating) throws {
        if operations.itemExists(at: root) {
            guard operations.isDirectory(at: root), try !operations.isSymbolicLink(at: root) else {
                throw ManagerError.invalidResponse("导入暂存目录不安全。")
            }
        } else {
            try operations.createDirectory(at: root, permissions: 0o700)
        }
        try operations.setPermissions(0o700, at: root)
        guard try operations.permissions(at: root) == 0o700,
              try !operations.isSymbolicLink(at: root),
              operations.isDirectory(at: root)
        else { throw ManagerError.invalidResponse("导入暂存目录权限校验失败。") }
    }

    package static func defaultRoot() -> URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support", isDirectory: true)
            .appendingPathComponent("CodexDreamSkinStudio", isDirectory: true)
            .appendingPathComponent("PendingThemeImports", isDirectory: true)
    }
}
