import AppKit
import ApplicationServices
import CoreGraphics
import Foundation

@MainActor
final class PermissionService: ObservableObject {
    @Published private(set) var hasAccessibility: Bool = false
    @Published private(set) var hasScreenRecording: Bool = false
    @Published private(set) var hasVerifiedLiveWindowNames: Bool = false

    private var didPromptAccessibilityThisSession: Bool = false
    private var didPromptScreenRecordingThisSession: Bool = false
    private let ownPID: pid_t = ProcessInfo.processInfo.processIdentifier

    init() {
        refresh()
    }

    /// Passively checks current permission state WITHOUT triggering any macOS system popup.
    func refresh() {
        hasAccessibility = AXIsProcessTrusted()
        let preflight = CGPreflightScreenCaptureAccess()
        let liveNames = probeOtherProcessWindowNames()
        hasVerifiedLiveWindowNames = liveNames
        // Consider Screen Recording truly active when preflight passes OR macOS actually exposes other-app window names.
        hasScreenRecording = preflight || liveNames
    }

    /// True only when both preflight AND actual window metadata confirm macOS accepts this build's signature.
    var isScreenCaptureKitSafeToCall: Bool {
        CGPreflightScreenCaptureAccess() && hasVerifiedLiveWindowNames
    }

    /// Checks passively whether macOS exposes non-empty kCGWindowName on other processes (never prompts).
    private func probeOtherProcessWindowNames() -> Bool {
        guard let rawList = CGWindowListCopyWindowInfo([.optionAll], kCGNullWindowID) as? [[String: Any]] else {
            return false
        }
        for dict in rawList {
            guard let pidNum = dict[kCGWindowOwnerPID as String] as? NSNumber,
                  pid_t(pidNum.int32Value) != ownPID else {
                continue
            }
            if let name = dict[kCGWindowName as String] as? String,
               !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return true
            }
        }
        return false
    }

    /// Requests Accessibility permission cleanly without immediately stealing focus from the system prompt.
    func requestAccessibilityIfNeeded() {
        refresh()
        guard !hasAccessibility else { return }

        if !didPromptAccessibilityThisSession {
            didPromptAccessibilityThisSession = true
            let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
            _ = AXIsProcessTrustedWithOptions(options)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
                self?.openAccessibilitySettings()
                self?.refresh()
            }
        } else {
            openAccessibilitySettings()
        }
    }

    /// Resets any stale ad-hoc TCC Accessibility entry for Foldie and re-prompts cleanly.
    func resetStaleAccessibilityAndRequest() {
        let bundleID = Bundle.main.bundleIdentifier ?? "com.foldie.app"
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/tccutil")
        process.arguments = ["reset", "Accessibility", bundleID]
        try? process.run()
        process.waitUntilExit()

        didPromptAccessibilityThisSession = false
        requestAccessibilityIfNeeded()
    }

    /// Requests Screen Recording permission only if not already granted; avoids spamming system popups.
    func requestScreenRecordingIfNeeded() {
        refresh()
        guard !hasScreenRecording else { return }

        if !didPromptScreenRecordingThisSession {
            didPromptScreenRecordingThisSession = true
            _ = CGRequestScreenCaptureAccess()
        }
        openScreenRecordingSettings()

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
            self?.refresh()
        }
    }

    func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    func openScreenRecordingSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
            NSWorkspace.shared.open(url)
        }
    }

    /// Opens macOS System Settings -> Menu Bar ("Разрешить в строке меню" on macOS 26 / Control Center on macOS 14–15).
    func openMenuBarSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.ControlCenter-Settings.extension") {
            NSWorkspace.shared.open(url)
        }
    }
}
