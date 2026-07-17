import Foundation

package struct ThemeManifest: Codable, Equatable, Sendable {
    package let schemaVersion: Int
    package let id: String
    package let name: String
    package let image: String
    package let appearance: String?

    package init(schemaVersion: Int, id: String, name: String, image: String, appearance: String?) {
        self.schemaVersion = schemaVersion
        self.id = id
        self.name = name
        self.image = image
        self.appearance = appearance
    }
}

package struct ThemeRecord: Identifiable, Equatable, Sendable {
    package let libraryID: String
    package let manifest: ThemeManifest
    package let directoryURL: URL
    package let imageURL: URL
    package let isActive: Bool

    package var id: String { libraryID }

    package init(
        libraryID: String,
        manifest: ThemeManifest,
        directoryURL: URL,
        imageURL: URL,
        isActive: Bool
    ) {
        self.libraryID = libraryID
        self.manifest = manifest
        self.directoryURL = directoryURL
        self.imageURL = imageURL
        self.isActive = isActive
    }
}

package struct EngineStatus: Codable, Equatable, Sendable {
    package let session: String
    package let port: Int
    package let injectorAlive: Bool
    package let cdpOk: Bool
    package let codexRunning: Bool
    package let themeName: String

    package init(
        session: String,
        port: Int,
        injectorAlive: Bool,
        cdpOk: Bool,
        codexRunning: Bool,
        themeName: String
    ) {
        self.session = session
        self.port = port
        self.injectorAlive = injectorAlive
        self.cdpOk = cdpOk
        self.codexRunning = codexRunning
        self.themeName = themeName
    }
}

package protocol ThemeCatalogReading: Sendable {
    func loadThemes() throws -> [ThemeRecord]
    func loadActiveTheme() -> ThemeManifest?
}
