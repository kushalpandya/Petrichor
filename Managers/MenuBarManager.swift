//
// MenuBarManager class
//
// This class handles the menu bar options and interactions for the app.
//


import AppKit
import SwiftUI

class MenuBarManager: NSObject {
    private var statusItem: NSStatusItem?
    private let playbackManager: PlaybackManager
    private let playlistManager: PlaylistManager

    var isMenuBarActive: Bool {
        statusItem != nil
    }

    init(playbackManager: PlaybackManager, playlistManager: PlaylistManager) {
        self.playbackManager = playbackManager
        self.playlistManager = playlistManager
        super.init()

        // Observe the UserDefaults change
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleCloseToMenubarChange),
            name: UserDefaults.didChangeNotification,
            object: nil
        )

        // Observe playback state changes
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(updateMenuBarIcon),
            name: NSNotification.Name("PlaybackStateChanged"),
            object: nil
        )

        // Set up initial state
        if UserDefaults.standard.bool(forKey: "closeToMenubar") {
            setupMenuBar()
        }
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    @objc
    private func handleCloseToMenubarChange() {
        if UserDefaults.standard.bool(forKey: "closeToMenubar") {
            setupMenuBar()
        } else {
            removeMenuBar()
        }
    }

    private func setupMenuBar() {
        guard statusItem == nil else { return }

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        updateMenuBarIcon()
        updateMenu()

        Logger.info("Menubar setup complete")
    }

    @objc
    private func updateMenuBarIcon() {
        guard let button = statusItem?.button else { return }

        // Use play/pause circle icons based on playback state
        let iconName = playbackManager.isPlaying ? Icons.playCircleFill : Icons.pauseCircleFill

        if let image = NSImage(systemSymbolName: iconName, accessibilityDescription: "Petrichor") {
            image.size = NSSize(width: 18, height: 18)
            image.isTemplate = true
            button.image = image
        }

        // Also update the menu when playback state changes
        updateMenu()
    }

    private func removeMenuBar() {
        if let statusItem = statusItem {
            NSStatusBar.system.removeStatusItem(statusItem)
            self.statusItem = nil
        }
    }

    @objc
    private func updateMenu() {
        guard let statusItem = statusItem else { return }

        let menu = NSMenu()
        menu.autoenablesItems = false  // Prevent automatic state changes
        menu.minimumWidth = 180  // Set a fixed minimum width

        // Play/Pause
        let playPauseItem = NSMenuItem(
            title: playbackManager.isPlaying ? "Pause" : "Play",
            action: #selector(togglePlayPause),
            keyEquivalent: ""
        )
        playPauseItem.target = self
        playPauseItem.isEnabled = true
        menu.addItem(playPauseItem)

        // Next
        let nextItem = NSMenuItem(
            title: "Next",
            action: #selector(playNext),
            keyEquivalent: ""
        )
        nextItem.target = self
        nextItem.isEnabled = true
        menu.addItem(nextItem)

        // Previous
        let previousItem = NSMenuItem(
            title: "Previous",
            action: #selector(playPrevious),
            keyEquivalent: ""
        )
        previousItem.target = self
        previousItem.isEnabled = true
        menu.addItem(previousItem)

        menu.addItem(NSMenuItem.separator())

        // Shuffle - no indentation
        let shuffleItem = NSMenuItem(
            title: "Shuffle",
            action: #selector(toggleShuffle),
            keyEquivalent: ""
        )
        shuffleItem.target = self
        shuffleItem.state = playlistManager.isShuffleEnabled ? .on : .off
        shuffleItem.isEnabled = true
        menu.addItem(shuffleItem)

        menu.addItem(NSMenuItem.separator())

        // Show App Window
        let showWindowItem = NSMenuItem(
            title: "Show Petrichor",
            action: #selector(showMainWindow),
            keyEquivalent: ""
        )
        showWindowItem.target = self
        showWindowItem.isEnabled = true
        menu.addItem(showWindowItem)

        menu.addItem(NSMenuItem.separator())

        // Quit
        let quitItem = NSMenuItem(
            title: "Quit Petrichor",
            action: #selector(quitApp),
            keyEquivalent: ""
        )
        quitItem.target = self
        quitItem.isEnabled = true
        menu.addItem(quitItem)

        statusItem.menu = menu
    }

    // MARK: - Actions

    @objc
    private func togglePlayPause() {
        playbackManager.togglePlayPause()
        updateMenu()
    }

    @objc
    private func playNext() {
        playlistManager.playNextTrack()
        updateMenu()
    }

    @objc
    private func playPrevious() {
        playlistManager.playPreviousTrack()
        updateMenu()
    }

    @objc
    private func toggleShuffle() {
        playlistManager.toggleShuffle()
        updateMenu()
    }

    @objc
    private func showMainWindow() {
        Logger.info("Showing main window from menubar")

        // First restore dock icon
        NSApp.setActivationPolicy(.regular)

        // Then show the window
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            if let window = WindowManager.shared.mainWindow {
                window.makeKeyAndOrderFront(nil)
                window.level = .floating // Temporarily float

                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    window.level = .normal // Return to normal
                }
            } else if let window = NSApp.windows.first {
                window.makeKeyAndOrderFront(nil)
                window.level = .floating // Temporarily float

                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    window.level = .normal // Return to normal
                }
            }
        }
    }

    @objc
    private func quitApp() {
        NSApp.terminate(nil)
    }
}
