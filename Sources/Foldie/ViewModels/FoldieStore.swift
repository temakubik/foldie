import AppKit
import Combine
import Foundation
import ServiceManagement
import SwiftUI

@MainActor
final class FoldieStore: ObservableObject {
    @Published var config: FoldieConfig
    @Published private(set) var liveItemsByKey: [String: MenuBarItem] = [:]
    @Published var searchQuery: String = ""
    @Published var cylinderFolderPath: [UUID] = []
    /// Active folder selected via horizontal swipe on the main Foldie icon (`nil` = all / root view).
    @Published var swipedFolderID: UUID? = nil
    /// Folder currently being displayed by the floating popover (either from hovering a pinned folder icon, or from `swipedFolderID`).
    @Published var activePopupFolderID: UUID? = nil
    @Published var isShowingSettings: Bool = false
    @Published var isRefreshing: Bool = false
    @Published var isAutoCollecting: Bool = false
    @Published var autoCollectMessage: String?

    /// In-memory cache of resolved app icons (works for Electron apps and offline apps like Ollama, Notion, Trae).
    private var resolvedIconCache: [String: NSImage] = [:]

    // Editor overlay states (inline inside the floating panel so focus never glitches)
    @Published var folderEditorState: FolderEditorState?
    @Published var dividerEditorState: DividerEditorState?

    let permissions: PermissionService
    let hider: MenuBarHiderService
    let discovery: MenuBarDiscoveryService
    let activator: MenuBarActivationService
    let sounds: SoundFeedbackService
    private let persistence: PersistenceStore

    var onRequestClosePanel: (() -> Void)?
    var onRequestShowOnboarding: (() -> Void)?
    var onRequestOpenOrganizer: (() -> Void)?

    private var refreshTimer: Timer?
    private var cancellables = Set<AnyCancellable>()

    struct FolderEditorState: Identifiable {
        let id = UUID()
        var existingFolderID: UUID?
        var parentFolderID: UUID?
        var name: String
        var symbolName: String
        var accentHex: String
        var showInMenuBar: Bool = false
    }

    struct DividerEditorState: Identifiable {
        let id = UUID()
        var existingDividerID: UUID?
        var parentFolderID: UUID?
        var label: String
    }

