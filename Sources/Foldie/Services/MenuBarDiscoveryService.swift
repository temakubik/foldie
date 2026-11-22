import AppKit
import ApplicationServices
import CoreGraphics
import Foundation
import ScreenCaptureKit

/// Discovers real menu bar applications and macOS system status items using a 3-layer pipeline:
/// 1. Accessibility AXExtrasMenuBar across running apps (real app names, real icons, exact menu bar frames).
/// 2. CGWindowListCopyWindowInfo status windows (named items + windowIDs, strictly filtering out macOS 26 clones/placeholders).
/// 3. Running LSUIElement / menu-bar accessory user apps fallback so real apps with real icons ALWAYS appear instead of placeholders.
@MainActor
final class MenuBarDiscoveryService {
    private var imageCache: [String: NSImage] = [:]
    private let ownPID: pid_t = ProcessInfo.processInfo.processIdentifier
    private var lastCaptureAttempt: Date = .distantPast
    private(set) var isCaptureDisabledForSession: Bool = false

    func resetCaptureBackoff() {
        isCaptureDisabledForSession = false
        lastCaptureAttempt = .distantPast
    }

    private static let ignoredOwners: Set<String> = [
        "Window Server",
        "WindowManager",
        "Dock",
        "Wallpaper",
        "CursorUIViewService",
        "screencaptureui",
        "loginwindow",
        "Foldie"
    ]

    private static let ignoredTitles: Set<String> = [
        "AddBentoBox",
        "hiddenbar_separate",
        "System Status Item Clone"
    ]

    private static let systemOwners: Set<String> = [
        "ControlCenter",
        "Пункт управления",
        "SystemUIServer",
        "Spotlight",
        "TextInputMenuAgent",
        "Siri",
        "NotificationCenter",
        "WiFiAgent",
        "AirPlayUIAgent",
        "UniversalAccessAuthWarn",
        "TimeMachine"
    ]

    private static let knownSystemTitles: Set<String> = [
        "WiFi", "Bluetooth", "Battery", "Clock", "Sound",
        "BentoBox", "BentoBox-0", "FocusModes", "ScreenMirroring",
        "Display", "NowPlaying", "AirDrop", "AudioVideoModule",
        "AccessibilityShortcuts", "KeyboardBrightness", "UserSwitcher",
        "Hearing", "Weather", "Spotlight", "Siri"
    ]

