import AppKit
import SwiftUI

@main
struct FoldieApp: App {
    @NSApplicationDelegateAdaptor(FoldieAppDelegate.self) var appDelegate

    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}

@MainActor
final class FoldieAppDelegate: NSObject, NSApplicationDelegate {
    private var store: FoldieStore?
    private var panelController: FloatingPanelController?
    private var onboardingController: OnboardingWindowController?
    private var organizerController: OrganizerWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Run as a menu bar utility (no Dock clutter)
        NSApp.setActivationPolicy(.accessory)

        let store = FoldieStore()
        let panelController = FloatingPanelController(store: store)
        let organizerController = OrganizerWindowController(store: store) { [weak panelController, weak store] in
            guard let panelController, let store else { return }
            panelController.open(anchorRect: store.hider.folderButtonScreenFrame)
        }
        let onboardingController = OnboardingWindowController(store: store) { [weak panelController, weak organizerController, weak store] destination in
            guard let store else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
                switch destination {
                case .openOrganizer:
                    organizerController?.show()
                case .openPopover:
                    panelController?.open(anchorRect: store.hider.folderButtonScreenFrame)
                }
            }
        }

        self.store = store
        self.panelController = panelController
        self.organizerController = organizerController
        self.onboardingController = onboardingController

        store.onRequestClosePanel = { [weak panelController] in
            panelController?.close()
        }

        store.onRequestShowOnboarding = { [weak onboardingController] in
            onboardingController?.show()
        }

        store.onRequestOpenOrganizer = { [weak organizerController] in
            organizerController?.show()
        }

        store.hider.onLeftClick = { [weak self] in
            guard let self, let store = self.store, let panel = self.panelController else { return }
            panel.toggle(anchorRect: store.hider.folderButtonScreenFrame)
        }

        store.hider.onHoverChanged = { [weak self] hovering in
            self?.panelController?.handleStatusButtonHover(hovering)
        }

        store.hider.onHorizontalSwipe = { [weak store] step in
            store?.cycleSwipedFolder(step: step)
        }

        store.hider.onPinnedFolderLeftClick = { [weak self] folderID in
            guard let self, let store = self.store, let panel = self.panelController else { return }
            panel.togglePinnedFolder(folderID, anchorRect: store.hider.screenFrame(forPinnedFolderID: folderID))
        }

        store.hider.onPinnedFolderHoverChanged = { [weak self] folderID, hovering in
            self?.panelController?.handlePinnedFolderHover(folderID, hovering: hovering)
        }

        store.hider.onPinnedFolderRightClick = { [weak self] _, button in
            self?.showContextMenu(from: button)
        }

        store.hider.onRightClick = { [weak self] button in
            self?.showContextMenu(from: button)
        }

        store.start()

        // Show onboarding automatically on first launch so the user clearly sees what Foldie does
        if !store.config.preferences.hasCompletedOnboarding {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
                onboardingController.show()
            }
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        guard let store else { return true }
        if !store.config.preferences.hasCompletedOnboarding {
            onboardingController?.show()
        } else {
            // Opening Foldie.app from Finder/Spotlight opens the convenient Organizer & Settings window
            organizerController?.show()
        }
        return true
    }

    func applicationWillTerminate(_ notification: Notification) {
        // Restore menu bar icons before quitting so nothing stays hidden
        store?.hider.setDesiredHideIcons(false)
    }

    private func showContextMenu(from button: NSStatusBarButton) {
        guard let store else { return }
        let menu = NSMenu()

        let organizerItem = NSMenuItem(
            title: "Настройки Foldie...",
            action: #selector(menuOpenOrganizer),
            keyEquivalent: ","
        )
        organizerItem.target = self
        menu.addItem(organizerItem)

        menu.addItem(.separator())

        let listModeItem = NSMenuItem(
            title: "Режим: Список с папками",
            action: #selector(menuSwitchToList),
            keyEquivalent: ""
        )
        listModeItem.target = self
        listModeItem.state = store.config.preferences.displayMode == .list ? .on : .off
        menu.addItem(listModeItem)

        let cylinderModeItem = NSMenuItem(
            title: "Режим: 3D-Цилиндр",
            action: #selector(menuSwitchToCylinder),
            keyEquivalent: ""
        )
        cylinderModeItem.target = self
        cylinderModeItem.state = store.config.preferences.displayMode == .cylinder ? .on : .off
        menu.addItem(cylinderModeItem)

        let iconStyleItem = NSMenuItem(
            title: store.config.preferences.iconStyle == .color
                ? "Стиль иконок: переключить на Моно"
                : "Стиль иконок: переключить на Цветные",
            action: #selector(menuToggleIconStyle),
            keyEquivalent: ""
        )
        iconStyleItem.target = self
        menu.addItem(iconStyleItem)

        menu.addItem(.separator())

        let collectItem = NSMenuItem(
            title: "Собрать все иконки в Foldie",
            action: #selector(menuAutoCollect),
            keyEquivalent: ""
        )
        collectItem.target = self
        menu.addItem(collectItem)

        let revealTitle = store.hider.isCurrentlyHiding
            ? "Показать иконки в строке меню"
            : "Скрыть иконки в Foldie"
        let revealItem = NSMenuItem(
            title: revealTitle,
            action: #selector(menuToggleReveal),
            keyEquivalent: ""
        )
        revealItem.target = self
        menu.addItem(revealItem)

        let refreshItem = NSMenuItem(
            title: "Обновить иконки",
            action: #selector(menuRefresh),
            keyEquivalent: ""
        )
        refreshItem.target = self
        menu.addItem(refreshItem)

        let updateTitle: String
        if let release = store.updater.state.availableRelease {
            updateTitle = "Обновить Foldie до v\(release.version)..."
        } else {
            updateTitle = "Проверить обновления..."
        }
        let updateItem = NSMenuItem(
            title: updateTitle,
            action: #selector(menuCheckForUpdates),
            keyEquivalent: ""
        )
        updateItem.target = self
        menu.addItem(updateItem)

        let onboardingItem = NSMenuItem(
            title: "Показать онбординг...",
            action: #selector(menuShowOnboarding),
            keyEquivalent: ""
        )
        onboardingItem.target = self
        menu.addItem(onboardingItem)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(
            title: "Выйти из Foldie",
            action: #selector(menuQuit),
            keyEquivalent: "q"
        )
        quitItem.target = self
        menu.addItem(quitItem)

        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: button.bounds.height + 4), in: button)
    }

    @objc private func menuOpenFoldie() {
        guard let store else { return }
        panelController?.open(anchorRect: store.hider.folderButtonScreenFrame)
    }

    @objc private func menuOpenOrganizer() {
        panelController?.close()
        organizerController?.show()
    }

    @objc private func menuSwitchToList() {
        guard let store else { return }
        store.setDisplayMode(.list)
        store.isShowingSettings = false
        panelController?.open(anchorRect: store.hider.folderButtonScreenFrame)
    }

    @objc private func menuSwitchToCylinder() {
        guard let store else { return }
        store.setDisplayMode(.cylinder)
        store.isShowingSettings = false
        panelController?.open(anchorRect: store.hider.folderButtonScreenFrame)
    }

    @objc private func menuToggleIconStyle() {
        guard let store else { return }
        let next: IconStyle = store.config.preferences.iconStyle == .color ? .monochrome : .color
        store.setIconStyle(next)
    }

    @objc private func menuAutoCollect() {
        store?.autoCollectAllIcons()
    }

    @objc private func menuToggleReveal() {
        store?.toggleTemporaryReveal()
    }

    @objc private func menuRefresh() {
        store?.refreshItems(captureThumbnails: true)
    }

    @objc private func menuCheckForUpdates() {
        guard let store else { return }
        panelController?.close()
        organizerController?.show()
        if store.updater.state.availableRelease != nil {
            store.updater.installAvailableUpdate()
        } else {
            store.updater.checkForUpdates(userInitiated: true)
        }
    }

    @objc private func menuShowOnboarding() {
        panelController?.close()
        onboardingController?.show()
    }

    @objc private func menuQuit() {
        NSApp.terminate(nil)
    }
}
