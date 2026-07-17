import Foundation

package struct ThemeCatalog: ThemeCatalogReading, Sendable {
    package let stateRoot: URL

    package init(stateRoot: URL) {
        self.stateRoot = stateRoot.standardizedFileURL
    }

    package func loadThemes() throws -> [ThemeRecord] {
        let themesRoot = stateRoot.appendingPathComponent("themes", isDirectory: true)
        guard FileManager.default.fileExists(atPath: themesRoot.path) else { return [] }

        let active = loadActiveTheme()
        let urls = try FileManager.default.contentsOfDirectory(
            at: themesRoot,
            includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey],
            options: [.skipsHiddenFiles]
        )
        var candidates: [(libraryID: String, manifest: ThemeManifest, directory: URL, image: URL)] = []
        for directory in urls {
            let values = try? directory.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
            guard values?.isDirectory == true, values?.isSymbolicLink != true else { continue }
            let libraryID = directory.lastPathComponent
            guard isSafeLibraryID(libraryID), let manifest = readManifest(in: directory) else { continue }
            let imageURL = directory.appendingPathComponent(manifest.image, isDirectory: false)
            guard isSafeImage(manifest.image, at: imageURL) else { continue }
            candidates.append((libraryID, manifest, directory, imageURL))
        }

        let activeLibraryID = chooseActiveLibraryID(from: candidates, active: active)
        return candidates
            .map { candidate in
                ThemeRecord(
                    libraryID: candidate.libraryID,
                    manifest: candidate.manifest,
                    directoryURL: candidate.directory,
                    imageURL: candidate.image,
                    isActive: candidate.libraryID == activeLibraryID
                )
            }
            .sorted(by: compareThemes)
    }

    package func loadActiveTheme() -> ThemeManifest? {
        readManifest(in: stateRoot.appendingPathComponent("theme", isDirectory: true))
    }

    private func readManifest(in directory: URL) -> ThemeManifest? {
        let configURL = directory.appendingPathComponent("theme.json", isDirectory: false)
        guard isRegularFileWithoutFollowingLinks(configURL),
              let attributes = try? FileManager.default.attributesOfItem(atPath: configURL.path),
              let byteCount = attributes[.size] as? NSNumber,
              byteCount.intValue <= 65_536,
              let data = try? Data(contentsOf: configURL),
              let manifest = try? JSONDecoder().decode(ThemeManifest.self, from: data),
              manifest.schemaVersion == 1,
              isSafeText(manifest.id, maximumLength: 80),
              isSafeText(manifest.name, maximumLength: 80),
              isSafeImageName(manifest.image)
        else {
            return nil
        }
        return manifest
    }

    private func isSafeLibraryID(_ id: String) -> Bool {
        guard !id.isEmpty, id.count <= 80 else { return false }
        return id.unicodeScalars.allSatisfy { scalar in
            CharacterSet.alphanumerics.contains(scalar) || scalar == "_" || scalar == "-"
        }
    }

    private func isSafeText(_ value: String, maximumLength: Int) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count <= maximumLength else { return false }
        return !trimmed.unicodeScalars.contains { scalar in
            CharacterSet.controlCharacters.contains(scalar)
        }
    }

    private func isSafeImageName(_ name: String) -> Bool {
        guard !name.isEmpty,
              name == URL(fileURLWithPath: name).lastPathComponent,
              !name.hasPrefix(".")
        else {
            return false
        }
        let extensions = ["png", "jpg", "jpeg", "webp"]
        return extensions.contains(URL(fileURLWithPath: name).pathExtension.lowercased())
    }

    private func isSafeImage(_ name: String, at url: URL) -> Bool {
        guard isSafeImageName(name), isRegularFileWithoutFollowingLinks(url) else { return false }
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
              let bytes = attributes[.size] as? NSNumber
        else {
            return false
        }
        return bytes.intValue > 0 && bytes.intValue <= 16 * 1_024 * 1_024
    }

    private func isRegularFileWithoutFollowingLinks(_ url: URL) -> Bool {
        guard let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey]) else {
            return false
        }
        return values.isRegularFile == true && values.isSymbolicLink != true
    }

    private func chooseActiveLibraryID(
        from candidates: [(libraryID: String, manifest: ThemeManifest, directory: URL, image: URL)],
        active: ThemeManifest?
    ) -> String? {
        guard let active else { return nil }
        let exactMatches = candidates.filter { $0.manifest.id == active.id }
        if !exactMatches.isEmpty {
            return exactMatches.sorted { left, right in
                if left.libraryID == active.id { return true }
                if right.libraryID == active.id { return false }
                return left.libraryID.localizedStandardCompare(right.libraryID) == .orderedAscending
            }.first?.libraryID
        }
        return candidates
            .filter { $0.manifest.name == active.name }
            .sorted { $0.libraryID.localizedStandardCompare($1.libraryID) == .orderedAscending }
            .first?.libraryID
    }

    private func compareThemes(_ left: ThemeRecord, _ right: ThemeRecord) -> Bool {
        if left.isActive != right.isActive { return left.isActive }
        let nameOrder = left.manifest.name.localizedStandardCompare(right.manifest.name)
        if nameOrder != .orderedSame { return nameOrder == .orderedAscending }
        return left.libraryID.localizedStandardCompare(right.libraryID) == .orderedAscending
    }
}
