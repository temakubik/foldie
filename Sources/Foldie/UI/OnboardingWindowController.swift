import AppKit
import SwiftUI

@MainActor
final class OnboardingWindowController: NSObject, NSWindowDelegate {
    private var window: NSWindow?
    private let store: FoldieStore
    private let onFinished: (OnboardingFinishDestination) -> Void

    init(store: FoldieStore, onFinished: @escaping (OnboardingFinishDestination) -> Void) {
        self.store = store
        self.onFinished = onFinished
        super.init()
    }

    func show() {
        if let existing = window {
            existing.center()
            existing.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let contentView = OnboardingView(store: store) { [weak self] destination in
            self?.close()
            self?.onFinished(destination)
        }

        let hosting = NSHostingController(rootView: contentView)
        let window = NSWindow(contentViewController: hosting)
        window.title = "Добро пожаловать в Foldie"
        window.styleMask = [.titled, .closable, .fullSizeContentView]
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isMovableByWindowBackground = true
        window.isReleasedWhenClosed = false
        window.level = .floating
        window.delegate = self
        window.setContentSize(NSSize(width: 560, height: 550))
        window.center()

        self.window = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func close() {
        window?.orderOut(nil)
        window = nil
    }

    func windowWillClose(_ notification: Notification) {
        if !store.config.preferences.hasCompletedOnboarding {
            store.completeOnboarding()
        }
        window = nil
    }
}
