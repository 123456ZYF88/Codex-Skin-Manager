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

func writeExportTheme(in root: URL, id: String) throws -> ThemeRecord {
    let directory = root.appendingPathComponent(id, isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
    let manifest = ThemeManifest(
        schemaVersion: 1,
        id: id,
        name: "Safe Theme",
        image: "background.png",
        appearance: "dark"
    )
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    try encoder.encode(manifest).write(
        to: directory.appendingPathComponent("theme.json"),
        options: .atomic
    )
    let png = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAusB9Y9Z4ZkAAAAASUVORK5CYII=")!
    let imageURL = directory.appendingPathComponent("background.png")
    try png.write(to: imageURL, options: .atomic)
    return ThemeRecord(
        libraryID: id,
        manifest: manifest,
        directoryURL: directory,
        imageURL: imageURL,
        isActive: false
    )
}
