import Foundation

package enum ManagerSection: String, CaseIterable, Identifiable, Sendable {
    case dashboard
    case library
    case recent

    package var id: String { rawValue }
    package var title: String {
        switch self {
        case .dashboard: "首页"
        case .library: "主题库"
        case .recent: "最近使用"
        }
    }
    package var symbol: String {
        switch self {
        case .dashboard: "house"
        case .library: "rectangle.grid.1x2"
        case .recent: "clock.arrow.circlepath"
        }
    }
}

package enum ThemeFilter: String, CaseIterable, Identifiable, Sendable {
    case all, dark, light, automatic, recent

    package var id: String { rawValue }
    package var title: String {
        switch self {
        case .all: "全部"
        case .dark: "深色"
        case .light: "明亮"
        case .automatic: "自动"
        case .recent: "最近使用"
        }
    }
}

package enum ThemeSort: String, CaseIterable, Identifiable, Sendable {
    case recent, name

    package var id: String { rawValue }
    package var title: String { self == .recent ? "最近使用" : "名称" }
}

package struct ThemeLibraryEmptyStateDecision: Equatable, Sendable {
    package let symbol: String
    package let title: String
    package let message: String

    package static func resolve(
        section: ManagerSection,
        hasInstalledThemes: Bool,
        searchText: String
    ) -> ThemeLibraryEmptyStateDecision {
        let hasActiveSearch = !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        if section == .recent && !hasActiveSearch {
            return ThemeLibraryEmptyStateDecision(
                symbol: "clock.badge.questionmark",
                title: "还没有最近使用的主题",
                message: "应用主题后会出现在这里"
            )
        }
        if hasInstalledThemes {
            return ThemeLibraryEmptyStateDecision(
                symbol: "line.3.horizontal.decrease.circle",
                title: "当前筛选没有匹配主题",
                message: "调整搜索或筛选条件后再试。"
            )
        }
        return ThemeLibraryEmptyStateDecision(
            symbol: "shield.slash",
            title: "没有找到已安装主题",
            message: "导入 .codexskin 主题包以开始使用。"
        )
    }
}

package struct ThemeLibraryQuery: Equatable, Sendable {
    package var searchText: String
    package var filter: ThemeFilter
    package var sort: ThemeSort

    package init(searchText: String, filter: ThemeFilter, sort: ThemeSort) {
        self.searchText = searchText
        self.filter = filter
        self.sort = sort
    }

    package func filtered(themes: [ThemeRecord], recentIDs: [String]) -> [ThemeRecord] {
        let needle = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        var recentIndex: [String: Int] = [:]
        for (index, id) in recentIDs.enumerated() where recentIndex[id] == nil {
            recentIndex[id] = index
        }
        let matches = themes.filter { theme in
            let searchMatches = needle.isEmpty
                || theme.manifest.name.localizedCaseInsensitiveContains(needle)
                || theme.manifest.id.localizedCaseInsensitiveContains(needle)
                || theme.libraryID.localizedCaseInsensitiveContains(needle)
            guard searchMatches else { return false }
            switch filter {
            case .all: return true
            case .dark: return theme.manifest.appearance == "dark"
            case .light: return theme.manifest.appearance == "light"
            case .automatic: return theme.manifest.appearance != "dark" && theme.manifest.appearance != "light"
            case .recent: return recentIndex[theme.libraryID] != nil
            }
        }
        return matches.sorted { left, right in
            if left.isActive != right.isActive { return left.isActive }
            if sort == .recent {
                let leftIndex = recentIndex[left.libraryID] ?? Int.max
                let rightIndex = recentIndex[right.libraryID] ?? Int.max
                if leftIndex != rightIndex { return leftIndex < rightIndex }
            }
            let order = left.manifest.name.localizedStandardCompare(right.manifest.name)
            if order != .orderedSame { return order == .orderedAscending }
            return left.libraryID.localizedStandardCompare(right.libraryID) == .orderedAscending
        }
    }
}
