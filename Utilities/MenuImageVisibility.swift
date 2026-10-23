import AppKit

/// macOS 27 hides menu item images unless each item opts in, and SwiftUI has no modifier for it.
/// SwiftUI rebuilds its menus freely, so the opt-in is reapplied whenever items are added or changed.
enum MenuImageVisibility {
    private static var observers: [NSObjectProtocol] = []

    static func install() {
        guard #available(macOS 27.0, *), observers.isEmpty else { return }

        for name in [NSMenu.didAddItemNotification, NSMenu.didChangeItemNotification] {
            observers.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: nil) { notification in
                guard let menu = notification.object as? NSMenu,
                      let index = notification.userInfo?["NSMenuItemIndex"] as? Int,
                      menu.items.indices.contains(index) else { return }
                MainActor.assumeIsolated { apply(to: menu.items[index], in: menu) }
            })
        }
    }

    /// Context menus and the status item menu are entirely ours, so every image they carry is intentional.
    /// In the main menu, only an explicit set of items keeps its icon.
    @available(macOS 27.0, *)
    @MainActor
    private static func apply(to item: NSMenuItem, in menu: NSMenu) {
        guard item.image != nil, item.preferredImageVisibility != .visible else { return }

        if !isInMainMenu(menu) || isMainMenuIconItem(item, in: menu) {
            item.preferredImageVisibility = .visible
        }
    }

    @MainActor
    private static func isMainMenuIconItem(_ item: NSMenuItem, in menu: NSMenu) -> Bool {
        if item.action == #selector(NSWindow.toggleFullScreen(_:)) { return true }
        if menu.title == String(localized: "Playback") { return true }
        return [
            String(localized: "Settings"),
            String(localized: "Equalizer"),
            String(localized: "Mini Player"),
            String(localized: "Immersive Mode"),
            String(localized: "Report a Problem...")
        ].contains(item.title)
    }

    @MainActor
    private static func isInMainMenu(_ menu: NSMenu) -> Bool {
        guard let mainMenu = NSApp.mainMenu else { return false }
        var current: NSMenu? = menu
        while let candidate = current {
            if candidate === mainMenu { return true }
            current = candidate.supermenu
        }
        return false
    }
}
