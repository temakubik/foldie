import AppKit
import SwiftUI

private final class FoldiePanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

@MainActor
final class FloatingPanelController: NSObject {
    private var panel: FoldiePanel?
    private var globalMouseDownMonitor: Any?
    private var globalMouseMovedMonitor: Any?
    private var globalScrollMonitor: Any?
    private var localScrollMonitor: Any?
    private var localMouseMovedMonitor: Any?
    private var localKeyMonitor: Any?

    private var hoverOpenTask: Task<Void, Never>?
    private var hoverCloseTask: Task<Void, Never>?
    private var openedByHover: Bool = false
    private var isPointerOverStatusButton: Bool = false
    private var hoveredPinnedFolderID: UUID? = nil
    private var activeAnchorFolderID: UUID? = nil

    private let store: FoldieStore

    private let panelWidth: CGFloat = 214
    private var currentPanelHeight: CGFloat {
        store.config.preferences.displayMode == .cylinder ? 236 : 292
    }

    init(store: FoldieStore) {
        self.store = store
        super.init()
        installGlobalHoverMonitor()
    }

    var isVisible: Bool {
        panel?.isVisible ?? false
    }

    /// Called when the user explicitly clicks Foldie's main menu bar icon.
    func toggle(anchorRect: CGRect?) {
        hoverOpenTask?.cancel()
        hoverCloseTask?.cancel()
        if isVisible && !openedByHover && activeAnchorFolderID == nil {
            close()
        } else {
            openedByHover = false
            activeAnchorFolderID = nil
            store.setActivePopupFolder(store.swipedFolderID)
            open(anchorRect: anchorRect)
        }
    }

    /// Called when the user explicitly clicks one of the pinned folder status bar icons.
    func togglePinnedFolder(_ folderID: UUID, anchorRect: CGRect?) {
        hoverOpenTask?.cancel()
        hoverCloseTask?.cancel()
        if isVisible && !openedByHover && activeAnchorFolderID == folderID {
            close()
        } else {
            openedByHover = false
            activeAnchorFolderID = folderID
            store.setActivePopupFolder(folderID)
            open(anchorRect: anchorRect)
        }
    }

    /// Called by NSTrackingArea on the main Foldie status button.
    func handleStatusButtonHover(_ hovering: Bool) {
        isPointerOverStatusButton = hovering
        if hovering {
            hoveredPinnedFolderID = nil
        }
        evaluateHoverState(mouseLocation: NSEvent.mouseLocation)
    }

    /// Called by NSTrackingArea on any pinned folder status bar icon.
    func handlePinnedFolderHover(_ folderID: UUID, hovering: Bool) {
        if hovering {
            hoveredPinnedFolderID = folderID
            isPointerOverStatusButton = false
        } else if hoveredPinnedFolderID == folderID {
            hoveredPinnedFolderID = nil
        }
        evaluateHoverState(mouseLocation: NSEvent.mouseLocation)
    }

    func open(anchorRect: CGRect?, fromHover: Bool = false) {
        hoverOpenTask?.cancel()
        hoverCloseTask?.cancel()
        if !fromHover {
            openedByHover = false
        }

        store.refreshItems(captureThumbnails: false)

        if panel == nil {
            createPanel()
        }
        guard let panel else { return }

        positionPanel(panel, anchorRect: anchorRect)

        if !panel.isVisible {
            if !fromHover {
                store.sounds.playPop()
            }
            panel.alphaValue = 0
            if fromHover {
                panel.orderFrontRegardless()
            } else {
                panel.makeKeyAndOrderFront(nil)
                NSApp.activate(ignoringOtherApps: true)
            }

            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.14
                ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
                panel.animator().alphaValue = 1
            }
        }

