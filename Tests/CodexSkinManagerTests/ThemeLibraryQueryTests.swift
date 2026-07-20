import CodexSkinManagerCore

enum ThemeLibraryQueryTests {
    static func run() throws {
        try searchesNameAndIDCaseInsensitively()
        try filtersAppearanceAndRecents()
        try sortsByNameAndRecentOrder()
        print("PASS: ThemeLibraryQueryTests")
    }

    private static func searchesNameAndIDCaseInsensitively() throws {
        let themes = [
            makeThemeRecord(id: "frost-dragon", name: "寒龙子", appearance: "dark"),
            makeThemeRecord(id: "jade-palace", name: "碧落金阙", appearance: "light"),
        ]
        let byName = ThemeLibraryQuery(searchText: "寒龙", filter: .all, sort: .name)
            .filtered(themes: themes, recentIDs: [])
        let byID = ThemeLibraryQuery(searchText: "JADE", filter: .all, sort: .name)
            .filtered(themes: themes, recentIDs: [])
        try expect(byName.map(\.libraryID) == ["frost-dragon"], "name search mismatch")
        try expect(byID.map(\.libraryID) == ["jade-palace"], "id search mismatch")
    }

    private static func filtersAppearanceAndRecents() throws {
        let themes = [
            makeThemeRecord(id: "dark", name: "Dark", appearance: "dark"),
            makeThemeRecord(id: "light", name: "Light", appearance: "light"),
            makeThemeRecord(id: "auto", name: "Auto", appearance: nil),
        ]
        let light = ThemeLibraryQuery(searchText: "", filter: .light, sort: .name)
            .filtered(themes: themes, recentIDs: ["auto", "dark"])
        let recent = ThemeLibraryQuery(searchText: "", filter: .recent, sort: .recent)
            .filtered(themes: themes, recentIDs: ["auto", "dark"])
        try expect(light.map(\.libraryID) == ["light"], "light filter mismatch")
        try expect(recent.map(\.libraryID) == ["auto", "dark"], "recent filter mismatch")
    }

    private static func sortsByNameAndRecentOrder() throws {
        let themes = [
            makeThemeRecord(id: "b", name: "Beta", appearance: "dark"),
            makeThemeRecord(id: "a", name: "Alpha", appearance: "dark"),
        ]
        let named = ThemeLibraryQuery(searchText: "", filter: .all, sort: .name)
            .filtered(themes: themes, recentIDs: ["b", "a"])
        let recent = ThemeLibraryQuery(searchText: "", filter: .all, sort: .recent)
            .filtered(themes: themes, recentIDs: ["b", "a"])
        try expect(named.map(\.libraryID) == ["a", "b"], "name sort mismatch")
        try expect(recent.map(\.libraryID) == ["b", "a"], "recent sort mismatch")
    }
}
