import CodexSkinManagerCore

enum ThemeLibraryQueryTests {
    static func run() throws {
        try searchesNameAndIDCaseInsensitively()
        try filtersAppearanceAndRecents()
        try sortsByNameAndRecentOrder()
        try deduplicatesRecentIDsBeforeIndexing()
        try resolvesLibraryEmptyState()
        try resolvesRecentEmptyState()
        try resolvesFilteredEmptyState()
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

    private static func resolvesLibraryEmptyState() throws {
        let state = ThemeLibraryEmptyStateDecision.resolve(
            section: .library,
            hasInstalledThemes: false,
            searchText: ""
        )
        try expect(state.symbol == "shield.slash", "library-empty symbol mismatch")
        try expect(state.title == "没有找到已安装主题", "library-empty title mismatch")
        try expect(state.message == "导入 .codexskin 主题包以开始使用。", "library-empty message mismatch")
    }

    private static func deduplicatesRecentIDsBeforeIndexing() throws {
        let first = makeThemeRecord(id: "first", name: "First")
        let second = makeThemeRecord(id: "second", name: "Second")
        let result = ThemeLibraryQuery(searchText: "", filter: .recent, sort: .recent)
            .filtered(themes: [first, second], recentIDs: ["second", "second", "first"])
        try expect(result.map(\.libraryID) == ["second", "first"], "duplicate recent IDs must retain first-seen ordering without trapping")
    }

    private static func resolvesRecentEmptyState() throws {
        let state = ThemeLibraryEmptyStateDecision.resolve(
            section: .recent,
            hasInstalledThemes: true,
            searchText: "  "
        )
        try expect(state.symbol == "clock.badge.questionmark", "recent-empty symbol mismatch")
        try expect(state.title == "还没有最近使用的主题", "recent-empty title mismatch")
        try expect(state.message == "应用主题后会出现在这里", "recent-empty message mismatch")
    }

    private static func resolvesFilteredEmptyState() throws {
        let libraryState = ThemeLibraryEmptyStateDecision.resolve(
            section: .library,
            hasInstalledThemes: true,
            searchText: ""
        )
        let recentSearchState = ThemeLibraryEmptyStateDecision.resolve(
            section: .recent,
            hasInstalledThemes: true,
            searchText: "missing"
        )
        try expect(libraryState == recentSearchState, "recent search must use the filtered-empty state")
        try expect(libraryState.symbol == "line.3.horizontal.decrease.circle", "filtered-empty symbol mismatch")
        try expect(libraryState.title == "当前筛选没有匹配主题", "filtered-empty title mismatch")
        try expect(libraryState.message == "调整搜索或筛选条件后再试。", "filtered-empty message mismatch")
    }
}
