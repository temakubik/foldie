import AppKit
import ApplicationServices
import CoreGraphics
import Foundation

/// Result of the automatic one-click collection into Foldie.
struct AutoCollectResult: Sendable {
    let success: Bool
    let message: String
}

/// Transparent tracking overlay placed inside Foldie's NSStatusBarButton to detect hover enter/exit
/// without intercepting left or right mouse clicks.
private final class StatusButtonHoverView: NSView {
    var onHoverChanged: ((Bool) -> Void)?
    var onScrollWheel: ((NSEvent) -> Void)?
    private var trackingArea: NSTrackingArea?

    override func hitTest(_ point: NSPoint) -> NSView? {
        // Let clicks pass straight through to NSStatusBarButton
        return nil
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let existing = trackingArea {
            removeTrackingArea(existing)
        }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        trackingArea = area
    }

    override func mouseEntered(with event: NSEvent) {
        onHoverChanged?(true)
    }

    override func mouseExited(with event: NSEvent) {
        onHoverChanged?(false)
    }

    override func scrollWheel(with event: NSEvent) {
        onScrollWheel?(event)
    }
}

/// Manages Foldie's two status items in the macOS menu bar:
/// - Always ensures the RIGHTMOST of our two items is the visible Foldie folder button.
/// - Always ensures the LEFTMOST of our two items is the expanding hider spacer.
/// This guarantees Foldie can never hide its own folder icon on macOS 14–26.
@MainActor
final class MenuBarHiderService: NSObject, ObservableObject {
    static let slotAName = "com.foldie.app.slotA"
    static let slotBName = "com.foldie.app.slotB"

    private var slotA: NSStatusItem?
    private var slotB: NSStatusItem?
    /// Tracks which of (slotA, slotB) currently acts as the visible folder button.
    private var folderIsSlotA: Bool = true

    @Published private(set) var isCurrentlyHiding: Bool = false
    @Published private(set) var isTemporarilyRevealed: Bool = false
    @Published private(set) var isFolderVisibleOnscreen: Bool = true
    @Published private(set) var conflictingAppName: String? = nil
    @Published private(set) var isHiddenBehindNotchOrOtherApp: Bool = false

    private static let conflictingManagerBundleIDs: [(bundleID: String, displayName: String)] = [
        ("com.dwarvesv.minimalbar", "Hidden Bar"),
        ("com.jordanbaird.Ice", "Ice"),
        ("com.surteesstudios.Bartender", "Bartender"),
        ("com.mortennn.Dozer", "Dozer"),
        ("com.hypercritical.Barbee", "Barbee")
    ]

    private var desiredHideState: Bool = true
    private var currentSymbolName: String = "folder.fill"
    private var badgeCount: Int = 0
    private var activeFolderLabel: String? = nil
    private var watchdogTask: Task<Void, Never>?

    var onLeftClick: (() -> Void)?
    var onRightClick: ((NSStatusBarButton) -> Void)?
    var onHoverChanged: ((Bool) -> Void)?
    var onHorizontalSwipe: ((Int) -> Void)?

    // Multi-folder pinned status items (when user pins specific folders to their own menu bar icons)
    var onPinnedFolderLeftClick: ((UUID) -> Void)?
    var onPinnedFolderRightClick: ((UUID, NSStatusBarButton) -> Void)?
    var onPinnedFolderHoverChanged: ((UUID, Bool) -> Void)?

    private var pinnedFolderItems: [UUID: NSStatusItem] = [:]
    private var pinnedButtonToFolderID: [ObjectIdentifier: UUID] = [:]
    private var lastKnownPinnedFrames: [UUID: CGRect] = [:]

    private weak var activeHoverView: StatusButtonHoverView?
    private var horizontalSwipeAccumulator: CGFloat = 0
    private var lastHorizontalSwipeTime: Date = .distantPast
    private var lastKnownFolderScreenFrame: CGRect?

    private var folderStatusItem: NSStatusItem? {
        folderIsSlotA ? slotA : slotB
    }

    private var hiderStatusItem: NSStatusItem? {
        folderIsSlotA ? slotB : slotA
    }

    private var folderAutosaveName: String {
        folderIsSlotA ? Self.slotAName : Self.slotBName
    }

