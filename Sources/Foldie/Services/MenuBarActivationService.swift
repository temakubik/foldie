import AppKit
import ApplicationServices
import CoreGraphics
import Foundation

/// Activates (clicks) a collected menu bar icon by temporarily revealing the menu bar if hidden,
/// triggering the status item via synthetic mouse click or Accessibility AXPress, and auto-rehiding afterward.
@MainActor
final class MenuBarActivationService {
    private let discoveryService: MenuBarDiscoveryService
    private let hiderService: MenuBarHiderService

    private var rehideTask: Task<Void, Never>?
    private var globalClickMonitor: Any?

    init(discoveryService: MenuBarDiscoveryService, hiderService: MenuBarHiderService) {
        self.discoveryService = discoveryService
        self.hiderService = hiderService
    }

    func activate(
        item: MenuBarItem,
        rightClick: Bool = false,
        rehideMode: AutoRehideMode
    ) {
        cancelPendingRehide()

        let wasHiding = hiderService.isCurrentlyHiding
        if wasHiding {
            hiderService.setTemporarilyRevealed(true)
        }

        // Allow WindowServer to lay out the unhidden menu bar items before clicking.
        let revealDelay: UInt64 = wasHiding ? 110_000_000 : 25_000_000

        Task { @MainActor [weak self] in
            guard let self else { return }
            try? await Task.sleep(nanoseconds: revealDelay)

            let liveFrame = self.discoveryService.locateLiveFrame(for: item) ?? item.frame
            let isLikelyVisible = liveFrame.origin.x >= 0 && liveFrame.width >= 4

            var activated = false

            if isLikelyVisible {
                activated = self.performSyntheticClick(at: CGPoint(x: liveFrame.midX, y: liveFrame.midY), rightClick: rightClick)
            }

            if !activated && !rightClick {
                activated = self.performAccessibilityPress(for: item)
            }

            if !activated {
                // Last resort: activate the owning application directly.
                NSRunningApplication(processIdentifier: item.pid)?.activate()
            }

            if wasHiding {
                self.scheduleRehide(mode: rehideMode)
            }
        }
    }

    func cancelPendingRehide() {
        rehideTask?.cancel()
        rehideTask = nil
        if let monitor = globalClickMonitor {
            NSEvent.removeMonitor(monitor)
            globalClickMonitor = nil
        }
    }

    private func scheduleRehide(mode: AutoRehideMode) {
        switch mode {
        case .manual:
            break
        case .after3Seconds:
            rehideTask = Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: 3_000_000_000)
                guard !Task.isCancelled else { return }
                self?.hiderService.setTemporarilyRevealed(false)
            }
        case .after6Seconds:
            rehideTask = Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: 6_000_000_000)
                guard !Task.isCancelled else { return }
                self?.hiderService.setTemporarilyRevealed(false)
            }
        case .onOutsideClick:
            // Wait slightly so the synthetic click itself doesn't immediately trigger rehide,
            // then rehide as soon as the user clicks anywhere outside the top menu bar.
            rehideTask = Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: 450_000_000)
                guard !Task.isCancelled, let self else { return }
                self.globalClickMonitor = NSEvent.addGlobalMonitorForEvents(
                    matching: [.leftMouseDown, .rightMouseDown]
                ) { [weak self] _ in
                    Task { @MainActor [weak self] in
                        // Wait a brief moment so the clicked menu action finishes before hiding.
                        try? await Task.sleep(nanoseconds: 250_000_000)
                        self?.cancelPendingRehide()
                        self?.hiderService.setTemporarilyRevealed(false)
                    }
                }
            }
        }
    }

    /// Posts a synthetic left or right click at the given global CG coordinates and restores cursor position.
    private func performSyntheticClick(at targetPoint: CGPoint, rightClick: Bool) -> Bool {
        guard let source = CGEventSource(stateID: .hidSystemState) else {
            return false
        }

        let originalLocation = CGEvent(source: nil)?.location

        let downType: CGEventType = rightClick ? .rightMouseDown : .leftMouseDown
        let upType: CGEventType = rightClick ? .rightMouseUp : .leftMouseUp
        let button: CGMouseButton = rightClick ? .right : .left

        guard let moveEvent = CGEvent(
            mouseEventSource: source,
            mouseType: .mouseMoved,
            mouseCursorPosition: targetPoint,
            mouseButton: button
        ),
        let downEvent = CGEvent(
            mouseEventSource: source,
            mouseType: downType,
            mouseCursorPosition: targetPoint,
            mouseButton: button
        ),
        let upEvent = CGEvent(
            mouseEventSource: source,
            mouseType: upType,
            mouseCursorPosition: targetPoint,
            mouseButton: button
        ) else {
            return false
        }

        moveEvent.post(tap: .cghidEventTap)
        usleep(12_000)
        downEvent.post(tap: .cghidEventTap)
        usleep(25_000)
        upEvent.post(tap: .cghidEventTap)

        // Smoothly return the pointer to where the user was clicking after the menu opens.
        if let originalLocation {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
                if let restore = CGEvent(
                    mouseEventSource: source,
                    mouseType: .mouseMoved,
                    mouseCursorPosition: originalLocation,
                    mouseButton: .left
                ) {
                    restore.post(tap: .cghidEventTap)
                }
            }
        }

        return true
    }

    /// Fallback Accessibility AXPress on the process's AXExtrasMenuBar item.
    private func performAccessibilityPress(for item: MenuBarItem) -> Bool {
        guard AXIsProcessTrusted() else { return false }
        let appElement = AXUIElementCreateApplication(item.pid)

        var extrasValue: CFTypeRef?
        let status = AXUIElementCopyAttributeValue(appElement, "AXExtrasMenuBar" as CFString, &extrasValue)
        guard status == .success,
              let extrasRef = extrasValue,
              CFGetTypeID(extrasRef) == AXUIElementGetTypeID() else {
            return false
        }
        let extrasBar = unsafeDowncast(extrasRef, to: AXUIElement.self)

        var childrenValue: CFTypeRef?
        let childrenStatus = AXUIElementCopyAttributeValue(extrasBar, kAXChildrenAttribute as CFString, &childrenValue)
        guard childrenStatus == .success, let children = childrenValue as? [AXUIElement], !children.isEmpty else {
            return false
        }

        guard let targetElement = (children.first { element in
            var titleVal: CFTypeRef?
            if AXUIElementCopyAttributeValue(element, kAXTitleAttribute as CFString, &titleVal) == .success,
               let titleStr = titleVal as? String,
               !item.title.isEmpty,
               titleStr.localizedCaseInsensitiveContains(item.title) {
                return true
            }
            var descVal: CFTypeRef?
            if AXUIElementCopyAttributeValue(element, kAXDescriptionAttribute as CFString, &descVal) == .success,
               let descStr = descVal as? String,
               !item.title.isEmpty,
               descStr.localizedCaseInsensitiveContains(item.title) {
                return true
            }
            return false
        } ?? children.first) else {
            return false
        }

        return AXUIElementPerformAction(targetElement, kAXPressAction as CFString) == .success
    }
}
