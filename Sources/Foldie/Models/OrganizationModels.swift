import Foundation
import SwiftUI

enum DisplayMode: String, Codable, CaseIterable, Identifiable, Sendable {
    case list = "list"
    case cylinder = "cylinder"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .list: return "Список"
        case .cylinder: return "Цилиндр"
        }
    }

    var symbolName: String {
        switch self {
        case .list: return "list.bullet.indent"
        case .cylinder: return "cylinder.split.1x2"
        }
    }
}

enum CylinderScope: String, Codable, CaseIterable, Identifiable, Sendable {
    case structured = "structured"
    case allFlat = "allFlat"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .structured: return "С папками"
        case .allFlat: return "Все иконки"
        }
    }
}

enum IconStyle: String, Codable, CaseIterable, Identifiable, Sendable {
    case color = "color"
    case monochrome = "monochrome"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .color: return "Цветные"
        case .monochrome: return "Моно"
        }
    }
}

enum AutoRehideMode: String, Codable, CaseIterable, Identifiable, Sendable {
    case onOutsideClick = "onOutsideClick"
    case after3Seconds = "after3Seconds"
    case after6Seconds = "after6Seconds"
    case manual = "manual"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .onOutsideClick: return "При клике вне меню"
        case .after3Seconds: return "Через 3 секунды"
        case .after6Seconds: return "Через 6 секунд"
        case .manual: return "Вручную"
        }
    }
}

struct FoldieFolder: Identifiable, Codable, Hashable, Sendable {
    var id: UUID = UUID()
    var name: String
    var symbolName: String = "folder.fill"
    var accentHex: String = "#0A84FF"
    var isExpanded: Bool = true
    var children: [FoldieNode] = []

    var accentColor: Color {
        Color(hex: accentHex) ?? .accentColor
    }
}

struct FoldieDivider: Identifiable, Codable, Hashable, Sendable {
    var id: UUID = UUID()
    var label: String = ""
}

enum FoldieNode: Identifiable, Codable, Hashable, Sendable {
    case item(key: String)
    case folder(FoldieFolder)
    case divider(FoldieDivider)

    var id: String {
        switch self {
        case .item(let key): return "item::\(key)"
        case .folder(let folder): return "folder::\(folder.id.uuidString)"
        case .divider(let divider): return "divider::\(divider.id.uuidString)"
        }
    }

    var isFolder: Bool {
        if case .folder = self { return true }
        return false
    }

    var isDivider: Bool {
        if case .divider = self { return true }
        return false
    }

    var itemKey: String? {
        if case .item(let key) = self { return key }
        return nil
    }

    var folderValue: FoldieFolder? {
        if case .folder(let folder) = self { return folder }
        return nil
    }

    var dividerValue: FoldieDivider? {
        if case .divider(let divider) = self { return divider }
        return nil
    }
}

struct FoldiePreferences: Codable, Hashable, Sendable {
    var displayMode: DisplayMode = .list
    var cylinderScope: CylinderScope = .structured
    var iconStyle: IconStyle = .color
    var hideMenuBarIcons: Bool = true
    var showSystemItems: Bool = true
    var showOfflineItems: Bool = false
    var autoRehideMode: AutoRehideMode = .onOutsideClick
    var statusIconSymbol: String = "folder.fill"
    var launchAtLogin: Bool = false
    var hasCompletedOnboarding: Bool = false
    var dismissedOnboardingTip: Bool = false
    var dismissedPermissionBanner: Bool = false

