import AppKit
import SwiftUI

@MainActor
final class OrganizerWindowController: NSObject, NSWindowDelegate {
    private var window: NSWindow?
    private let store: FoldieStore
    private let onOpenMenuBarPopover: () -> Void

    init(store: FoldieStore, onOpenMenuBarPopover: @escaping () -> Void) {
        self.store = store
        self.onOpenMenuBarPopover = onOpenMenuBarPopover
        super.init()
    }

    func show() {
        if let existing = window {
            existing.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let contentView = OrganizerWindowView(
            store: store,
            onOpenMenuBarPopover: onOpenMenuBarPopover
        )
        let hosting = NSHostingController(rootView: contentView)
        let window = NSWindow(contentViewController: hosting)
        window.title = "Foldie — Настройка и сортировка"
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.setContentSize(NSSize(width: 740, height: 540))
        window.minSize = NSSize(width: 680, height: 480)
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
        window = nil
    }
}
