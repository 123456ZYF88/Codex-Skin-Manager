import CodexSkinManagerCore
import Foundation

struct TestFailure: Error, CustomStringConvertible {
    let description: String
}

func expect(_ condition: @autoclosure () -> Bool, _ message: String) throws {
    guard condition() else { throw TestFailure(description: message) }
}

func makeTemporaryDirectory(prefix: String) throws -> URL {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("\(prefix)-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

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