    /// Discovers real menu bar items (third-party apps + named system items), never returning anonymous ControlCenter placeholders.
    func discoverItems(excludingWindowIDs: Set<CGWindowID>) -> [MenuBarItem] {
        let runningApps = NSWorkspace.shared.runningApplications
        var discovered: [MenuBarItem] = []
        var seenBundleIDs = Set<String>()
        var seenKeys = Set<String>()

        // Layer 1: Accessibility AXExtrasMenuBar across all running apps (most accurate source on macOS 14–26!)
        if AXIsProcessTrusted() {
            let axItems = discoverViaAccessibility(runningApps: runningApps)
            for item in axItems {
                if !seenKeys.contains(item.key) {
                    discovered.append(item)
                    seenKeys.insert(item.key)
                    if let bid = item.bundleIdentifier, !item.isSystemItem {
                        seenBundleIDs.insert(bid)
                    }
                }
            }
        }

        // Layer 2: CGWindowListCopyWindowInfo status bar windows (excludes clones & empty ControlCenter placeholders)
        let cgItems = discoverViaCGWindowList(
            excludingWindowIDs: excludingWindowIDs,
            runningApps: runningApps
        )
        for item in cgItems {
            // If Layer 1 already discovered this third-party app, enrich its windowID & frame instead of duplicating
            if !item.isSystemItem,
               let bid = item.bundleIdentifier,
               let existingIdx = discovered.firstIndex(where: { $0.bundleIdentifier == bid && !$0.isSystemItem }) {
                let existing = discovered[existingIdx]
                if existing.windowID == 0 || existing.frame == .zero {
                    discovered[existingIdx] = MenuBarItem(
                        key: existing.key,
                        windowID: item.windowID,
                        pid: existing.pid,
                        ownerName: existing.ownerName,
                        title: existing.title,
                        bundleIdentifier: existing.bundleIdentifier,
                        frame: item.frame != .zero ? item.frame : existing.frame,
                        isOnscreen: item.isOnscreen,
                        isSystemItem: false,
                        capturedImage: existing.capturedImage ?? item.capturedImage,
                        appIcon: existing.appIcon ?? item.appIcon
                    )
                }
                continue
            }

            if !seenKeys.contains(item.key) {
                discovered.append(item)
                seenKeys.insert(item.key)
                if let bid = item.bundleIdentifier, !item.isSystemItem {
                    seenBundleIDs.insert(bid)
                }
            }
        }

        // Layer 3: Real running menu-bar accessory user apps (.accessory / LSUIElement apps in /Applications etc.)
        // Ensures users ALWAYS see their real menu bar apps (Mos, BetterMouse, DisplayLink, OneDrive, Figma, AdGuard VPN, etc.)
        // with crisp real app icons even when macOS 26 hides CGWindow names or ControlCenter wraps them.
        let accessoryApps = discoverRunningMenuBarAccessoryApps(
            runningApps: runningApps,
            alreadySeenBundleIDs: seenBundleIDs
        )
        for item in accessoryApps {
            if !seenKeys.contains(item.key) {
                discovered.append(item)
                seenKeys.insert(item.key)
            }
        }

        // Sort: third-party apps first (left-to-right by frame if known, otherwise alphabetically), then system items.
        discovered.sort { lhs, rhs in
            if lhs.isSystemItem != rhs.isSystemItem {
                return !lhs.isSystemItem
            }
            let lhsHasFrame = lhs.frame.width > 0 && lhs.frame.origin.x > 0
            let rhsHasFrame = rhs.frame.width > 0 && rhs.frame.origin.x > 0
            if lhsHasFrame && rhsHasFrame && abs(lhs.frame.origin.x - rhs.frame.origin.x) > 1 {
                return lhs.frame.origin.x < rhs.frame.origin.x
            }
            return lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName) == .orderedAscending
        }