    enum CodingKeys: String, CodingKey {
        case displayMode, cylinderScope, iconStyle, hideMenuBarIcons, showSystemItems,
             showOfflineItems, autoRehideMode, statusIconSymbol, launchAtLogin,
             hasCompletedOnboarding, dismissedOnboardingTip, dismissedPermissionBanner
    }

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        displayMode = try c.decodeIfPresent(DisplayMode.self, forKey: .displayMode) ?? .list
        cylinderScope = try c.decodeIfPresent(CylinderScope.self, forKey: .cylinderScope) ?? .structured
        iconStyle = try c.decodeIfPresent(IconStyle.self, forKey: .iconStyle) ?? .color
        hideMenuBarIcons = try c.decodeIfPresent(Bool.self, forKey: .hideMenuBarIcons) ?? true
        showSystemItems = try c.decodeIfPresent(Bool.self, forKey: .showSystemItems) ?? true
        showOfflineItems = try c.decodeIfPresent(Bool.self, forKey: .showOfflineItems) ?? false
        autoRehideMode = try c.decodeIfPresent(AutoRehideMode.self, forKey: .autoRehideMode) ?? .onOutsideClick
        statusIconSymbol = try c.decodeIfPresent(String.self, forKey: .statusIconSymbol) ?? "folder.fill"
        launchAtLogin = try c.decodeIfPresent(Bool.self, forKey: .launchAtLogin) ?? false
        hasCompletedOnboarding = try c.decodeIfPresent(Bool.self, forKey: .hasCompletedOnboarding) ?? false
        dismissedOnboardingTip = try c.decodeIfPresent(Bool.self, forKey: .dismissedOnboardingTip) ?? false
        dismissedPermissionBanner = try c.decodeIfPresent(Bool.self, forKey: .dismissedPermissionBanner) ?? false
    }
}

struct FoldieConfig: Codable, Sendable {
    var version: Int = 1
    var rootNodes: [FoldieNode] = []
    var itemMetadata: [String: StoredItemMeta] = [:]
    var hiddenItemKeys: Set<String> = []
    var preferences: FoldiePreferences = FoldiePreferences()

    enum CodingKeys: String, CodingKey {
        case version, rootNodes, itemMetadata, hiddenItemKeys, preferences
    }

    init(
        version: Int = 1,
        rootNodes: [FoldieNode] = [],
        itemMetadata: [String: StoredItemMeta] = [:],
        hiddenItemKeys: Set<String> = [],
        preferences: FoldiePreferences = FoldiePreferences()
    ) {
        self.version = version
        self.rootNodes = rootNodes
        self.itemMetadata = itemMetadata
        self.hiddenItemKeys = hiddenItemKeys
        self.preferences = preferences
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.version = try container.decodeIfPresent(Int.self, forKey: .version) ?? 1
        self.rootNodes = try container.decodeIfPresent([FoldieNode].self, forKey: .rootNodes) ?? []
        self.itemMetadata = try container.decodeIfPresent([String: StoredItemMeta].self, forKey: .itemMetadata) ?? [:]
        self.hiddenItemKeys = try container.decodeIfPresent(Set<String>.self, forKey: .hiddenItemKeys) ?? []
        self.preferences = try container.decodeIfPresent(FoldiePreferences.self, forKey: .preferences) ?? FoldiePreferences()
    }
}

extension Color {
    init?(hex: String) {
        var cleaned = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned.hasPrefix("#") {
            cleaned.removeFirst()
        }
        guard cleaned.count == 6, let value = UInt64(cleaned, radix: 16) else {
            return nil
        }
        let r = Double((value & 0xFF0000) >> 16) / 255.0
        let g = Double((value & 0x00FF00) >> 8) / 255.0
        let b = Double(value & 0x0000FF) / 255.0
        self.init(.sRGB, red: r, green: g, blue: b, opacity: 1.0)
    }
}

enum FoldiePalette {
    static let folderColors: [(name: String, hex: String)] = [
        ("Синий", "#0A84FF"),
        ("Индиго", "#5E5CE6"),
        ("Фиолетовый", "#BF5AF2"),
        ("Розовый", "#FF375F"),
        ("Оранжевый", "#FF9F0A"),
        ("Жёлтый", "#FFD60A"),
        ("Зелёный", "#30D158"),
        ("Бирюзовый", "#40C8E0"),
        ("Серый", "#8E8E93")
    ]

    static let folderSymbols: [String] = [
        "folder.fill",
        "star.fill",
        "briefcase.fill",
        "wrench.and.screwdriver.fill",
        "network",
        "message.fill",
        "music.note",
        "bolt.fill",
        "lock.shield.fill",
        "cpu.fill",
        "cloud.fill",
        "gamecontroller.fill",
        "sparkles",
        "tray.full.fill",
        "terminal.fill",
        "heart.fill"
    ]

    static let statusBarSymbols: [(name: String, symbol: String)] = [
        ("Папка", "folder.fill"),
        ("Папка со стеком", "folder.badge.gearshape"),
        ("Лоток", "tray.full.fill"),
        ("Сетка", "square.grid.2x2.fill"),
        ("Цилиндр", "cylinder.split.1x2.fill"),
        ("Слои", "square.3.layers.3d")
    ]
}
