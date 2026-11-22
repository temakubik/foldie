import AppKit
import CoreGraphics
import Foundation

/// Represents a discovered menu bar app or system status item.
struct MenuBarItem: Identifiable, Hashable, @unchecked Sendable {
    /// Stable persistent key used to track this item inside folders and ordering.
    let key: String
    var id: String { key }

    let windowID: CGWindowID
    let pid: pid_t
    let ownerName: String
    let title: String
    let bundleIdentifier: String?
    let frame: CGRect
    let isOnscreen: Bool
    let isSystemItem: Bool

    /// Captured live screenshot of the status bar item (optional, for system items when Screen Recording is active).
    var capturedImage: NSImage?
    /// Running application icon (always crisp and immediately recognizable for real apps).
    var appIcon: NSImage?

    var displayName: String {
        if let mapped = Self.systemTitleDisplayMap[title], !mapped.isEmpty {
            return mapped
        }
        if !title.isEmpty && !title.hasPrefix("Item-") && title.lowercased() != ownerName.lowercased() {
            if isSystemItem {
                return title
            }
            return "\(ownerName) — \(title)"
        }
        if let mappedOwner = Self.systemOwnerDisplayMap[ownerName] {
            return mappedOwner
        }
        return ownerName.isEmpty ? "Приложение #\(pid)" : ownerName
    }

    var subtitle: String {
        if isSystemItem {
            return "Система macOS"
        }
        if !title.isEmpty && !title.hasPrefix("Item-") && title.lowercased() != ownerName.lowercased() {
            return ownerName
        }
        return "Панель меню"
    }

    var fallbackSymbolName: String {
        let lowerTitle = title.lowercased()
        let lowerOwner = ownerName.lowercased()

        if lowerTitle.contains("wifi") || lowerTitle.contains("wi-fi") { return "wifi" }
        if lowerTitle.contains("bluetooth") { return "dot.radiowaves.left.and.right" }
        if lowerTitle.contains("battery") || lowerTitle.contains("аккумулятор") { return "battery.100" }
        if lowerTitle.contains("clock") || lowerTitle.contains("часы") { return "clock" }
        if lowerTitle.contains("sound") || lowerTitle.contains("audio") || lowerTitle.contains("звук") { return "speaker.wave.2.fill" }
        if lowerTitle.contains("bentobox") || lowerOwner.contains("controlcenter") || lowerOwner.contains("пункт управления") { return "switch.2" }
        if lowerTitle.contains("focus") || lowerTitle.contains("фокус") { return "moon.fill" }
        if lowerTitle.contains("airdrop") { return "airplayaudio" }
        if lowerTitle.contains("screenmirroring") || lowerTitle.contains("display") || lowerTitle.contains("повтор") { return "rectangle.on.rectangle" }
        if lowerTitle.contains("nowplaying") || lowerTitle.contains("исполняется") { return "play.circle.fill" }
        if lowerTitle.contains("keyboard") || lowerOwner.contains("textinput") || lowerTitle.contains("раскладка") { return "keyboard" }
        if lowerOwner.contains("spotlight") { return "magnifyingglass" }
        if lowerOwner.contains("siri") { return "sparkles" }
        if lowerOwner.contains("timemachine") { return "clock.arrow.circlepath" }
        if lowerTitle.contains("vpn") || lowerOwner.contains("vpn") { return "lock.shield" }
        return "app.badge"
    }

    static func == (lhs: MenuBarItem, rhs: MenuBarItem) -> Bool {
        lhs.key == rhs.key &&
        lhs.windowID == rhs.windowID &&
        lhs.pid == rhs.pid &&
        lhs.frame == rhs.frame &&
        lhs.isOnscreen == rhs.isOnscreen &&
        (lhs.capturedImage != nil) == (rhs.capturedImage != nil)
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(key)
        hasher.combine(windowID)
        hasher.combine(pid)
    }

    private static let systemTitleDisplayMap: [String: String] = [
        "WiFi": "Wi-Fi",
        "Bluetooth": "Bluetooth",
        "Battery": "Аккумулятор",
        "Clock": "Часы",
        "Sound": "Звук",
        "BentoBox": "Пункт управления",
        "BentoBox-0": "Пункт управления",
        "FocusModes": "Фокусирование",
        "ScreenMirroring": "Повтор экрана",
        "Display": "Дисплей",
        "NowPlaying": "Исполняется",
        "AirDrop": "AirDrop",
        "AudioVideoModule": "Звук и видео",
        "com.apple.menuextra.vpn": "VPN",
        "AccessibilityShortcuts": "Универсальный доступ",
        "KeyboardBrightness": "Подсветка клавиатуры",
        "UserSwitcher": "Переключатель пользователей",
        "Hearing": "Слух",
        "Weather": "Погода"
    ]

    private static let systemOwnerDisplayMap: [String: String] = [
        "ControlCenter": "Пункт управления",
        "SystemUIServer": "Системное меню",
        "Spotlight": "Spotlight",
        "TextInputMenuAgent": "Раскладка клавиатуры",
        "Siri": "Siri",
        "NotificationCenter": "Центр уведомлений",
        "FigmaAgent": "Figma",
        "logioptionsplus_agent": "Logi Options+"
    ]
}

/// Metadata remembered for an item even if its app is not currently running.
struct StoredItemMeta: Codable, Hashable, Sendable {
    var key: String
    var displayName: String
    var ownerName: String
    var bundleIdentifier: String?
    var bundlePath: String?
    var customAlias: String?
}