    private var hiderAutosaveName: String {
        folderIsSlotA ? Self.slotBName : Self.slotAName
    }

    func setup(symbolName: String, hideIcons: Bool) {
        self.currentSymbolName = symbolName
        self.desiredHideState = hideIcons

        // Persist preferred positions near the right edge of the menu bar (distance from right edge).
        // Smaller value = further RIGHT (visible outside MacBook notch & right of other hiders).
        let defaults = UserDefaults.standard
        let keyA = "NSStatusItem Preferred Position \(Self.slotAName)"
        let keyB = "NSStatusItem Preferred Position \(Self.slotBName)"
        if defaults.object(forKey: keyA) == nil {
            defaults.set(220.0, forKey: keyA)
        }
        if defaults.object(forKey: keyB) == nil {
            defaults.set(252.0, forKey: keyB)
        }
        defaults.synchronize()

        createStatusItems()

        // Let WindowServer lay out both items first, then verify which is actually rightmost before hiding.
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 300_000_000)
            guard let self else { return }
            self.reconcileRoleOrder()
            self.applyHidingState(hide: self.desiredHideState)
        }
    }

    private func createStatusItems() {
        if let oldA = slotA { NSStatusBar.system.removeStatusItem(oldA) }
        if let oldB = slotB { NSStatusBar.system.removeStatusItem(oldB) }

        let itemA = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        itemA.autosaveName = Self.slotAName
        itemA.isVisible = true

        let itemB = NSStatusBar.system.statusItem(withLength: 1)
        itemB.autosaveName = Self.slotBName
        itemB.isVisible = true

        self.slotA = itemA
        self.slotB = itemB
        self.folderIsSlotA = true

        configureRoles()
    }

    /// Detects another running menu bar manager (e.g. Hidden Bar, Ice, Bartender) that can push Foldie offscreen.
    func detectConflictingMenuBarManager() -> NSRunningApplication? {
        let running = NSWorkspace.shared.runningApplications
        for entry in Self.conflictingManagerBundleIDs {
            if let app = running.first(where: { $0.bundleIdentifier == entry.bundleID }) {
                return app
            }
        }
        return nil
    }

    /// Terminates a conflicting menu bar manager (like Hidden Bar) and re-anchors Foldie on the visible right side.
    func quitConflictingManagerAndReveal() {
        if let conflict = detectConflictingMenuBarManager() {
            conflict.terminate()
        }

        // Reset Foldie's saved positions right next to Control Center so it pops straight into view
        let defaults = UserDefaults.standard
        defaults.set(220.0, forKey: "NSStatusItem Preferred Position \(Self.slotAName)")
        defaults.set(252.0, forKey: "NSStatusItem Preferred Position \(Self.slotBName)")
        defaults.synchronize()

        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 450_000_000)
            guard let self else { return }
            self.createStatusItems()
            try? await Task.sleep(nanoseconds: 250_000_000)
            self.reconcileRoleOrder()
            self.updateFolderVisibilityStatus()
            self.pulseHighlight()
        }
    }

    func updateSymbol(_ symbolName: String) {
        currentSymbolName = symbolName
        configureRoles()
    }

    func updateBadgeCount(_ count: Int) {
        badgeCount = count
        updateFolderButtonVisuals()
    }

    func updateAppearance(symbolName: String, count: Int, label: String?) {
        currentSymbolName = symbolName
        badgeCount = count
        activeFolderLabel = label
        updateFolderButtonVisuals()
    }

    func processHorizontalScrollEvent(_ event: NSEvent) {
        // Ignore inertial momentum so one two-finger flick advances exactly one folder cleanly
        guard event.momentumPhase == [] else { return }
        guard abs(event.scrollingDeltaX) > abs(event.scrollingDeltaY) * 1.15 else { return }

        let now = Date()
        if now.timeIntervalSince(lastHorizontalSwipeTime) < 0.24 {
            horizontalSwipeAccumulator = 0
            return
        }

        horizontalSwipeAccumulator += event.scrollingDeltaX
        let threshold: CGFloat = event.hasPreciseScrollingDeltas ? 18.0 : 0.8
        if abs(horizontalSwipeAccumulator) >= threshold {
            let step = horizontalSwipeAccumulator < 0 ? 1 : -1
            horizontalSwipeAccumulator = 0
            lastHorizontalSwipeTime = now
            onHorizontalSwipe?(step)
        }
    }

    func setDesiredHideIcons(_ hide: Bool) {
        desiredHideState = hide
        isTemporarilyRevealed = false
        reconcileRoleOrder()
        applyHidingState(hide: hide)
    }

    func setTemporarilyRevealed(_ revealed: Bool) {
        isTemporarilyRevealed = revealed
        if revealed {
            applyHidingState(hide: false)
        } else {
            reconcileRoleOrder()
            applyHidingState(hide: desiredHideState)
        }
    }

    /// Checks live X positions of slotA and slotB and ensures the rightmost item is ALWAYS the folder button.
    func reconcileRoleOrder() {
        let frameA = liveFrame(forAutosaveName: Self.slotAName, item: slotA)
        let frameB = liveFrame(forAutosaveName: Self.slotBName, item: slotB)

        if let frameA, let frameB, abs(frameA.origin.x - frameB.origin.x) > 1 {
            let shouldABeFolder = frameA.origin.x > frameB.origin.x
            if shouldABeFolder != folderIsSlotA {
                // Collapse old hider before swapping roles so neither item stays stuck at 10_000
                hiderStatusItem?.length = 1
                folderIsSlotA = shouldABeFolder
                configureRoles()
            }
        }
        updateFolderVisibilityStatus()
    }

    private func configureRoles() {
        activeHoverView?.removeFromSuperview()
        activeHoverView = nil

        if let folderItem = folderStatusItem {
            folderItem.isVisible = true
            folderItem.length = NSStatusItem.variableLength
            if let button = folderItem.button {
                button.isEnabled = true
                button.target = self
                button.action = #selector(handleStatusButtonClick(_:))
                button.sendAction(on: [.leftMouseUp, .rightMouseUp])

                // Attach hover detector overlay so hovering over Foldie opens the menu smoothly
                let hoverView = StatusButtonHoverView(frame: button.bounds)
                hoverView.autoresizingMask = [.width, .height]
                hoverView.onHoverChanged = { [weak self] hovering in
                    if hovering {
                        self?.captureAnchorFromCurrentPointer()
                    }
                    self?.onHoverChanged?(hovering)
                }
                hoverView.onScrollWheel = { [weak self] event in
                    self?.processHorizontalScrollEvent(event)
                }
                button.addSubview(hoverView)
                activeHoverView = hoverView
            }
            updateFolderButtonVisuals()
        }

        if let hiderItem = hiderStatusItem {
            hiderItem.isVisible = true
            if let hiderButton = hiderItem.button {
                hiderButton.target = nil
                hiderButton.action = nil
                hiderButton.image = nil
                hiderButton.title = ""
                hiderButton.attributedTitle = NSAttributedString(string: "")
                hiderButton.isEnabled = false
                hiderButton.appearsDisabled = false
            }
        }
    }

    private func updateFolderButtonVisuals() {
        guard let folderItem = folderStatusItem, let button = folderItem.button else { return }
        folderItem.length = NSStatusItem.variableLength

        let config = NSImage.SymbolConfiguration(pointSize: 13.5, weight: .medium)
        if let image = NSImage(systemSymbolName: currentSymbolName, accessibilityDescription: "Foldie")?
            .withSymbolConfiguration(config) {
            image.isTemplate = true
            button.image = image
            button.imagePosition = badgeCount > 0 ? .imageLeading : .imageOnly
        } else {
            button.image = nil
        }

        if let folderLabel = activeFolderLabel, !folderLabel.isEmpty {
            let shortLabel = folderLabel.count > 10 ? String(folderLabel.prefix(9)) + "…" : folderLabel
            let text = badgeCount > 0 ? " \(shortLabel) \(badgeCount)" : " \(shortLabel)"
            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.monospacedDigitSystemFont(ofSize: 11.5, weight: .semibold),
                .baselineOffset: 0.5
            ]
            button.attributedTitle = NSAttributedString(string: text, attributes: attrs)
            button.toolTip = "Foldie — папка «\(folderLabel)» (\(badgeCount)). Свайп влево/вправо для смены папки."
        } else if badgeCount > 0 {
            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.monospacedDigitSystemFont(ofSize: 11.5, weight: .semibold),
                .baselineOffset: 0.5
            ]
            button.attributedTitle = NSAttributedString(string: " \(badgeCount)", attributes: attrs)
            button.toolTip = "Foldie — приложений в папке: \(badgeCount). Свайп влево/вправо для смены папки."
        } else {
            button.attributedTitle = NSAttributedString(string: "")
            button.title = ""
            button.toolTip = "Foldie — папка иконок строки меню"
        }
    }

    private func applyHidingState(hide: Bool) {
        watchdogTask?.cancel()
        guard let hiderItem = hiderStatusItem else { return }

        if hide {
            hiderItem.isVisible = true
            hiderItem.length = 10_000
            isCurrentlyHiding = true

            // Safety watchdog: verify our own folder icon was NOT pushed offscreen!
            // If it vanished (e.g., macOS placed hider to the right of folder), immediately swap roles and retry.
            watchdogTask = Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: 180_000_000)
                guard !Task.isCancelled, let self else { return }
                if !self.checkIfFolderIsOnscreen() {
                    hiderItem.length = 1
                    self.isCurrentlyHiding = false
                    try? await Task.sleep(nanoseconds: 120_000_000)
                    guard !Task.isCancelled else { return }
                    self.folderIsSlotA.toggle()
                    self.configureRoles()
                    if let newHider = self.hiderStatusItem {
                        newHider.length = 10_000
                        self.isCurrentlyHiding = true
                        try? await Task.sleep(nanoseconds: 180_000_000)
                        if !self.checkIfFolderIsOnscreen() {
                            // Still offscreen (e.g. menu bar completely full behind notch): don't hide ourselves.
                            newHider.length = 1
                            self.isCurrentlyHiding = false
                        }
                    }
                }
                self.updateFolderVisibilityStatus()
            }
        } else {
            hiderItem.length = 1
            isCurrentlyHiding = false
            updateFolderVisibilityStatus()
        }
    }

    /// Programmatically moves Foldie's folder icon to the right side of the menu bar (using Command-Drag)
    /// and engages hiding so all third-party menu bar icons tuck neatly inside Foldie in one click.
    func autoCollectAllIcons() async -> AutoCollectResult {
        // First collapse hider so all status items return to their real onscreen coordinates.
        applyHidingState(hide: false)
        try? await Task.sleep(nanoseconds: 220_000_000)
        reconcileRoleOrder()

        guard AXIsProcessTrusted() else {
            // Without Accessibility, we can still engage hiding right where Foldie sits.
            desiredHideState = true
            applyHidingState(hide: true)
            return AutoCollectResult(
                success: false,
                message: "Выдайте Универсальный доступ, чтобы Foldie мог автоматически переместиться вправо и собрать все иконки."
            )
        }

        let mainScreenWidth = NSScreen.main?.frame.width ?? 1440

        // Find where the macOS Control Center / Clock system cluster begins on the right,
        // so we can place Foldie right next to it (just to the left of Control Center).
        let targetRightX = computeIdealFolderTargetX(screenWidth: mainScreenWidth)

        // Move folder item to the right edge if it's currently sitting too far left
        if let folderFrame = liveFrame(forAutosaveName: folderAutosaveName, item: folderStatusItem),
           folderFrame.origin.x > 0,
           folderFrame.origin.x < targetRightX - 36 {
            await performCommandDrag(
                from: CGPoint(x: folderFrame.midX, y: max(12, folderFrame.midY)),
                to: CGPoint(x: targetRightX, y: max(12, folderFrame.midY))
            )
            try? await Task.sleep(nanoseconds: 220_000_000)
        }

        // Move hider spacer just to the left of folder item
        if let updatedFolder = liveFrame(forAutosaveName: folderAutosaveName, item: folderStatusItem),
           let hiderFrame = liveFrame(forAutosaveName: hiderAutosaveName, item: hiderStatusItem),
           hiderFrame.origin.x > 0 {
            let desiredHiderX = max(40, updatedFolder.minX - 18)
            if abs(hiderFrame.midX - desiredHiderX) > 28 || hiderFrame.origin.x >= updatedFolder.origin.x {
                await performCommandDrag(
                    from: CGPoint(x: hiderFrame.midX, y: max(12, hiderFrame.midY)),
                    to: CGPoint(x: desiredHiderX, y: max(12, updatedFolder.midY))
                )
                try? await Task.sleep(nanoseconds: 220_000_000)
            }
        }

        reconcileRoleOrder()
        desiredHideState = true
        applyHidingState(hide: true)
        try? await Task.sleep(nanoseconds: 240_000_000)
        updateFolderVisibilityStatus()

        if isCurrentlyHiding {
            return AutoCollectResult(
                success: true,
                message: "Готово! Иконки собраны в папку Foldie."
            )
        } else {
            return AutoCollectResult(
                success: false,
                message: "Перетащите иконку Foldie с зажатой ⌘ правее других иконок в строке меню, затем включите скрытие."
            )
        }
    }

    private func computeIdealFolderTargetX(screenWidth: CGFloat) -> CGFloat {
        let statusLevel = Int(CGWindowLevelForKey(.statusWindow))
        guard let rawList = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] else {
            return screenWidth - 220
        }

        // Look for ControlCenter BentoBox / Clock / WiFi on the right edge to place Foldie right next to them.
        var systemLeftEdge: CGFloat = screenWidth - 180
        let systemAnchors: Set<String> = ["Clock", "BentoBox-0", "BentoBox", "WiFi", "Battery"]
        for dict in rawList {
            guard let layerNum = dict[kCGWindowLayer as String] as? NSNumber,
                  layerNum.intValue == statusLevel,
                  let title = dict[kCGWindowName as String] as? String,
                  systemAnchors.contains(title),
                  let boundsDict = dict[kCGWindowBounds as String] as? NSDictionary,
                  let frame = CGRect(dictionaryRepresentation: boundsDict),
                  frame.origin.x > screenWidth * 0.5 else {
                continue
            }
            systemLeftEdge = min(systemLeftEdge, frame.minX)
        }

        return max(screenWidth * 0.55, systemLeftEdge - 14)
    }

    private func performCommandDrag(from start: CGPoint, to end: CGPoint) async {
        guard let source = CGEventSource(stateID: .hidSystemState) else { return }
        let originalLocation = CGEvent(source: nil)?.location

        if let move = CGEvent(mouseEventSource: source, mouseType: .mouseMoved, mouseCursorPosition: start, mouseButton: .left) {
            move.post(tap: .cghidEventTap)
        }
        try? await Task.sleep(nanoseconds: 35_000_000)

        if let down = CGEvent(mouseEventSource: source, mouseType: .leftMouseDown, mouseCursorPosition: start, mouseButton: .left) {
            down.flags = .maskCommand
            down.post(tap: .cghidEventTap)
        }
        try? await Task.sleep(nanoseconds: 50_000_000)

        let steps = 10
        for step in 1...steps {
            let t = CGFloat(step) / CGFloat(steps)
            let pt = CGPoint(
                x: start.x + (end.x - start.x) * t,
                y: start.y + (end.y - start.y) * t
            )
            if let drag = CGEvent(mouseEventSource: source, mouseType: .leftMouseDragged, mouseCursorPosition: pt, mouseButton: .left) {
                drag.flags = .maskCommand
                drag.post(tap: .cghidEventTap)
            }
            try? await Task.sleep(nanoseconds: 14_000_000)
        }

        if let up = CGEvent(mouseEventSource: source, mouseType: .leftMouseUp, mouseCursorPosition: end, mouseButton: .left) {
            up.flags = .maskCommand
            up.post(tap: .cghidEventTap)
        }

        if let originalLocation {
            try? await Task.sleep(nanoseconds: 50_000_000)
            if let restore = CGEvent(mouseEventSource: source, mouseType: .mouseMoved, mouseCursorPosition: originalLocation, mouseButton: .left) {
                restore.post(tap: .cghidEventTap)
            }
        }
    }

    /// Locates the CG-coordinate CGRect of one of our status items (supports both classic AppKit and macOS 26 ControlCenter hosting).
    private func liveFrame(forAutosaveName name: String, item: NSStatusItem?) -> CGRect? {
        let statusLevel = Int(CGWindowLevelForKey(.statusWindow))
        if let rawList = CGWindowListCopyWindowInfo([.optionAll], kCGNullWindowID) as? [[String: Any]] {
            for dict in rawList {
                guard let layerNum = dict[kCGWindowLayer as String] as? NSNumber,
                      layerNum.intValue == statusLevel,
                      let title = dict[kCGWindowName as String] as? String,
                      title == name,
                      let boundsDict = dict[kCGWindowBounds as String] as? NSDictionary,
                      let frame = CGRect(dictionaryRepresentation: boundsDict) else {
                    continue
                }
                return frame
            }
        }

        // Fallback to AppKit window frame converted to CG top-left coordinates
        if let window = item?.button?.window {
            let appKitFrame = window.frame
            let screenHeight = NSScreen.screens.first?.frame.height ?? 900
            return CGRect(
                x: appKitFrame.origin.x,
                y: screenHeight - appKitFrame.maxY,
                width: appKitFrame.width,
                height: appKitFrame.height
            )
        }
        return nil
    }

    private func checkIfFolderIsOnscreen() -> Bool {
        // On a MacBook with a notch, the visible right menu bar starts at auxiliaryTopRightArea.minX (e.g. 960).
        let minVisibleX: CGFloat = (NSScreen.main?.auxiliaryTopRightArea?.minX ?? 20) - 4

        if let frame = liveFrame(forAutosaveName: folderAutosaveName, item: folderStatusItem) {
            return frame.origin.x >= minVisibleX && frame.width >= 10
        }
        if let winFrame = folderStatusItem?.button?.window?.frame {
            return winFrame.origin.x >= minVisibleX && winFrame.width >= 10
        }
        return true
    }

    func updateFolderVisibilityStatus() {
        let onscreen = checkIfFolderIsOnscreen()
        isFolderVisibleOnscreen = onscreen

        if let conflict = detectConflictingMenuBarManager() {
            conflictingAppName = conflict.localizedName ?? "Другой менеджер меню"
        } else {
            conflictingAppName = nil
        }

        // Also detect if any external giant spacer window (> 500pt wide) is active in the menu bar
        let hasExternalSpacer = detectExternalMenuBarSpacer()
        isHiddenBehindNotchOrOtherApp = !onscreen || hasExternalSpacer
    }

    private func detectExternalMenuBarSpacer() -> Bool {
        guard !isCurrentlyHiding else { return false }
        let statusLevel = Int(CGWindowLevelForKey(.statusWindow))
        guard let rawList = CGWindowListCopyWindowInfo([.optionAll], kCGNullWindowID) as? [[String: Any]] else {
            return false
        }
        for dict in rawList {
            guard let layerNum = dict[kCGWindowLayer as String] as? NSNumber,
                  layerNum.intValue == statusLevel,
                  let boundsDict = dict[kCGWindowBounds as String] as? NSDictionary,
                  let frame = CGRect(dictionaryRepresentation: boundsDict) else {
                continue
            }
            if frame.width > 500 && frame.height >= 16 && frame.height <= 64 {
                return true
            }
        }
        return false
    }

    /// Synchronizes dedicated menu bar status items for every folder with `showInMenuBar == true`.
    func syncPinnedFolderItems(
        folders: [FoldieFolder],
        counts: [UUID: Int],
        iconStyle: IconStyle
    ) {
        let pinnedFolders = folders.filter { $0.showInMenuBar }
        let wantedIDs = Set(pinnedFolders.map(\.id))

        // Remove status items for folders that were unpinned or deleted
        for (id, item) in pinnedFolderItems where !wantedIDs.contains(id) {
            if let btn = item.button {
                pinnedButtonToFolderID.removeValue(forKey: ObjectIdentifier(btn))
            }
            NSStatusBar.system.removeStatusItem(item)
            pinnedFolderItems.removeValue(forKey: id)
            lastKnownPinnedFrames.removeValue(forKey: id)
        }

        // Create or update each pinned folder status item
        let defaults = UserDefaults.standard
        for (idx, folder) in pinnedFolders.enumerated() {
            let autosave = "com.foldie.app.folder.\(folder.id.uuidString)"
            let statusItem: NSStatusItem
            if let existing = pinnedFolderItems[folder.id] {
                statusItem = existing
            } else {
                let prefKey = "NSStatusItem Preferred Position \(autosave)"
                if defaults.object(forKey: prefKey) == nil {
                    // Place pinned folders cleanly on the right side next to Foldie (right of hider spacer!)
                    defaults.set(max(120.0, 210.0 - Double(idx + 1) * 32.0), forKey: prefKey)
                    defaults.synchronize()
                }
                let created = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
                created.autosaveName = autosave
                created.isVisible = true
                pinnedFolderItems[folder.id] = created
                statusItem = created
            }

            statusItem.isVisible = true
            statusItem.length = NSStatusItem.variableLength

            if let button = statusItem.button {
                pinnedButtonToFolderID[ObjectIdentifier(button)] = folder.id
                button.isEnabled = true
                button.target = self
                button.action = #selector(handlePinnedFolderClick(_:))
                button.sendAction(on: [.leftMouseUp, .rightMouseUp])

                // Render custom SF Symbol with folder's custom color (or crisp monochrome template)
                let baseConfig = NSImage.SymbolConfiguration(pointSize: 13.5, weight: .semibold)
                let image: NSImage?
                if iconStyle == .color {
                    let paletteConfig = baseConfig.applying(.init(paletteColors: [folder.nsAccentColor]))
                    let colored = NSImage(systemSymbolName: folder.symbolName, accessibilityDescription: folder.name)?
                        .withSymbolConfiguration(paletteConfig)
                    colored?.isTemplate = false
                    image = colored
                } else {
                    let mono = NSImage(systemSymbolName: folder.symbolName, accessibilityDescription: folder.name)?
                        .withSymbolConfiguration(baseConfig)
                    mono?.isTemplate = true
                    image = mono
                }

                let count = counts[folder.id] ?? 0
                button.image = image
                button.imagePosition = count > 0 ? .imageLeading : .imageOnly

                if count > 0 {
                    let attrs: [NSAttributedString.Key: Any] = [
                        .font: NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .semibold),
                        .baselineOffset: 0.5
                    ]
                    button.attributedTitle = NSAttributedString(string: " \(count)", attributes: attrs)
                } else {
                    button.attributedTitle = NSAttributedString(string: "")
                    button.title = ""
                }
                button.toolTip = "\(folder.name) — приложений: \(count)"

                // Ensure hover tracking view is attached
                let hasHover = button.subviews.contains { $0 is StatusButtonHoverView }
                if !hasHover {
                    let folderID = folder.id
                    let hoverView = StatusButtonHoverView(frame: button.bounds)
                    hoverView.autoresizingMask = [.width, .height]
                    hoverView.onHoverChanged = { [weak self] hovering in
                        if hovering {
                            self?.capturePinnedAnchorFromPointer(folderID: folderID)
                        }
                        self?.onPinnedFolderHoverChanged?(folderID, hovering)
                    }
                    button.addSubview(hoverView)
                }
            }
        }
    }

    func screenFrame(forPinnedFolderID folderID: UUID) -> CGRect? {
        let autosave = "com.foldie.app.folder.\(folderID.uuidString)"
        if let cgFrame = liveFrame(forAutosaveName: autosave, item: pinnedFolderItems[folderID]),
           cgFrame.origin.x > 10, cgFrame.width >= 10 {
            let primaryHeight = NSScreen.screens.first?.frame.height ?? 900
            let rect = CGRect(
                x: cgFrame.origin.x,
                y: primaryHeight - cgFrame.maxY,
                width: cgFrame.width,
                height: cgFrame.height
            )
            lastKnownPinnedFrames[folderID] = rect
            return rect
        }
        if let button = pinnedFolderItems[folderID]?.button,
           let window = button.window {
            let frameInWindow = button.convert(button.bounds, to: nil)
            let screenRect = window.convertToScreen(frameInWindow)
            if screenRect.origin.x > 10 && screenRect.origin.y > 200 {
                lastKnownPinnedFrames[folderID] = screenRect
                return screenRect
            }
        }
        return lastKnownPinnedFrames[folderID]
    }

    /// Checks whether a given screen point is currently hovering any pinned folder status item.
    func pinnedFolderID(at screenPoint: NSPoint) -> UUID? {
        for folderID in pinnedFolderItems.keys {
            if let rect = screenFrame(forPinnedFolderID: folderID),
               rect.insetBy(dx: -3, dy: -4).contains(screenPoint) {
                return folderID
            }
        }
        return nil
    }

    private func capturePinnedAnchorFromPointer(folderID: UUID) {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main
        guard let screen else { return }
        let menuBarHeight = max(24, screen.frame.maxY - screen.visibleFrame.maxY)
        if mouse.y >= screen.visibleFrame.maxY - 6 {
            lastKnownPinnedFrames[folderID] = CGRect(
                x: mouse.x - 18,
                y: screen.visibleFrame.maxY,
                width: 36,
                height: menuBarHeight
            )
        }
    }

    @objc private func handlePinnedFolderClick(_ sender: NSStatusBarButton) {
        guard let folderID = pinnedButtonToFolderID[ObjectIdentifier(sender)] else { return }
        capturePinnedAnchorFromPointer(folderID: folderID)
        guard let event = NSApp.currentEvent else {
            onPinnedFolderLeftClick?(folderID)
            return
        }
        if event.type == .rightMouseUp || event.modifierFlags.contains(.control) {
            onPinnedFolderRightClick?(folderID, sender)
        } else {
            onPinnedFolderLeftClick?(folderID)
        }
    }

    /// Returns CGWindowIDs belonging to Foldie's own status items so discovery filters them out.
    var ownStatusWindowIDs: Set<CGWindowID> {
        var ids = Set<CGWindowID>()
        let allItems: [NSStatusItem?] = [slotA, slotB] + Array(pinnedFolderItems.values)
        for item in allItems {
            if let winNum = item?.button?.window?.windowNumber,
               let cgID = CGWindowID(exactly: winNum),
               cgID > 0 {
                ids.insert(cgID)
            }
        }
        return ids
    }

    private func captureAnchorFromCurrentPointer() {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main
        guard let screen else { return }
        let menuBarHeight = max(24, screen.frame.maxY - screen.visibleFrame.maxY)
        if mouse.y >= screen.visibleFrame.maxY - 6 {
            lastKnownFolderScreenFrame = CGRect(
                x: mouse.x - 22,
                y: screen.visibleFrame.maxY,
                width: 44,
                height: menuBarHeight
            )
        }
    }

    /// Returns the screen frame (AppKit bottom-left coordinates) of the Foldie folder button.
    var folderButtonScreenFrame: CGRect? {
        if let cgFrame = liveFrame(forAutosaveName: folderAutosaveName, item: folderStatusItem),
           cgFrame.origin.x > 10, cgFrame.width >= 10 {
            let primaryHeight = NSScreen.screens.first?.frame.height ?? 900
            let rect = CGRect(
                x: cgFrame.origin.x,
                y: primaryHeight - cgFrame.maxY,
                width: cgFrame.width,
                height: cgFrame.height
            )
            lastKnownFolderScreenFrame = rect
            return rect
        }
        if let button = folderStatusItem?.button,
           let window = button.window {
            let frameInWindow = button.convert(button.bounds, to: nil)
            let screenRect = window.convertToScreen(frameInWindow)
            if screenRect.origin.x > 10 && screenRect.origin.y > 200 {
                lastKnownFolderScreenFrame = screenRect
                return screenRect
            }
        }
        return lastKnownFolderScreenFrame
    }

    /// Returns true if the hider spacer is somehow positioned to the right of the folder icon.
    var isHiderMisordered: Bool {
        guard let folderFrame = liveFrame(forAutosaveName: folderAutosaveName, item: folderStatusItem),
              let hiderFrame = liveFrame(forAutosaveName: hiderAutosaveName, item: hiderStatusItem) else {
            return false
        }
        return hiderFrame.origin.x > folderFrame.origin.x + 2
    }

    /// Briefly highlights Foldie's status bar button so the user can easily spot it during onboarding.
    func pulseHighlight() {
        guard let button = folderStatusItem?.button else { return }
        Task { @MainActor in
            for _ in 0..<4 {
                button.highlight(true)
                try? await Task.sleep(nanoseconds: 220_000_000)
                button.highlight(false)
                try? await Task.sleep(nanoseconds: 160_000_000)
            }
        }
    }

    @objc private func handleStatusButtonClick(_ sender: NSStatusBarButton) {
        captureAnchorFromCurrentPointer()
        guard let event = NSApp.currentEvent else {
            onLeftClick?()
            return
        }
        if event.type == .rightMouseUp || event.modifierFlags.contains(.control) {
            onRightClick?(sender)
        } else {
            onLeftClick?()
        }
    }
}