        installActiveDismissMonitors()
    }

    func close() {
        hoverOpenTask?.cancel()
        hoverCloseTask?.cancel()
        openedByHover = false
        removeActiveDismissMonitors()
        guard let panel, panel.isVisible else { return }
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.11
            ctx.timingFunction = CAMediaTimingFunction(name: .easeIn)
            panel.animator().alphaValue = 0
        }, completionHandler: { [weak panel] in
            Task { @MainActor in
                panel?.orderOut(nil)
            }
        })
    }

    // MARK: - Hover Open & Auto-Close

    private func installGlobalHoverMonitor() {
        globalMouseMovedMonitor = NSEvent.addGlobalMonitorForEvents(matching: .mouseMoved) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.evaluateHoverState(mouseLocation: NSEvent.mouseLocation)
            }
        }
        localMouseMovedMonitor = NSEvent.addLocalMonitorForEvents(matching: .mouseMoved) { [weak self] event in
            Task { @MainActor [weak self] in
                self?.evaluateHoverState(mouseLocation: NSEvent.mouseLocation)
            }
            return event
        }
        // Horizontal two-finger swipe directly over Foldie's menu bar area OR over the floating menu switches main folders!
        globalScrollMonitor = NSEvent.addGlobalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            Task { @MainActor [weak self] in
                self?.handlePotentialHorizontalSwipe(event)
            }
        }
        localScrollMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            guard let self else { return event }
            if abs(event.scrollingDeltaX) > abs(event.scrollingDeltaY) * 1.15,
               self.isPointerInSwipeArea(mouse: NSEvent.mouseLocation) {
                self.store.hider.processHorizontalScrollEvent(event)
                return nil
            }
            return event
        }
    }

    private func isPointerInSwipeArea(mouse: NSPoint) -> Bool {
        if isPointerOverStatusButton { return true }
        if let rect = store.hider.folderButtonScreenFrame, rect.insetBy(dx: -24, dy: -10).contains(mouse) {
            return true
        }
        if isVisible, let panelFrame = panel?.frame, panelFrame.insetBy(dx: -8, dy: -8).contains(mouse) {
            return true
        }
        // Fallback right-side menu bar strip (reliable on macOS 26 even before Screen Recording is granted)
        if let screen = NSScreen.screens.first(where: { $0.frame.contains(mouse) }) ?? NSScreen.main {
            if mouse.y >= screen.visibleFrame.maxY - 4 && mouse.x >= screen.frame.midX {
                return true
            }
        }
        return false
    }

    private func handlePotentialHorizontalSwipe(_ event: NSEvent) {
        guard abs(event.scrollingDeltaX) > abs(event.scrollingDeltaY) * 1.15 else { return }
        if isPointerInSwipeArea(mouse: NSEvent.mouseLocation) {
            store.hider.processHorizontalScrollEvent(event)
        }
    }

    private func activeAnchorRect() -> CGRect? {
        if let pinnedID = activeAnchorFolderID {
            return store.hider.screenFrame(forPinnedFolderID: pinnedID)
        }
        return store.hider.folderButtonScreenFrame
    }

    private func evaluateHoverState(mouseLocation: NSPoint) {
        let hoveredPinned = hoveredPinnedFolderID ?? store.hider.pinnedFolderID(at: mouseLocation)
        let mainRect = store.hider.folderButtonScreenFrame
        let overMainButton = isPointerOverStatusButton
            || (mainRect?.insetBy(dx: -3, dy: -4).contains(mouseLocation) ?? false)

        // If hovering directly over a different pinned folder or main icon while already open -> switch smoothly!
        if isVisible {
            if let pinnedID = hoveredPinned, activeAnchorFolderID != pinnedID {
                hoverCloseTask?.cancel()
                hoverCloseTask = nil
                activeAnchorFolderID = pinnedID
                store.setActivePopupFolder(pinnedID)
                open(anchorRect: store.hider.screenFrame(forPinnedFolderID: pinnedID), fromHover: openedByHover)
                return
            }
            if overMainButton && hoveredPinned == nil && activeAnchorFolderID != nil {
                hoverCloseTask?.cancel()
                hoverCloseTask = nil
                activeAnchorFolderID = nil
                store.setActivePopupFolder(store.swipedFolderID)
                open(anchorRect: mainRect, fromHover: openedByHover)
                return
            }
        }

        if !isVisible {
            if hoveredPinned != nil || overMainButton {
                let targetPinned = hoveredPinned
                guard hoverOpenTask == nil else { return }
                hoverOpenTask = Task { @MainActor [weak self] in
                    try? await Task.sleep(nanoseconds: 110_000_000)
                    guard !Task.isCancelled, let self else { return }
                    self.hoverOpenTask = nil
                    let currentMouse = NSEvent.mouseLocation
                    if let pinnedID = self.hoveredPinnedFolderID ?? self.store.hider.pinnedFolderID(at: currentMouse) ?? targetPinned,
                       (self.hoveredPinnedFolderID == pinnedID || (self.store.hider.screenFrame(forPinnedFolderID: pinnedID)?.insetBy(dx: -4, dy: -4).contains(currentMouse) ?? false)) {
                        self.openedByHover = true
                        self.activeAnchorFolderID = pinnedID
                        self.store.setActivePopupFolder(pinnedID)
                        self.open(anchorRect: self.store.hider.screenFrame(forPinnedFolderID: pinnedID), fromHover: true)
                    } else {
                        let stillMain = self.isPointerOverStatusButton
                            || (self.store.hider.folderButtonScreenFrame?.insetBy(dx: -4, dy: -4).contains(currentMouse) ?? false)
                        if stillMain && !self.isVisible {
                            self.openedByHover = true
                            self.activeAnchorFolderID = nil
                            self.store.setActivePopupFolder(self.store.swipedFolderID)
                            self.open(anchorRect: self.store.hider.folderButtonScreenFrame, fromHover: true)
                        }
                    }
                }
            } else {
                hoverOpenTask?.cancel()
                hoverOpenTask = nil
            }
            return
        }

        // Panel is visible: if opened via hover, smoothly close once cursor leaves active anchor + panel + bridge zone
        guard openedByHover else { return }

        if store.folderEditorState != nil || store.dividerEditorState != nil {
            hoverCloseTask?.cancel()
            hoverCloseTask = nil
            return
        }

        let inSafeZone = isMouseInHoverSafeZone(mouseLocation: mouseLocation, buttonRect: activeAnchorRect())
        if inSafeZone {
            hoverCloseTask?.cancel()
            hoverCloseTask = nil
        } else if hoverCloseTask == nil {
            hoverCloseTask = Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: 340_000_000)
                guard !Task.isCancelled, let self else { return }
                self.hoverCloseTask = nil
                let latestMouse = NSEvent.mouseLocation
                if self.openedByHover && !self.isMouseInHoverSafeZone(
                    mouseLocation: latestMouse,
                    buttonRect: self.activeAnchorRect()
                ) {
                    self.close()
                }
            }
        }
    }

    private func isMouseInHoverSafeZone(mouseLocation: NSPoint, buttonRect: CGRect?) -> Bool {
        if isPointerOverStatusButton { return true }
        if let buttonRect, buttonRect.insetBy(dx: -8, dy: -8).contains(mouseLocation) {
            return true
        }
        guard let panelFrame = panel?.frame else { return false }
        if panelFrame.insetBy(dx: -8, dy: -8).contains(mouseLocation) {
            return true
        }
        // Bridge area between top of panel and bottom of menu bar so moving downward never flickers closed
        if let buttonRect {
            let bridgeMinX = min(panelFrame.minX, buttonRect.minX) - 6
            let bridgeMaxX = max(panelFrame.maxX, buttonRect.maxX) + 6
            let bridgeRect = CGRect(
                x: bridgeMinX,
                y: panelFrame.maxY - 2,
                width: bridgeMaxX - bridgeMinX,
                height: max(18, buttonRect.maxY - panelFrame.maxY + 6)
            )
            if bridgeRect.contains(mouseLocation) {
                return true
            }
        }
        return false
    }

    // MARK: - Panel Setup

    private func createPanel() {
        let height = currentPanelHeight
        let contentRect = NSRect(x: 0, y: 0, width: panelWidth, height: height)
        let panel = FoldiePanel(
            contentRect: contentRect,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        // Completely transparent frameless host — NO outer window box or rectangular shadow!
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .popUpMenu
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.isMovableByWindowBackground = false
        panel.hidesOnDeactivate = false

        let rootView = FoldiePopoverView(store: store)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        let hostingView = NSHostingView(rootView: rootView)
        hostingView.wantsLayer = true
        hostingView.layer?.backgroundColor = NSColor.clear.cgColor
        hostingView.layer?.masksToBounds = false

        panel.contentView = hostingView
        self.panel = panel
    }

    private func positionPanel(_ panel: NSPanel, anchorRect: CGRect?) {
        let height = currentPanelHeight
        let screen = screenContaining(anchorRect) ?? NSScreen.main ?? NSScreen.screens.first
        let visibleFrame = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1280, height: 800)

        var x: CGFloat
        var y: CGFloat

        if let anchor = anchorRect {
            x = anchor.midX - panelWidth / 2
            // Hug tightly right underneath Foldie's menu bar icon (2pt gap)
            y = anchor.minY - height - 2
        } else {
            x = visibleFrame.maxX - panelWidth - 10
            y = visibleFrame.maxY - height - 2
        }

        let margin: CGFloat = 8
        x = min(max(x, visibleFrame.minX + margin), visibleFrame.maxX - panelWidth - margin)
        y = max(y, visibleFrame.minY + margin)

        panel.setFrame(NSRect(x: x, y: y, width: panelWidth, height: height), display: true)
    }

    private func screenContaining(_ rect: CGRect?) -> NSScreen? {
        guard let rect else { return nil }
        let center = CGPoint(x: rect.midX, y: rect.midY)
        return NSScreen.screens.first { $0.frame.contains(center) }
    }

    private func installActiveDismissMonitors() {
        removeActiveDismissMonitors()

        globalMouseDownMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown]
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, let panel = self.panel, panel.isVisible else { return }
                let mouseLocation = NSEvent.mouseLocation
                if panel.frame.contains(mouseLocation) {
                    return
                }
                if let buttonFrame = self.store.hider.folderButtonScreenFrame,
                   buttonFrame.insetBy(dx: -4, dy: -4).contains(mouseLocation) {
                    return
                }
                self.close()
            }
        }

        localKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53 { // Escape
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    if self.store.config.preferences.displayMode == .cylinder && !self.store.cylinderFolderPath.isEmpty {
                        self.store.popCylinderFolder()
                    } else {
                        self.close()
                    }
                }
                return nil
            }
            return event
        }
    }

    private func removeActiveDismissMonitors() {
        if let monitor = globalMouseDownMonitor {
            NSEvent.removeMonitor(monitor)
            globalMouseDownMonitor = nil
        }
        if let monitor = localKeyMonitor {
            NSEvent.removeMonitor(monitor)
            localKeyMonitor = nil
        }
    }
}