        return discovered
    }

    // MARK: - Layer 1: Accessibility AXExtrasMenuBar

    private func discoverViaAccessibility(runningApps: [NSRunningApplication]) -> [MenuBarItem] {
        var results: [MenuBarItem] = []

        for app in runningApps {
            let pid = app.processIdentifier
            if pid == ownPID { continue }
            guard let bundleID = app.bundleIdentifier, !bundleID.isEmpty else { continue }
            if bundleID == Bundle.main.bundleIdentifier || bundleID.hasPrefix("com.foldie.") { continue }

            let axApp = AXUIElementCreateApplication(pid)
            var extrasRef: CFTypeRef?
            let err = AXUIElementCopyAttributeValue(axApp, "AXExtrasMenuBar" as CFString, &extrasRef)
            guard err == .success,
                  let extrasObj = extrasRef,
                  CFGetTypeID(extrasObj) == AXUIElementGetTypeID() else {
                continue
            }

            let extrasBar = unsafeDowncast(extrasObj, to: AXUIElement.self)
            var childrenRef: CFTypeRef?
            let cerr = AXUIElementCopyAttributeValue(extrasBar, kAXChildrenAttribute as CFString, &childrenRef)
            guard cerr == .success, let children = childrenRef as? [AXUIElement], !children.isEmpty else {
                continue
            }

            let isAppleSystemApp = bundleID.hasPrefix("com.apple.")
                && (bundleID.contains("controlcenter")
                    || bundleID.contains("systemuiserver")
                    || bundleID.contains("Spotlight")
                    || bundleID.contains("TextInputMenuAgent")
                    || bundleID.contains("Siri")
                    || bundleID.contains("NotificationCenter"))

            let ownerName = app.localizedName ?? bundleID

            for (idx, child) in children.enumerated() {
                let rawTitle = axStringAttribute(child, kAXTitleAttribute as CFString) ?? ""
                let rawDesc = axStringAttribute(child, kAXDescriptionAttribute as CFString) ?? ""
                let rawID = axStringAttribute(child, kAXIdentifierAttribute as CFString) ?? ""

                let combinedCheck = "\(rawTitle) \(rawDesc) \(rawID)"
                if combinedCheck.contains("com.foldie.")
                    || combinedCheck.contains("System Status Item Clone")
                    || combinedCheck.contains("AddBentoBox")
                    || combinedCheck.contains("hiddenbar_separate") {
                    continue
                }

                let frame = axFrame(of: child)
                if frame.width > 420 { continue } // Skip giant hider spacers

                // For ControlCenter, use descriptive identifier/description (e.g. Wi-Fi, Battery, Clock)
                let effectiveTitle: String
                if isAppleSystemApp {
                    let candidateLabel = !rawDesc.isEmpty ? rawDesc : (!rawTitle.isEmpty ? rawTitle : rawID)
                    if candidateLabel.isEmpty { continue }
                    effectiveTitle = prettifyTitle(candidateLabel)
                } else {
                    effectiveTitle = children.count > 1 && !rawDesc.isEmpty ? rawDesc : ""
                }

                let key: String
                if isAppleSystemApp {
                    key = "\(bundleID)::\(rawID.isEmpty ? effectiveTitle : rawID)"
                } else if children.count == 1 {
                    key = "app::\(bundleID)"
                } else {
                    key = "app::\(bundleID)#\(idx)"
                }

                results.append(MenuBarItem(
                    key: key,
                    windowID: 0,
                    pid: pid,
                    ownerName: ownerName,
                    title: effectiveTitle,
                    bundleIdentifier: bundleID,
                    frame: frame,
                    isOnscreen: frame.origin.x > 0 && frame.width >= 4,
                    isSystemItem: isAppleSystemApp,
                    capturedImage: imageCache[key],
                    appIcon: isAppleSystemApp ? nil : resolveBestAppIcon(for: app)
                ))
            }
        }

        return results
    }

    private func axStringAttribute(_ element: AXUIElement, _ attribute: CFString) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute, &value) == .success else { return nil }
        return (value as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func axFrame(of element: AXUIElement) -> CGRect {
        var posRef: CFTypeRef?
        var sizeRef: CFTypeRef?
        var pt = CGPoint.zero
        var sz = CGSize.zero
        if AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &posRef) == .success,
           let p = posRef, CFGetTypeID(p) == AXValueGetTypeID() {
            AXValueGetValue(unsafeDowncast(p, to: AXValue.self), .cgPoint, &pt)
        }
        if AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &sizeRef) == .success,
           let s = sizeRef, CFGetTypeID(s) == AXValueGetTypeID() {
            AXValueGetValue(unsafeDowncast(s, to: AXValue.self), .cgSize, &sz)
        }
        return CGRect(origin: pt, size: sz)
    }

    // MARK: - Layer 2: CGWindowListCopyWindowInfo

    private func discoverViaCGWindowList(
        excludingWindowIDs: Set<CGWindowID>,
        runningApps: [NSRunningApplication]
    ) -> [MenuBarItem] {
        let statusLevel = Int(CGWindowLevelForKey(.statusWindow))
        guard let rawList = CGWindowListCopyWindowInfo([.optionAll], kCGNullWindowID) as? [[String: Any]] else {
            return []
        }

        struct Candidate {
            let windowID: CGWindowID
            let pid: pid_t
            let ownerName: String
            let title: String
            let frame: CGRect
            let isOnscreen: Bool
        }

        var candidates: [Candidate] = []
        for dict in rawList {
            guard let layerNum = dict[kCGWindowLayer as String] as? NSNumber,
                  layerNum.intValue == statusLevel else {
                continue
            }
            guard let windowNum = dict[kCGWindowNumber as String] as? NSNumber,
                  let windowID = CGWindowID(exactly: windowNum.int64Value),
                  let pidNum = dict[kCGWindowOwnerPID as String] as? NSNumber else {
                continue
            }
            let pid = pid_t(pidNum.int32Value)
            if pid == ownPID || excludingWindowIDs.contains(windowID) {
                continue
            }

            let ownerName = (dict[kCGWindowOwnerName as String] as? String) ?? ""
            if ownerName.isEmpty || Self.ignoredOwners.contains(ownerName) {
                continue
            }

            let title = ((dict[kCGWindowName as String] as? String) ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)

            // Strictly filter out Foldie's own items, hiddenbar spacer, and macOS 26 ControlCenter clones!
            if title.hasPrefix("com.foldie.")
                || title.hasPrefix("System Status Item Clone")
                || Self.ignoredTitles.contains(title) {
                continue
            }

            let isOnscreen = (dict[kCGWindowIsOnscreen as String] as? NSNumber)?.boolValue ?? false

            guard let boundsDict = dict[kCGWindowBounds as String] as? NSDictionary,
                  let frame = CGRect(dictionaryRepresentation: boundsDict) else {
                continue
            }

            if frame.width < 4 || frame.width > 420 || frame.height < 14 || frame.height > 64 {
                continue
            }
            if frame.origin.y > 120 || frame.origin.y < -120 {
                continue
            }

            candidates.append(Candidate(
                windowID: windowID,
                pid: pid,
                ownerName: ownerName,
                title: title,
                frame: frame,
                isOnscreen: isOnscreen
            ))
        }

        candidates.sort { lhs, rhs in
            if abs(lhs.frame.origin.x - rhs.frame.origin.x) > 1 {
                return lhs.frame.origin.x < rhs.frame.origin.x
            }
            return lhs.windowID < rhs.windowID
        }

        var usedKeys = Set<String>()
        var results: [MenuBarItem] = []

        for candidate in candidates {
            let hostApp = NSRunningApplication(processIdentifier: candidate.pid)
            let hostBundleID = hostApp?.bundleIdentifier
            let isHostedByControlCenter = (hostBundleID == "com.apple.controlcenter")
                || candidate.ownerName == "ControlCenter"
                || candidate.ownerName == "Пункт управления"

            // CRITICAL: Never emit anonymous empty-title ControlCenter windows as placeholder "Пункт управления" rows!
            if isHostedByControlCenter && candidate.title.isEmpty {
                continue
            }

            let resolvedApp = isHostedByControlCenter
                ? resolveHostedThirdPartyApp(fromTitle: candidate.title, runningApps: runningApps)
                : nil

            let effectiveApp = resolvedApp ?? hostApp
            let effectiveBundleID = resolvedApp?.bundleIdentifier ?? hostBundleID
            let effectiveOwnerName = resolvedApp?.localizedName ?? candidate.ownerName
            let effectivePID = resolvedApp?.processIdentifier ?? candidate.pid

            let isSystem: Bool
            if resolvedApp != nil {
                isSystem = false
            } else if isHostedByControlCenter {
                isSystem = Self.knownSystemTitles.contains(candidate.title)
                    || candidate.title.hasPrefix("com.apple.")
                    || candidate.title.hasPrefix("BentoBox")
            } else {
                isSystem = Self.systemOwners.contains(candidate.ownerName)
                    || (hostBundleID?.hasPrefix("com.apple.controlcenter") == true)
                    || (hostBundleID?.hasPrefix("com.apple.systemuiserver") == true)
                    || (hostBundleID?.hasPrefix("com.apple.Spotlight") == true)
                    || (hostBundleID?.hasPrefix("com.apple.TextInputMenuAgent") == true)
                    || (hostBundleID?.hasPrefix("com.apple.Siri") == true)
            }

            let key: String
            if !isSystem, let bid = effectiveBundleID, !bid.isEmpty {
                key = "app::\(bid)"
            } else {
                let baseID = effectiveBundleID ?? effectiveOwnerName
                let normalizedTitle = candidate.title
                if !normalizedTitle.isEmpty && !normalizedTitle.hasPrefix("Item-") {
                    key = "\(baseID)::\(normalizedTitle)"
                } else {
                    continue
                }
            }

            if usedKeys.contains(key) { continue }
            usedKeys.insert(key)

            let cleanTitle = resolvedApp != nil ? "" : prettifyTitle(candidate.title)

            results.append(MenuBarItem(
                key: key,
                windowID: candidate.windowID,
                pid: effectivePID,
                ownerName: effectiveOwnerName,
                title: cleanTitle,
                bundleIdentifier: effectiveBundleID,
                frame: candidate.frame,
                isOnscreen: candidate.isOnscreen,
                isSystemItem: isSystem,
                capturedImage: imageCache[key],
                appIcon: isSystem ? nil : (effectiveApp.flatMap { resolveBestAppIcon(for: $0) })
            ))
        }

        return results
    }

    // MARK: - Layer 3: Running Menu Bar Accessory Apps (.accessory / LSUIElement)

    private func discoverRunningMenuBarAccessoryApps(
        runningApps: [NSRunningApplication],
        alreadySeenBundleIDs: Set<String>
    ) -> [MenuBarItem] {
        var results: [MenuBarItem] = []

        for app in runningApps {
            if app.processIdentifier == ownPID { continue }
            guard app.activationPolicy == .accessory else { continue }
            guard let bundleID = app.bundleIdentifier, !bundleID.isEmpty else { continue }
            if bundleID == Bundle.main.bundleIdentifier || bundleID.hasPrefix("com.foldie.") || bundleID.hasPrefix("com.apple.") { continue }
            if alreadySeenBundleIDs.contains(bundleID) { continue }

            guard let bundleURL = app.bundleURL else { continue }
            let path = bundleURL.path

            // Must be a real .app bundle, not a system daemon, app extension, or nested Helper/Updater binary
            guard bundleURL.pathExtension == "app" else { continue }
            if path.hasPrefix("/System/") || path.contains("/CoreServices/") { continue }
            if path.contains("/Contents/Frameworks/") || path.contains("/Contents/PlugIns/") || path.contains("/Contents/XPCServices/") {
                continue
            }

            let name = app.localizedName ?? bundleURL.deletingPathExtension().lastPathComponent
            let lowerName = name.lowercased()
            let lowerBID = bundleID.lowercased()
            if lowerName.contains("helper") || lowerName.contains("updater") || lowerName.contains("crash")
                || lowerBID.contains(".helper") || lowerBID.contains("sparkle") || lowerBID.contains("pluginservice") {
                continue
            }

            let key = "app::\(bundleID)"
            results.append(MenuBarItem(
                key: key,
                windowID: 0,
                pid: app.processIdentifier,
                ownerName: name,
                title: "",
                bundleIdentifier: bundleID,
                frame: .zero,
                isOnscreen: true,
                isSystemItem: false,
                capturedImage: imageCache[key],
                appIcon: resolveBestAppIcon(for: app)
            ))
        }

        return results
    }

    /// Resolves the sharpest app icon directly from the .app bundle (reliable for Electron apps like Ollama, Notion, Trae).
    private func resolveBestAppIcon(for app: NSRunningApplication) -> NSImage? {
        if let bid = app.bundleIdentifier, bid == "com.figma.agent",
           let figmaURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.figma.Desktop") {
            return NSWorkspace.shared.icon(forFile: figmaURL.path)
        }
        if let url = app.bundleURL, FileManager.default.fileExists(atPath: url.path) {
            return NSWorkspace.shared.icon(forFile: url.path)
        }
        if let bid = app.bundleIdentifier,
           let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bid) {
            return NSWorkspace.shared.icon(forFile: url.path)
        }
        return app.icon
    }

    /// Attempts to match a ControlCenter-hosted status item title (e.g. "com.tw93.MoleApp.menuBarStatusItem",
    /// "hiddenbar_expandcollapse") back to its real running macOS application.
    private func resolveHostedThirdPartyApp(
        fromTitle title: String,
        runningApps: [NSRunningApplication]
    ) -> NSRunningApplication? {
        guard !title.isEmpty,
              !Self.knownSystemTitles.contains(title),
              !title.hasPrefix("com.apple."),
              !title.hasPrefix("BentoBox") else {
            return nil
        }

        let lowerTitle = title.lowercased()

        // 1. Direct bundle identifier prefix or containment match
        for app in runningApps {
            guard let bid = app.bundleIdentifier?.lowercased(), !bid.hasPrefix("com.apple.") else { continue }
            if lowerTitle.hasPrefix(bid) || lowerTitle.contains(bid) {
                return app
            }
        }

        // 2. Match against app localized name (e.g. "hiddenbar_expandcollapse" -> "Hidden Bar")
        let collapsedTitle = lowerTitle
            .replacingOccurrences(of: "_", with: "")
            .replacingOccurrences(of: "-", with: "")
            .replacingOccurrences(of: " ", with: "")
        for app in runningApps {
            guard let bid = app.bundleIdentifier?.lowercased(), !bid.hasPrefix("com.apple.") else { continue }
            if let name = app.localizedName?.lowercased() {
                let collapsedName = name
                    .replacingOccurrences(of: " ", with: "")
                    .replacingOccurrences(of: "-", with: "")
                if collapsedName.count >= 3 && collapsedTitle.contains(collapsedName) {
                    return app
                }
            }
        }

        return nil
    }

    private func prettifyTitle(_ title: String) -> String {
        if title == "com.apple.menuextra.vpn" { return "VPN" }
        if title == "BentoBox-0" || title == "BentoBox" { return "BentoBox" }
        if title == "AudioVideoModule" { return "Звук и видео" }
        if title.hasPrefix("hiddenbar_") { return "Hidden Bar" }
        return title
    }

    /// Captures live crisp icon thumbnails for system status items using ScreenCaptureKit.
    /// Carefully guarded and rate-limited so it NEVER spams macOS Screen Recording consent popups.
    func captureThumbnails(
        for items: [MenuBarItem],
        canUseScreenCaptureKit: Bool,
        force: Bool = false
    ) async -> [String: NSImage] {
        guard canUseScreenCaptureKit, !isCaptureDisabledForSession, !items.isEmpty else {
            return imageCache
        }

        // Only capture items that have a valid windowID and need a thumbnail (system items or apps without appIcon)
        let candidates = items.filter { item in
            guard item.windowID > 0 else { return false }
            let needsCapture = item.isSystemItem || item.appIcon == nil
            return needsCapture && (force || imageCache[item.key] == nil)
        }
        guard !candidates.isEmpty else {
            return imageCache
        }

        let now = Date()
        if !force && now.timeIntervalSince(lastCaptureAttempt) < 20.0 {
            return imageCache
        }
        lastCaptureAttempt = now

        do {
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
            let windowByID: [CGWindowID: SCWindow] = Dictionary(
                uniqueKeysWithValues: content.windows.map { ($0.windowID, $0) }
            )

            for item in candidates {
                guard let scWindow = windowByID[item.windowID] else { continue }
                guard scWindow.frame.width.isFinite, scWindow.frame.height.isFinite,
                      scWindow.frame.width >= 6, scWindow.frame.height >= 14 else { continue }

                let filter = SCContentFilter(desktopIndependentWindow: scWindow)
                let config = SCStreamConfiguration()
                let scale: CGFloat = NSScreen.main?.backingScaleFactor ?? 2.0
                config.width = max(1, min(1024, Int(scWindow.frame.width * scale)))
                config.height = max(1, min(256, Int(scWindow.frame.height * scale)))
                config.showsCursor = false
                config.capturesAudio = false
                config.backgroundColor = .clear
                config.shouldBeOpaque = false

                if let cgImage = try? await SCScreenshotManager.captureImage(
                    contentFilter: filter,
                    configuration: config
                ) {
                    let nsImage = NSImage(
                        cgImage: cgImage,
                        size: NSSize(width: scWindow.frame.width, height: scWindow.frame.height)
                    )
                    imageCache[item.key] = nsImage
                }
            }
        } catch {
            isCaptureDisabledForSession = true
        }

        return imageCache
    }

    /// Locates the current live onscreen CGRect (CG global top-left coordinates) of a specific item.
    func locateLiveFrame(for item: MenuBarItem) -> CGRect? {
        // 1. Check Accessibility AXExtrasMenuBar for the owning PID first (works even without Screen Recording)
        if AXIsProcessTrusted() {
            let axApp = AXUIElementCreateApplication(item.pid)
            var extrasRef: CFTypeRef?
            if AXUIElementCopyAttributeValue(axApp, "AXExtrasMenuBar" as CFString, &extrasRef) == .success,
               let extrasObj = extrasRef, CFGetTypeID(extrasObj) == AXUIElementGetTypeID() {
                let extrasBar = unsafeDowncast(extrasObj, to: AXUIElement.self)
                var childrenRef: CFTypeRef?
                if AXUIElementCopyAttributeValue(extrasBar, kAXChildrenAttribute as CFString, &childrenRef) == .success,
                   let children = childrenRef as? [AXUIElement] {
                    for child in children {
                        let f = axFrame(of: child)
                        if f.width >= 4 && f.origin.x > 0 {
                            if item.title.isEmpty {
                                return f
                            }
                            let t = axStringAttribute(child, kAXTitleAttribute as CFString) ?? ""
                            let d = axStringAttribute(child, kAXDescriptionAttribute as CFString) ?? ""
                            let i = axStringAttribute(child, kAXIdentifierAttribute as CFString) ?? ""
                            if t.localizedCaseInsensitiveContains(item.title)
                                || d.localizedCaseInsensitiveContains(item.title)
                                || i.localizedCaseInsensitiveContains(item.title) {
                                return f
                            }
                        }
                    }
                    if let first = children.first {
                        let f = axFrame(of: first)
                        if f.width >= 4 && f.origin.x > 0 { return f }
                    }
                }
            }
        }

        // 2. Check CGWindowListCopyWindowInfo
        let statusLevel = Int(CGWindowLevelForKey(.statusWindow))
        guard let rawList = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] else {
            return nil
        }

        if item.windowID > 0 {
            for dict in rawList {
                guard let layerNum = dict[kCGWindowLayer as String] as? NSNumber,
                      layerNum.intValue == statusLevel,
                      let windowNum = dict[kCGWindowNumber as String] as? NSNumber,
                      let windowID = CGWindowID(exactly: windowNum.int64Value),
                      windowID == item.windowID,
                      let boundsDict = dict[kCGWindowBounds as String] as? NSDictionary,
                      let frame = CGRect(dictionaryRepresentation: boundsDict),
                      frame.width >= 4 else {
                    continue
                }
                return frame
            }
        }

        for dict in rawList {
            guard let layerNum = dict[kCGWindowLayer as String] as? NSNumber,
                  layerNum.intValue == statusLevel,
                  let pidNum = dict[kCGWindowOwnerPID as String] as? NSNumber,
                  let boundsDict = dict[kCGWindowBounds as String] as? NSDictionary,
                  let frame = CGRect(dictionaryRepresentation: boundsDict),
                  frame.width >= 4 else {
                continue
            }
            let title = (dict[kCGWindowName as String] as? String) ?? ""
            if pid_t(pidNum.int32Value) == item.pid && (item.title.isEmpty || title == item.title) {
                return frame
            }
            if let bid = item.bundleIdentifier, !bid.isEmpty, title.localizedCaseInsensitiveContains(bid) {
                return frame
            }
        }

        return nil
    }
}