    init() {
        let persistence = PersistenceStore()
        self.persistence = persistence
        self.config = persistence.load()
        self.permissions = PermissionService()
        self.hider = MenuBarHiderService()
        self.discovery = MenuBarDiscoveryService()
        self.activator = MenuBarActivationService(
            discoveryService: self.discovery,
            hiderService: self.hider
        )
        self.sounds = SoundFeedbackService()
        self.sounds.isEnabled = self.config.preferences.enableSounds

        // Forward nested observable changes so SwiftUI updates live
        permissions.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)
        hider.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)
    }

    func start() {
        promoteAllFoldersToRoot()
        let shouldHideInitially = config.preferences.hasCompletedOnboarding
            ? config.preferences.hideMenuBarIcons
            : false
        hider.setup(
            symbolName: config.preferences.statusIconSymbol,
            hideIcons: shouldHideInitially
        )
        refreshItems(captureThumbnails: true)

        // Periodically scan for newly launched or quit menu bar apps
        refreshTimer?.invalidate()
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 4.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.refreshItems(captureThumbnails: false)
            }
        }
    }

    func completeOnboarding() {
        config.preferences.hasCompletedOnboarding = true
        hider.setDesiredHideIcons(config.preferences.hideMenuBarIcons)
        saveConfig()
    }

    func autoCollectAllIcons() {
        guard !isAutoCollecting else { return }
        isAutoCollecting = true
        autoCollectMessage = "Собираем иконки в папку Foldie..."
        Task { @MainActor [weak self] in
            guard let self else { return }
            let result = await self.hider.autoCollectAllIcons()
            self.config.preferences.hideMenuBarIcons = self.hider.isCurrentlyHiding
            self.autoCollectMessage = result.message
            self.isAutoCollecting = false
            self.refreshItems(captureThumbnails: true)
            self.saveConfig()
        }
    }

    func setCustomAlias(forItemKey key: String, alias: String) {
        let trimmed = alias.trimmingCharacters(in: .whitespacesAndNewlines)
        var meta = config.itemMetadata[key] ?? StoredItemMeta(
            key: key,
            displayName: displayName(forItemKey: key),
            ownerName: liveItemsByKey[key]?.ownerName ?? "",
            bundleIdentifier: liveItemsByKey[key]?.bundleIdentifier,
            customAlias: nil
        )
        meta.customAlias = trimmed.isEmpty ? nil : trimmed
        config.itemMetadata[key] = meta
        saveConfig()
    }

    func parentFolderID(ofNodeID nodeID: String) -> UUID? {
        findParentFolderID(ofNodeID: nodeID, in: config.rootNodes, currentFolderID: nil)
    }

    func recheckPermissions() {
        discovery.resetCaptureBackoff()
        permissions.refresh()
        refreshItems(captureThumbnails: false)
    }

    func refreshItems(captureThumbnails: Bool = false, forceThumbnailRefresh: Bool = false) {
        permissions.refresh()
        hider.updateFolderVisibilityStatus()
        isRefreshing = true

        let discovered = discovery.discoverItems(excludingWindowIDs: hider.ownStatusWindowIDs)
        let runningAppsByPID = Dictionary(
            NSWorkspace.shared.runningApplications.map { ($0.processIdentifier, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        var newMap: [String: MenuBarItem] = [:]
        for item in discovered {
            newMap[item.key] = item
            let bundlePath = runningAppsByPID[item.pid]?.bundleURL?.path
            var meta = config.itemMetadata[item.key] ?? StoredItemMeta(
                key: item.key,
                displayName: item.displayName,
                ownerName: item.ownerName,
                bundleIdentifier: item.bundleIdentifier,
                bundlePath: bundlePath,
                customAlias: nil
            )
            meta.displayName = item.displayName
            meta.ownerName = item.ownerName
            meta.bundleIdentifier = item.bundleIdentifier
            if let bundlePath, !bundlePath.isEmpty {
                meta.bundlePath = bundlePath
            }
            config.itemMetadata[item.key] = meta
            if let icon = item.appIcon, !item.isSystemItem {
                resolvedIconCache[item.key] = icon
            }
        }

        liveItemsByKey = newMap

        var didMutate = false

        // Clean out any legacy Foldie self-items or anonymous ControlCenter slot-* ghosts that aren't live anymore
        let pruned = pruneObsoleteNodes(in: &config.rootNodes, liveKeys: Set(newMap.keys))
        if pruned {
            didMutate = true
        }

        // Ensure every newly discovered item exists somewhere in the node tree
        let existingKeys = collectAllItemKeys(in: config.rootNodes)
        for item in discovered {
            if !existingKeys.contains(item.key) {
                config.rootNodes.append(.item(key: item.key))
                didMutate = true
            }
        }

        updateStatusBarBadgeForCurrentFolder()

        if didMutate {
            saveConfig()
        }

        if captureThumbnails && permissions.isScreenCaptureKitSafeToCall {
            Task { @MainActor [weak self] in
                guard let self else { return }
                let captured = await self.discovery.captureThumbnails(
                    for: discovered,
                    canUseScreenCaptureKit: self.permissions.isScreenCaptureKitSafeToCall,
                    force: forceThumbnailRefresh
                )
                var updated = self.liveItemsByKey
                for (key, img) in captured {
                    if var existing = updated[key] {
                        existing.capturedImage = img
                        updated[key] = existing
                    }
                }
                self.liveItemsByKey = updated
                self.isRefreshing = false
            }
        } else {
            isRefreshing = false
        }
    }

    var visibleLiveItemCount: Int {
        liveItemsByKey.values.filter {
            isItemAllowedByPreferences($0) && !config.hiddenItemKeys.contains($0.key)
        }.count
    }

    func isItemEnabledInFoldie(key: String) -> Bool {
        !config.hiddenItemKeys.contains(key)
    }

    func setItemEnabledInFoldie(key: String, enabled: Bool) {
        if enabled {
            config.hiddenItemKeys.remove(key)
        } else {
            config.hiddenItemKeys.insert(key)
        }
        hider.updateBadgeCount(visibleLiveItemCount)
        saveConfig()
    }

    func isItemAllowedByPreferences(_ item: MenuBarItem) -> Bool {
        if !config.preferences.showSystemItems && item.isSystemItem {
            return false
        }
        return true
    }

    func isItemVisibleInUI(key: String) -> Bool {
        if config.hiddenItemKeys.contains(key) {
            return false
        }
        if let live = liveItemsByKey[key] {
            return isItemAllowedByPreferences(live)
        }
        return config.preferences.showOfflineItems
    }

    /// Used in the Settings/Organizer window so the user can see and re-enable toggled-off items.
    func isItemVisibleInOrganizer(key: String) -> Bool {
        if let live = liveItemsByKey[key] {
            return isItemAllowedByPreferences(live)
        }
        return config.preferences.showOfflineItems
    }

    func displayName(forItemKey key: String) -> String {
        if let alias = config.itemMetadata[key]?.customAlias, !alias.isEmpty {
            return alias
        }
        if let live = liveItemsByKey[key] {
            return live.displayName
        }
        return config.itemMetadata[key]?.displayName ?? key
    }

    func subtitle(forItemKey key: String) -> String {
        if let live = liveItemsByKey[key] {
            return live.subtitle
        }
        return "Не запущено"
    }

    // MARK: - Activation

    func activateItem(key: String, rightClick: Bool = false) {
        sounds.playPop()
        if let item = liveItemsByKey[key] {
            onRequestClosePanel?()
            activator.activate(
                item: item,
                rightClick: rightClick,
                rehideMode: config.preferences.autoRehideMode
            )
            return
        }

        // Fallback for offline apps: launch the application bundle cleanly so the button always works
        if let appURL = resolveApplicationURL(forItemKey: key) {
            onRequestClosePanel?()
            let config = NSWorkspace.OpenConfiguration()
            config.activates = true
            NSWorkspace.shared.openApplication(at: appURL, configuration: config)
        }
    }

    func resolveApplicationURL(forItemKey key: String) -> URL? {
        let meta = config.itemMetadata[key]
        if let path = meta?.bundlePath, FileManager.default.fileExists(atPath: path) {
            return URL(fileURLWithPath: path)
        }
        let candidateBID: String? = meta?.bundleIdentifier
            ?? (key.hasPrefix("app::") ? String(key.dropFirst("app::".count)).components(separatedBy: "#").first : nil)
        if let bid = candidateBID, !bid.isEmpty {
            if bid == "com.figma.agent",
               let figmaURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.figma.Desktop") {
                return figmaURL
            }
            if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bid) {
                return url
            }
        }
        return nil
    }

    // MARK: - Preferences

    func setIconStyle(_ style: IconStyle) {
        config.preferences.iconStyle = style
        saveConfig()
        updateStatusBarBadgeForCurrentFolder()
    }

    func setCapsuleShape(_ shape: CapsuleShapeStyle) {
        config.preferences.capsuleShape = shape
        saveConfig()
        updateStatusBarBadgeForCurrentFolder()
    }

    func setStatusBarLabelMode(_ mode: StatusBarLabelMode) {
        config.preferences.statusBarLabelMode = mode
        saveConfig()
        updateStatusBarBadgeForCurrentFolder()
    }

    func setEnableMenuBarSwipe(_ enabled: Bool) {
        config.preferences.enableMenuBarSwipe = enabled
        saveConfig()
        updateStatusBarBadgeForCurrentFolder()
    }

    func setEnableSounds(_ enabled: Bool) {
        config.preferences.enableSounds = enabled
        sounds.isEnabled = enabled
        if enabled {
            sounds.playPop()
        }
        saveConfig()
    }

    /// Resolves the real app icon for any item (live OR offline, including Electron apps like Ollama, Notion, Trae).
    func resolvedAppIcon(forItemKey key: String) -> NSImage? {
        if let cached = resolvedIconCache[key] {
            return cached
        }
        if let live = liveItemsByKey[key] {
            if live.isSystemItem { return nil }
            if let icon = live.appIcon {
                resolvedIconCache[key] = icon
                return icon
            }
        }

        let meta = config.itemMetadata[key]

        // 1. Saved bundle path on disk
        if let path = meta?.bundlePath, FileManager.default.fileExists(atPath: path) {
            let icon = NSWorkspace.shared.icon(forFile: path)
            resolvedIconCache[key] = icon
            return icon
        }

        // 2. Lookup by Bundle Identifier via LaunchServices
        let candidateBID: String? = meta?.bundleIdentifier
            ?? (key.hasPrefix("app::") ? String(key.dropFirst("app::".count)).components(separatedBy: "#").first : nil)

        if let bid = candidateBID, !bid.isEmpty, !bid.hasPrefix("com.apple.") {
            if bid == "com.figma.agent",
               let figmaURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.figma.Desktop") {
                let icon = NSWorkspace.shared.icon(forFile: figmaURL.path)
                resolvedIconCache[key] = icon
                return icon
            }
            if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bid) {
                let icon = NSWorkspace.shared.icon(forFile: url.path)
                resolvedIconCache[key] = icon
                return icon
            }
        }

        // 3. Direct case-insensitive scan of /Applications and ~/Applications by app display name
        let targetName = (meta?.ownerName ?? meta?.displayName ?? "").lowercased()
        if !targetName.isEmpty {
            let searchDirs = [
                URL(fileURLWithPath: "/Applications", isDirectory: true),
                FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications", isDirectory: true)
            ]
            for dir in searchDirs {
                if let entries = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) {
                    for entry in entries where entry.pathExtension == "app" {
                        let base = entry.deletingPathExtension().lastPathComponent.lowercased()
                        if base == targetName || base.contains(targetName) || targetName.contains(base) {
                            let icon = NSWorkspace.shared.icon(forFile: entry.path)
                            resolvedIconCache[key] = icon
                            return icon
                        }
                    }
                }
            }
        }

        return nil
    }

    /// Cycles active folder when swiping left/right on Foldie's menu bar icon (or horizontally in the menu).
    func cycleSwipedFolder(step: Int) {
        let folders = topLevelFolders()
        guard !folders.isEmpty else { return }

        // Slots: [nil (Все), folder1, folder2, ...]
        let slots: [UUID?] = [nil] + folders.map { Optional($0.id) }
        let currentIdx = slots.firstIndex(where: { $0 == swipedFolderID }) ?? 0
        let nextIdx = (currentIdx + step + slots.count) % slots.count
        sounds.playSwipe(forward: step > 0)
        selectSwipedFolder(slots[nextIdx])
    }

    func selectSwipedFolder(_ folderID: UUID?) {
        swipedFolderID = folderID
        activePopupFolderID = folderID
        cylinderFolderPath = folderID.map { [$0] } ?? []
        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
        updateStatusBarBadgeForCurrentFolder()
    }

    func setActivePopupFolder(_ folderID: UUID?) {
        activePopupFolderID = folderID
        cylinderFolderPath = folderID.map { [$0] } ?? []
    }

    func toggleFolderPinnedInMenuBar(id: UUID) {
        _ = mutateFolder(id: id, in: &config.rootNodes) { folder in
            folder.showInMenuBar.toggle()
        }
        saveConfig()
        updateStatusBarBadgeForCurrentFolder()
    }

    func topLevelFolders() -> [FoldieFolder] {
        config.rootNodes.compactMap { $0.folderValue }
    }

    /// Reorders top-level main folders (controls left/right swipe sequence in the menu bar).
    func moveMainFolder(id: UUID, up: Bool) {
        let folderIndices = config.rootNodes.indices.filter { config.rootNodes[$0].isFolder }
        guard let posInFolders = folderIndices.firstIndex(where: { config.rootNodes[$0].folderValue?.id == id }) else {
            return
        }
        let targetPos = up ? posInFolders - 1 : posInFolders + 1
        guard folderIndices.indices.contains(targetPos) else { return }
        config.rootNodes.swapAt(folderIndices[posInFolders], folderIndices[targetPos])
        saveConfig()
    }

    /// Promotes any nested subfolders to top-level main folders so every folder participates in menu bar swiping.
    func promoteAllFoldersToRoot() {
        var promoted: [FoldieFolder] = []
        func extractNested(from children: inout [FoldieNode]) {
            var remaining: [FoldieNode] = []
            for child in children {
                if case .folder(var sub) = child {
                    extractNested(from: &sub.children)
                    promoted.append(sub)
                } else {
                    remaining.append(child)
                }
            }
            children = remaining
        }
        for idx in config.rootNodes.indices {
            if case .folder(var folder) = config.rootNodes[idx] {
                extractNested(from: &folder.children)
                config.rootNodes[idx] = .folder(folder)
            }
        }
        if !promoted.isEmpty {
            config.rootNodes.insert(contentsOf: promoted.map { .folder($0) }, at: 0)
            saveConfig()
        }
    }

    /// One-click smart auto-sort: scans all menu bar apps and groups them into clean top-level main folders by category.
    func autoSortAppsIntoCategories() {
        refreshItems(captureThumbnails: false)

        // Collect all unique item keys currently tracked (respecting current visibility preferences)
        var allKeys: [String] = []
        var seen = Set<String>()
        func collect(_ nodes: [FoldieNode]) {
            for node in nodes {
                switch node {
                case .item(let key):
                    if !seen.contains(key) && isItemVisibleInOrganizer(key: key) {
                        seen.insert(key)
                        allKeys.append(key)
                    }
                case .folder(let folder):
                    collect(folder.children)
                case .divider:
                    break
                }
            }
        }
        collect(config.rootNodes)
        for key in liveItemsByKey.keys where !seen.contains(key) && isItemVisibleInOrganizer(key: key) {
            seen.insert(key)
            allKeys.append(key)
        }

        struct CategorySpec {
            let id: String
            let name: String
            let symbol: String
            let hex: String
        }

        let categories: [CategorySpec] = [
            CategorySpec(id: "ai_dev", name: "ИИ и разработка", symbol: "sparkles", hex: "#BF5AF2"),
            CategorySpec(id: "vpn_net", name: "Сеть и VPN", symbol: "network", hex: "#FF375F"),
            CategorySpec(id: "comm", name: "Связь", symbol: "message.fill", hex: "#30D158"),
            CategorySpec(id: "prod", name: "Продуктивность", symbol: "briefcase.fill", hex: "#0A84FF"),
            CategorySpec(id: "utils", name: "Утилиты", symbol: "wrench.and.screwdriver.fill", hex: "#FF9F0A"),
            CategorySpec(id: "system", name: "Система", symbol: "cpu.fill", hex: "#8E8E93"),
            CategorySpec(id: "other", name: "Прочее", symbol: "folder.fill", hex: "#40C8E0")
        ]

        var buckets: [String: [String]] = [:]
        for key in allKeys {
            let catID = classifyItemCategory(forKey: key)
            buckets[catID, default: []].append(key)
        }

        var newRootNodes: [FoldieNode] = []
        for spec in categories {
            guard let keys = buckets[spec.id], !keys.isEmpty else { continue }
            let sortedKeys = keys.sorted {
                displayName(forItemKey: $0).localizedCaseInsensitiveCompare(displayName(forItemKey: $1)) == .orderedAscending
            }
            let folder = FoldieFolder(
                name: spec.name,
                symbolName: spec.symbol,
                accentHex: spec.hex,
                isExpanded: false,
                children: sortedKeys.map { .item(key: $0) }
            )
            newRootNodes.append(.folder(folder))
        }

        config.rootNodes = newRootNodes
        swipedFolderID = nil
        cylinderFolderPath = []
        saveConfig()
        updateStatusBarBadgeForCurrentFolder()
    }

    private func classifyItemCategory(forKey key: String) -> String {
        let live = liveItemsByKey[key]
        let meta = config.itemMetadata[key]
        if live?.isSystemItem == true || key.hasPrefix("com.apple.") {
            let lower = "\(key) \(displayName(forItemKey: key))".lowercased()
            if lower.contains("vpn") || lower.contains("wifi") || lower.contains("wi-fi") {
                return "vpn_net"
            }
            return "system"
        }

        let name = displayName(forItemKey: key).lowercased()
        let bid = (live?.bundleIdentifier ?? meta?.bundleIdentifier ?? key).lowercased()
        let combined = "\(name) \(bid)"

        // 1. VPN & Networking
        let vpnKeywords = ["vpn", "adguard", "amnezia", "wireguard", "tailscale", "warp", "cloudflare", "proton", "mullvad", "nord", "proxyman", "snitch", "network"]
        if vpnKeywords.contains(where: { combined.contains($0) }) { return "vpn_net" }

        // 2. AI, Dev & Design
        let aiDevKeywords = ["chatgpt", "openai", "codex", "claude", "ollama", "cursor", "antigravity", "trae", "figma", "xcode", "vscode", "docker", "orbstack", "github", "gitlab", "iterm", "warp", "terminal", "jetbrains", "postman", "insomnia", "linear"]
        if aiDevKeywords.contains(where: { combined.contains($0) }) { return "ai_dev" }

        // 3. Communication
        let commKeywords = ["telegram", "slack", "discord", "zoom", "whatsapp", "teams", "skype", "viber", "mail", "spark", "signal", "messenger", "meet"]
        if commKeywords.contains(where: { combined.contains($0) }) { return "comm" }

        // 4. Productivity & Browsers
        let prodKeywords = ["notion", "calendar", "cron", "obsidian", "todoist", "things", "fantastical", "trello", "jira", "chrome", "safari", "arc", "firefox", "brave", "notes", "bear", "craft", "raycast", "alfred"]
        if prodKeywords.contains(where: { combined.contains($0) }) { return "prod" }

        // 5. Utilities, Input, Displays, Cloud sync
        let utilKeywords = ["mos", "bettermouse", "logi", "displaylink", "dropzone", "hidden", "minimalbar", "bartender", "ice", "mole", "pearcleaner", "cleanmymac", "onedrive", "dropbox", "drive", "icloud", "rectangle", "magnet", "resurf", "type", "gigatype", "cap", "cleanshot", "notch", "caramba", "switcher", "bionic", "keyboard", "mouse", "sound", "monitor", "stats", "istat"]
        if utilKeywords.contains(where: { combined.contains($0) }) { return "utils" }

        // 6. Inspect Info.plist LSApplicationCategoryType if bundle exists on disk
        if let appPath = meta?.bundlePath ?? bid.components(separatedBy: "::").last.flatMap({ NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0)?.path }),
           let plist = Bundle(path: appPath)?.infoDictionary,
           let lsCat = (plist["LSApplicationCategoryType"] as? String)?.lowercased() {
            if lsCat.contains("developer") || lsCat.contains("graphics") { return "ai_dev" }
            if lsCat.contains("social") { return "comm" }
            if lsCat.contains("productivity") || lsCat.contains("business") { return "prod" }
            if lsCat.contains("utilities") { return "utils" }
        }

        return "other"
    }

    func updateStatusBarBadgeForCurrentFolder() {
        let iconStyle = config.preferences.iconStyle
        let capsuleShape = config.preferences.capsuleShape
        let labelMode = config.preferences.statusBarLabelMode
        let swipeEnabled = config.preferences.enableMenuBarSwipe

        if let activeID = swipedFolderID, let folder = folder(byID: activeID) {
            let count = countVisibleItems(in: folder)
            hider.updateAppearance(
                symbolName: folder.symbolName,
                count: count,
                label: folder.name,
                accentColor: folder.nsAccentColor,
                iconStyle: iconStyle,
                capsuleShape: capsuleShape,
                labelMode: labelMode,
                swipeEnabled: swipeEnabled
            )
        } else {
            swipedFolderID = nil
            hider.updateAppearance(
                symbolName: config.preferences.statusIconSymbol,
                count: visibleLiveItemCount,
                label: "Все",
                accentColor: nil,
                iconStyle: iconStyle,
                capsuleShape: capsuleShape,
                labelMode: labelMode,
                swipeEnabled: swipeEnabled
            )
        }

        // Keep dedicated menu bar icons synchronized for all folders with `showInMenuBar == true`
        let folders = topLevelFolders()
        var counts: [UUID: Int] = [:]
        for f in folders {
            counts[f.id] = countVisibleItems(in: f)
        }
        hider.syncPinnedFolderItems(
            folders: folders,
            counts: counts,
            iconStyle: iconStyle,
            capsuleShape: capsuleShape
        )
    }

    func setDisplayMode(_ mode: DisplayMode) {
        config.preferences.displayMode = mode
        saveConfig()
    }

    func setCylinderScope(_ scope: CylinderScope) {
        config.preferences.cylinderScope = scope
        if scope == .allFlat {
            cylinderFolderPath = []
        }
        saveConfig()
    }

    func setHideMenuBarIcons(_ hide: Bool) {
        config.preferences.hideMenuBarIcons = hide
        activator.cancelPendingRehide()
        hider.setDesiredHideIcons(hide)
        saveConfig()
    }

    func toggleTemporaryReveal() {
        activator.cancelPendingRehide()
        if hider.isCurrentlyHiding {
            hider.setTemporarilyRevealed(true)
        } else {
            hider.setTemporarilyRevealed(false)
        }
    }

    func setShowSystemItems(_ show: Bool) {
        config.preferences.showSystemItems = show
        hider.updateBadgeCount(visibleLiveItemCount)
        saveConfig()
    }

    func setShowOfflineItems(_ show: Bool) {
        config.preferences.showOfflineItems = show
        saveConfig()
    }

    func setAutoRehideMode(_ mode: AutoRehideMode) {
        config.preferences.autoRehideMode = mode
        saveConfig()
    }

    func setStatusIconSymbol(_ symbol: String) {
        config.preferences.statusIconSymbol = symbol
        hider.updateSymbol(symbol)
        saveConfig()
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        config.preferences.launchAtLogin = enabled
        if Bundle.main.bundleURL.pathExtension == "app" {
            do {
                if enabled {
                    try SMAppService.mainApp.register()
                } else {
                    try SMAppService.mainApp.unregister()
                }
            } catch {
                // Ignore if running unsigned or outside standard app bundle context
            }
        }
        saveConfig()
    }

    func dismissOnboardingTip() {
        config.preferences.dismissedOnboardingTip = true
        saveConfig()
    }

    func dismissPermissionBanner() {
        config.preferences.dismissedPermissionBanner = true
        saveConfig()
    }

    // MARK: - Folder & Divider Management

    func presentCreateFolder(parentFolderID: UUID? = nil) {
        folderEditorState = FolderEditorState(
            existingFolderID: nil,
            parentFolderID: nil,
            name: "",
            symbolName: "folder.fill",
            accentHex: "#0A84FF",
            showInMenuBar: false
        )
    }

    func presentEditFolder(_ folder: FoldieFolder) {
        folderEditorState = FolderEditorState(
            existingFolderID: folder.id,
            parentFolderID: nil,
            name: folder.name,
            symbolName: folder.symbolName,
            accentHex: folder.accentHex,
            showInMenuBar: folder.showInMenuBar
        )
    }

    func commitFolderEditor(_ state: FolderEditorState) {
        let trimmed = state.name.trimmingCharacters(in: .whitespacesAndNewlines)
        let finalName = trimmed.isEmpty ? "Новая папка" : trimmed

        if let existingID = state.existingFolderID {
            updateFolder(
                id: existingID,
                name: finalName,
                symbolName: state.symbolName,
                accentHex: state.accentHex,
                showInMenuBar: state.showInMenuBar
            )
        } else {
            // Always create new folders as top-level main folders for clean menu bar swiping & pinning
            let folder = FoldieFolder(
                name: finalName,
                symbolName: state.symbolName,
                accentHex: state.accentHex,
                isExpanded: false,
                showInMenuBar: state.showInMenuBar,
                children: []
            )
            config.rootNodes.insert(.folder(folder), at: 0)
            saveConfig()
            updateStatusBarBadgeForCurrentFolder()
        }
        folderEditorState = nil
    }

    func updateFolder(id: UUID, name: String, symbolName: String, accentHex: String, showInMenuBar: Bool? = nil) {
        _ = mutateFolder(id: id, in: &config.rootNodes) { folder in
            folder.name = name
            folder.symbolName = symbolName
            folder.accentHex = accentHex
            if let showInMenuBar {
                folder.showInMenuBar = showInMenuBar
            }
        }
        saveConfig()
        updateStatusBarBadgeForCurrentFolder()
    }

    func toggleFolderExpanded(id: UUID) {
        _ = mutateFolder(id: id, in: &config.rootNodes) { folder in
            folder.isExpanded.toggle()
        }
        saveConfig()
    }

    func deleteFolder(id: UUID) {
        cylinderFolderPath.removeAll { $0 == id }
        if swipedFolderID == id { swipedFolderID = nil }
        if activePopupFolderID == id { activePopupFolderID = nil }
        _ = deleteFolderUnwrappingChildren(id: id, in: &config.rootNodes)
        saveConfig()
        updateStatusBarBadgeForCurrentFolder()
    }

    func presentCreateDivider(parentFolderID: UUID? = nil) {
        dividerEditorState = DividerEditorState(
            existingDividerID: nil,
            parentFolderID: parentFolderID,
            label: ""
        )
    }

    func presentEditDivider(_ divider: FoldieDivider) {
        dividerEditorState = DividerEditorState(
            existingDividerID: divider.id,
            parentFolderID: nil,
            label: divider.label
        )
    }

    func commitDividerEditor(_ state: DividerEditorState) {
        let trimmed = state.label.trimmingCharacters(in: .whitespacesAndNewlines)
        if let existingID = state.existingDividerID {
            _ = mutateDivider(id: existingID, in: &config.rootNodes) { divider in
                divider.label = trimmed
            }
        } else {
            let divider = FoldieDivider(label: trimmed)
            if let parentID = state.parentFolderID {
                _ = insertNode(.divider(divider), intoFolder: parentID, in: &config.rootNodes, atFront: false)
            } else {
                config.rootNodes.append(.divider(divider))
            }
        }
        saveConfig()
        dividerEditorState = nil
    }

    func deleteDivider(id: UUID) {
        _ = removeNode(nodeID: "divider::\(id.uuidString)", from: &config.rootNodes)
        saveConfig()
    }

    // MARK: - Reordering & Moving Nodes

    func moveNode(nodeID: String, toFolderID targetFolderID: UUID?) {
        // Prevent moving a folder into itself or one of its own descendants
        if nodeID.hasPrefix("folder::"),
           let movingFolderUUID = UUID(uuidString: String(nodeID.dropFirst("folder::".count))),
           let targetFolderID,
           (movingFolderUUID == targetFolderID || folder(movingFolderUUID, containsDescendantFolder: targetFolderID)) {
            return
        }

        guard let extracted = removeNode(nodeID: nodeID, from: &config.rootNodes) else {
            return
        }

        if let targetFolderID {
            if !insertNode(extracted, intoFolder: targetFolderID, in: &config.rootNodes, atFront: false) {
                config.rootNodes.append(extracted)
            }
        } else {
            config.rootNodes.append(extracted)
        }
        saveConfig()
        updateStatusBarBadgeForCurrentFolder()
    }

    func moveNode(nodeID: String, before targetNodeID: String) {
        guard nodeID != targetNodeID else { return }

        // Prevent moving a folder into its own descendant
        if nodeID.hasPrefix("folder::"),
           let movingFolderUUID = UUID(uuidString: String(nodeID.dropFirst("folder::".count))),
           nodeExistsInsideFolder(nodeID: targetNodeID, folderID: movingFolderUUID) {
            return
        }

        guard let extracted = removeNode(nodeID: nodeID, from: &config.rootNodes) else {
            return
        }

        if !insertNode(extracted, beforeNodeID: targetNodeID, in: &config.rootNodes) {
            config.rootNodes.append(extracted)
        }
        saveConfig()
    }

    func nudgeNode(nodeID: String, up: Bool) {
        if nudgeNode(nodeID: nodeID, up: up, in: &config.rootNodes) {
            saveConfig()
        }
    }

    func resetLayout() {
        cylinderFolderPath = []
        config.rootNodes = liveItemsByKey.values
            .sorted { $0.frame.origin.x < $1.frame.origin.x }
            .map { .item(key: $0.key) }
        saveConfig()
    }

    // MARK: - Queries & Tree Helpers

    func allFolders() -> [FoldieFolder] {
        var result: [FoldieFolder] = []
        collectFolders(from: config.rootNodes, into: &result)
        return result
    }

    func folder(byID id: UUID) -> FoldieFolder? {
        findFolder(id: id, in: config.rootNodes)
    }

    func countVisibleItems(in folder: FoldieFolder) -> Int {
        var count = 0
        for child in folder.children {
            switch child {
            case .item(let key):
                if isItemVisibleInUI(key: key) { count += 1 }
            case .folder(let sub):
                count += countVisibleItems(in: sub)
            case .divider:
                break
            }
        }
        return count
    }

    /// Nodes currently displayed in List mode (filtered to the hovered pinned folder or swiped folder).
    var activeListNodes: [FoldieNode] {
        let targetFolderID = activePopupFolderID ?? swipedFolderID
        if let activeID = targetFolderID, let folder = folder(byID: activeID) {
            return folder.children
        }
        return config.rootNodes
    }

    /// Nodes currently displayed in Cylinder mode according to active pinned/swiped folder, `cylinderScope`, and `cylinderFolderPath`.
    var cylinderNodes: [FoldieNode] {
        let targetFolderID = activePopupFolderID ?? swipedFolderID
        if let activeID = targetFolderID, cylinderFolderPath.isEmpty, let folder = folder(byID: activeID) {
            return folder.children.filter { node in
                switch node {
                case .item(let key): return isItemVisibleInUI(key: key)
                case .folder: return true
                case .divider: return false
                }
            }
        }
        switch config.preferences.cylinderScope {
        case .allFlat:
            var items: [FoldieNode] = []
            collectVisibleLeafItems(from: config.rootNodes, into: &items)
            return items
        case .structured:
            let baseNodes: [FoldieNode]
            if let currentFolderID = cylinderFolderPath.last,
               let folder = folder(byID: currentFolderID) {
                baseNodes = folder.children
            } else {
                baseNodes = config.rootNodes
            }
            return baseNodes.filter { node in
                switch node {
                case .item(let key):
                    return isItemVisibleInUI(key: key)
                case .folder:
                    return true
                case .divider:
                    return false
                }
            }
        }
    }

    var currentCylinderFolder: FoldieFolder? {
        guard let id = cylinderFolderPath.last else { return nil }
        return folder(byID: id)
    }

    func enterCylinderFolder(_ folder: FoldieFolder) {
        cylinderFolderPath.append(folder.id)
    }

    func popCylinderFolder() {
        if !cylinderFolderPath.isEmpty {
            cylinderFolderPath.removeLast()
        }
    }

    /// Filtered search results across the whole tree.
    func matchingItemKeys(for query: String) -> [String] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        var keys: [String] = []
        collectVisibleItemKeys(from: config.rootNodes, into: &keys)
        return keys.filter { key in
            let name = displayName(forItemKey: key)
            let sub = subtitle(forItemKey: key)
            return name.localizedCaseInsensitiveContains(trimmed)
                || sub.localizedCaseInsensitiveContains(trimmed)
        }
    }

    // MARK: - Private Tree Recursion

    private func saveConfig() {
        persistence.save(config)
    }

    private func pruneObsoleteNodes(in nodes: inout [FoldieNode], liveKeys: Set<String>) -> Bool {
        var mutated = false
        nodes.removeAll { node in
            if case .item(let key) = node {
                let isGarbageKey = key.contains("com.foldie.")
                    || key.contains("AddBentoBox")
                    || key.contains("hiddenbar_separate")
                    || key.contains("System Status Item Clone")
                    || key.contains("::slot-")
                    || key.hasPrefix("Пункт управления::")
                    || key.hasPrefix("ControlCenter::")
                if isGarbageKey {
                    config.itemMetadata.removeValue(forKey: key)
                    mutated = true
                    return true
                }
                // Remove stale offline ControlCenter / Hidden Bar duplicate entries
                if (key.hasPrefix("com.apple.controlcenter::") || key.contains("com.dwarvesv.minimalbar#")) && !liveKeys.contains(key) {
                    config.itemMetadata.removeValue(forKey: key)
                    mutated = true
                    return true
                }
            }
            return false
        }
        for idx in nodes.indices {
            if case .folder(var folder) = nodes[idx] {
                if pruneObsoleteNodes(in: &folder.children, liveKeys: liveKeys) {
                    nodes[idx] = .folder(folder)
                    mutated = true
                }
            }
        }
        return mutated
    }

    private func findParentFolderID(
        ofNodeID nodeID: String,
        in nodes: [FoldieNode],
        currentFolderID: UUID?
    ) -> UUID? {
        for node in nodes {
            if node.id == nodeID { return currentFolderID }
            if case .folder(let folder) = node {
                if let found = findParentFolderID(ofNodeID: nodeID, in: folder.children, currentFolderID: folder.id) {
                    return found
                }
            }
        }
        return nil
    }

    private func collectAllItemKeys(in nodes: [FoldieNode]) -> Set<String> {
        var keys = Set<String>()
        for node in nodes {
            switch node {
            case .item(let key):
                keys.insert(key)
            case .folder(let folder):
                keys.formUnion(collectAllItemKeys(in: folder.children))
            case .divider:
                break
            }
        }
        return keys
    }

    private func collectVisibleLeafItems(from nodes: [FoldieNode], into out: inout [FoldieNode]) {
        for node in nodes {
            switch node {
            case .item(let key):
                if isItemVisibleInUI(key: key) {
                    out.append(.item(key: key))
                }
            case .folder(let folder):
                collectVisibleLeafItems(from: folder.children, into: &out)
            case .divider:
                break
            }
        }
    }

    private func collectVisibleItemKeys(from nodes: [FoldieNode], into out: inout [String]) {
        for node in nodes {
            switch node {
            case .item(let key):
                if isItemVisibleInUI(key: key) { out.append(key) }
            case .folder(let folder):
                collectVisibleItemKeys(from: folder.children, into: &out)
            case .divider:
                break
            }
        }
    }

    private func collectFolders(from nodes: [FoldieNode], into out: inout [FoldieFolder]) {
        for node in nodes {
            if case .folder(let folder) = node {
                out.append(folder)
                collectFolders(from: folder.children, into: &out)
            }
        }
    }

    private func findFolder(id: UUID, in nodes: [FoldieNode]) -> FoldieFolder? {
        for node in nodes {
            if case .folder(let folder) = node {
                if folder.id == id { return folder }
                if let found = findFolder(id: id, in: folder.children) { return found }
            }
        }
        return nil
    }

    private func folder(_ folderID: UUID, containsDescendantFolder descendantID: UUID) -> Bool {
        guard let target = findFolder(id: folderID, in: config.rootNodes) else { return false }
        return findFolder(id: descendantID, in: target.children) != nil
    }

    private func nodeExistsInsideFolder(nodeID: String, folderID: UUID) -> Bool {
        guard let target = findFolder(id: folderID, in: config.rootNodes) else { return false }
        return containsNode(nodeID: nodeID, in: target.children)
    }

    private func containsNode(nodeID: String, in nodes: [FoldieNode]) -> Bool {
        for node in nodes {
            if node.id == nodeID { return true }
            if case .folder(let folder) = node, containsNode(nodeID: nodeID, in: folder.children) {
                return true
            }
        }
        return false
    }

    private func mutateFolder(
        id: UUID,
        in nodes: inout [FoldieNode],
        transform: (inout FoldieFolder) -> Void
    ) -> Bool {
        for idx in nodes.indices {
            if case .folder(var folder) = nodes[idx] {
                if folder.id == id {
                    transform(&folder)
                    nodes[idx] = .folder(folder)
                    return true
                }
                if mutateFolder(id: id, in: &folder.children, transform: transform) {
                    nodes[idx] = .folder(folder)
                    return true
                }
            }
        }
        return false
    }

    private func mutateDivider(
        id: UUID,
        in nodes: inout [FoldieNode],
        transform: (inout FoldieDivider) -> Void
    ) -> Bool {
        for idx in nodes.indices {
            switch nodes[idx] {
            case .divider(var divider) where divider.id == id:
                transform(&divider)
                nodes[idx] = .divider(divider)
                return true
            case .folder(var folder):
                if mutateDivider(id: id, in: &folder.children, transform: transform) {
                    nodes[idx] = .folder(folder)
                    return true
                }
            default:
                break
            }
        }
        return false
    }

    private func deleteFolderUnwrappingChildren(id: UUID, in nodes: inout [FoldieNode]) -> Bool {
        for idx in nodes.indices {
            if case .folder(var folder) = nodes[idx] {
                if folder.id == id {
                    let children = folder.children
                    nodes.remove(at: idx)
                    nodes.insert(contentsOf: children, at: idx)
                    return true
                }
                if deleteFolderUnwrappingChildren(id: id, in: &folder.children) {
                    nodes[idx] = .folder(folder)
                    return true
                }
            }
        }
        return false
    }

    private func removeNode(nodeID: String, from nodes: inout [FoldieNode]) -> FoldieNode? {
        for idx in nodes.indices {
            if nodes[idx].id == nodeID {
                return nodes.remove(at: idx)
            }
            if case .folder(var folder) = nodes[idx] {
                if let removed = removeNode(nodeID: nodeID, from: &folder.children) {
                    nodes[idx] = .folder(folder)
                    return removed
                }
            }
        }
        return nil
    }

    private func insertNode(
        _ node: FoldieNode,
        intoFolder folderID: UUID,
        in nodes: inout [FoldieNode],
        atFront: Bool
    ) -> Bool {
        for idx in nodes.indices {
            if case .folder(var folder) = nodes[idx] {
                if folder.id == folderID {
                    if atFront {
                        folder.children.insert(node, at: 0)
                    } else {
                        folder.children.append(node)
                    }
                    folder.isExpanded = true
                    nodes[idx] = .folder(folder)
                    return true
                }
                if insertNode(node, intoFolder: folderID, in: &folder.children, atFront: atFront) {
                    nodes[idx] = .folder(folder)
                    return true
                }
            }
        }
        return false
    }

    private func insertNode(
        _ node: FoldieNode,
        beforeNodeID targetID: String,
        in nodes: inout [FoldieNode]
    ) -> Bool {
        for idx in nodes.indices {
            if nodes[idx].id == targetID {
                nodes.insert(node, at: idx)
                return true
            }
            if case .folder(var folder) = nodes[idx] {
                if insertNode(node, beforeNodeID: targetID, in: &folder.children) {
                    nodes[idx] = .folder(folder)
                    return true
                }
            }
        }
        return false
    }

    private func nudgeNode(nodeID: String, up: Bool, in nodes: inout [FoldieNode]) -> Bool {
        if let idx = nodes.firstIndex(where: { $0.id == nodeID }) {
            let targetIdx = up ? idx - 1 : idx + 1
            guard targetIdx >= 0 && targetIdx < nodes.count else { return false }
            nodes.swapAt(idx, targetIdx)
            return true
        }
        for idx in nodes.indices {
            if case .folder(var folder) = nodes[idx] {
                if nudgeNode(nodeID: nodeID, up: up, in: &folder.children) {
                    nodes[idx] = .folder(folder)
                    return true
                }
            }
        }
        return false
    }
}
