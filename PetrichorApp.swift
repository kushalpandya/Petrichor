import SwiftUI

@main
struct PetrichorApp: App {
    @StateObject private var appCoordinator: AppCoordinator
    @NSApplicationDelegateAdaptor(AppDelegate.self)
    var appDelegate

    init() {
        AppDelegate.registerUserDefaultsDefaults()
        _appCoordinator = StateObject(wrappedValue: AppCoordinator())
    }
    
    @AppStorage("showFoldersTab")
    private var showFoldersTab = false
    
    @AppStorage("closeToMenubar")
    private var closeToMenubar = true

    @AppStorage("miniPlayerAlwaysOnTop")
    private var miniPlayerAlwaysOnTop = false

    @AppStorage("internetRadioEnabled")
    private var internetRadioEnabled = true

    @State private var menuUpdateTrigger = UUID()
    @Environment(\.openWindow)
    private var openWindow

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appCoordinator.playbackManager)
                .environmentObject(appCoordinator.libraryManager)
                .environmentObject(appCoordinator.playlistManager)
                .onReceive(appCoordinator.playlistManager.$repeatMode) { _ in
                    menuUpdateTrigger = UUID()
                }
                .onReceive(appCoordinator.playbackManager.$currentTrack) { _ in
                    menuUpdateTrigger = UUID()
                }
                .onReceive(appCoordinator.playlistManager.$isShuffleEnabled) { _ in
                    menuUpdateTrigger = UUID()
                }
        }
        .windowStyle(.hiddenTitleBar)
        .windowToolbarStyle(.unified)
        .defaultSize(width: 1200, height: 800)
        .windowResizability(.contentSize)
        .handlesExternalEvents(matching: ["main"])
        
        equalizerWindow

        reportProblemWindow

        acknowledgementsWindow

        .commands {
            // App Menu Commands
            appMenuCommands()
            
            // File Menu Commands
            fileMenuCommands()
            
            // Playback Menu
            playbackMenuCommands()
            
            // View Menu Commands
            viewMenuCommands()
            
            // Window Menu Commands
            windowMenuCommands()
            
            // Help Menu Commands
            helpMenuCommands()
        }
    }
    
    private var equalizerWindow: some Scene {
        WindowGroup("Equalizer", id: "equalizer") {
            EqualizerView()
                .environmentObject(appCoordinator.playbackManager)
        }
        .handlesExternalEvents(matching: [])
        .defaultSize(width: 500, height: 300)
        .windowResizability(.contentSize)
    }

    private var reportProblemWindow: some Scene {
        WindowGroup("Report a Problem", id: "report-problem") {
            ReportProblemView()
        }
        .handlesExternalEvents(matching: [])
        .defaultSize(width: 560, height: 680)
        .windowResizability(.contentSize)
    }

    private var acknowledgementsWindow: some Scene {
        WindowGroup("License & Acknowledgements", id: "acknowledgements") {
            AcknowledgementsView()
        }
        .handlesExternalEvents(matching: [])
        .defaultSize(width: 640, height: 720)
        .windowResizability(.contentSize)
    }
}

extension PetrichorApp {
    // MARK: - App Menu Commands
    
    @CommandsBuilder
    private func appMenuCommands() -> some Commands {
        CommandGroup(replacing: .appSettings) {}
        
        CommandGroup(replacing: .appInfo) {
            aboutMenuItem()
        }
        
        CommandGroup(after: .appInfo) {
            settingsMenuItem()
        }
        
        CommandGroup(after: .appInfo) {
            Divider()
            checkForUpdatesMenuItem()
        }
    }
    
    private func aboutMenuItem() -> some View {
        Button {
            NotificationCenter.default.post(
                name: NSNotification.Name("OpenSettingsAboutTab"),
                object: nil
            )
        } label: {
            Text("About Petrichor")
        }
    }
    
    private func settingsMenuItem() -> some View {
        Button {
            NotificationCenter.default.post(
                name: NSNotification.Name("OpenSettings"),
                object: nil
            )
        } label: {
            menuItemLabel(String(localized: "Settings"), systemImage: Icons.settings)
        }
        .keyboardShortcut(",", modifiers: .command)
    }
    
    private func checkForUpdatesMenuItem() -> some View {
        Button {
            if let updater = appDelegate.updaterController?.updater {
                updater.checkForUpdates()
            }
        } label: {
            Text("Check for Updates...")
        }
        // Dev builds don't run the updater, so leave the item visible but inert
        .disabled(!AppInfo.isProductionBuild)
    }
    
    // MARK: - File Menu Commands

    @CommandsBuilder
    private func fileMenuCommands() -> some Commands {
        CommandGroup(replacing: .saveItem) {}

        CommandGroup(replacing: .newItem) {
            // New submenu
            Menu {
                newPlaylistMenuItem()
                newPlaylistFromSelectionMenuItem()

                if internetRadioEnabled {
                    Divider()
                    newRadioStationMenuItem()
                }
            } label: {
                Text("New")
            }
            
            Divider()
            
            // Library submenu
            Menu {
                addFolderMenuItem()
                refreshLibraryMenuItem()
            } label: {
                Text("Library")
            }
            
            // Playlists submenu
            Menu {
                importPlaylistsMenuItem()
                exportPlaylistsMenuItem()
            } label: {
                Text("Playlists")
            }
            
            Divider()
            
            closeWindowMenuItem()
        }
    }
    
    private func closeWindowMenuItem() -> some View {
        Button {
            closeWindow()
        } label: {
            Text("Close")
        }
        .keyboardShortcut("w", modifiers: .command)
    }
    
    private func closeWindow() {
        guard let window = NSApp.keyWindow else { return }
        
        let isMainWindow = window.identifier?.rawValue == WindowIdentifier.mainWindow
        
        if closeToMenubar && isMainWindow {
            appCoordinator.savePlaybackState()
            window.orderOut(nil)
            DispatchQueue.main.async {
                WindowManager.shared.playbackWindowVisibilityDidChange()
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                NSApp.setActivationPolicy(.accessory)
            }
        } else {
            window.close()
        }
    }

    // MARK: - New Menu Items

    private func newPlaylistMenuItem() -> some View {
        Button {
            appCoordinator.playlistManager.showCreatePlaylistModal()
        } label: {
            Text("Playlist")
        }
        .keyboardShortcut("n", modifiers: .command)
        .disabled(!appCoordinator.libraryManager.hasLocalMusic)
    }

    private func newRadioStationMenuItem() -> some View {
        Button {
            InternetRadioManager.shared.showAddStation()
        } label: {
            Text("Radio Station")
        }
        .keyboardShortcut("n", modifiers: [.command, .option])
    }

    private func newPlaylistFromSelectionMenuItem() -> some View {
        Button {
            NotificationCenter.default.post(
                name: .createPlaylistFromSelection,
                object: nil
            )
        } label: {
            Text("Playlist from Selection")
        }
        .keyboardShortcut("n", modifiers: [.command, .shift])
    }

    // MARK: - Library Menu Items

    private func addFolderMenuItem() -> some View {
        Button {
            appCoordinator.libraryManager.addFolder()
        } label: {
            Text("Add Folder(s) to Library")
        }
        .keyboardShortcut("o", modifiers: .command)
    }

    private func refreshLibraryMenuItem() -> some View {
        Button {
            appCoordinator.libraryManager.refreshLibrary()
        } label: {
            Text("Refresh Library Folders")
        }
        .keyboardShortcut("r", modifiers: [.command, .shift])
    }

    // MARK: - Playlists Menu Items

    private func importPlaylistsMenuItem() -> some View {
        Button {
            NotificationCenter.default.post(name: .importPlaylists, object: nil)
        } label: {
            Text("Import Playlists")
        }
    }

    private func exportPlaylistsMenuItem() -> some View {
        Button {
            NotificationCenter.default.post(name: .exportPlaylists, object: nil)
        } label: {
            Text("Export Playlists")
        }
    }
    
    // MARK: - Playback Menu Commands
    
    @CommandsBuilder
    private func playbackMenuCommands() -> some Commands {
        CommandMenu("Playback") {
            playPauseMenuItem()
            favoriteMenuItem()
            
            Divider()
            
            shuffleMenuItem()
            repeatMenuItem()
            
            Divider()
            
            navigationMenuItems()
            
            Divider()
            
            volumeMenuItems()
        }
    }
    
    private func playPauseMenuItem() -> some View {
        Button {
            if appCoordinator.playbackManager.hasPlayableContent {
                appCoordinator.playbackManager.togglePlayPause()
            }
        } label: {
            Text("Play/Pause")
        }
        .keyboardShortcut(" ", modifiers: [])
        .disabled(!appCoordinator.playbackManager.hasPlayableContent)
    }
    
    private func favoriteMenuItem() -> some View {
        Button {
            if let track = appCoordinator.playbackManager.currentTrack {
                appCoordinator.playlistManager.toggleFavorite(for: track)
                menuUpdateTrigger = UUID()
            }
        } label: {
            let isFavorite = appCoordinator.playbackManager.currentTrack?.isFavorite == true

            Text(isFavorite ? String(localized: "Remove from Favorites") : String(localized: "Add to Favorites"))
        }
        .keyboardShortcut("f", modifiers: [.command, .shift])
        .disabled(appCoordinator.playbackManager.currentTrack == nil)
        .id(menuUpdateTrigger)
    }
    
    private func shuffleMenuItem() -> some View {
        Toggle(isOn: Binding(
            get: { appCoordinator.playlistManager.isShuffleEnabled },
            set: { _ in
                appCoordinator.playlistManager.toggleShuffle()
                menuUpdateTrigger = UUID()
            }
        )) {
            menuItemLabel(String(localized: "Shuffle"), systemImage: Icons.shuffleFill)
        }
        .keyboardShortcut("s", modifiers: .command)
        .id(menuUpdateTrigger)
    }
    
    private func repeatMenuItem() -> some View {
        Button {
            appCoordinator.playlistManager.toggleRepeatMode()
            menuUpdateTrigger = UUID()
        } label: {
            menuItemLabel(repeatModeLabel, systemImage: Icons.repeatFill)
        }
        .keyboardShortcut("r", modifiers: .command)
        .id(menuUpdateTrigger)
    }
    
    @ViewBuilder
    private func navigationMenuItems() -> some View {
        nextMenuItem()
        previousMenuItem()
        seekForwardMenuItem()
        seekBackwardMenuItem()
    }
    
    private func nextMenuItem() -> some View {
        Button {
            appCoordinator.playlistManager.playNextTrack()
        } label: {
            Text("Next")
        }
        .keyboardShortcut(.rightArrow, modifiers: .command)
        .disabled(appCoordinator.playbackManager.currentTrack == nil)
    }
    
    private func previousMenuItem() -> some View {
        Button {
            appCoordinator.playlistManager.playPreviousTrack()
        } label: {
            Text("Previous")
        }
        .keyboardShortcut(.leftArrow, modifiers: .command)
        .disabled(appCoordinator.playbackManager.currentTrack == nil)
    }
    
    private func seekForwardMenuItem() -> some View {
        Button {
            if let currentTrack = appCoordinator.playbackManager.currentTrack {
                let newTime = min(
                    appCoordinator.playbackManager.actualCurrentTime + 10,
                    currentTrack.duration
                )
                appCoordinator.playbackManager.seekTo(time: newTime)
            }
        } label: {
            Text("Seek Forward")
        }
        .keyboardShortcut(.rightArrow, modifiers: [.command, .shift])
        .disabled(appCoordinator.playbackManager.currentTrack == nil)
    }
    
    private func seekBackwardMenuItem() -> some View {
        Button {
            if appCoordinator.playbackManager.currentTrack != nil {
                let newTime = max(
                    appCoordinator.playbackManager.actualCurrentTime - 10,
                    0
                )
                appCoordinator.playbackManager.seekTo(time: newTime)
            }
        } label: {
            Text("Seek Backward")
        }
        .keyboardShortcut(.leftArrow, modifiers: [.command, .shift])
        .disabled(appCoordinator.playbackManager.currentTrack == nil)
    }
    
    @ViewBuilder
    private func volumeMenuItems() -> some View {
        volumeUpMenuItem()
        volumeDownMenuItem()
    }
    
    private func volumeUpMenuItem() -> some View {
        Button {
            let newVolume = min(appCoordinator.playbackManager.volume + 0.05, 1.0)
            appCoordinator.playbackManager.setVolume(newVolume)
        } label: {
            Text("Volume Up")
        }
        .keyboardShortcut(.upArrow, modifiers: .command)
    }
    
    private func volumeDownMenuItem() -> some View {
        Button {
            let newVolume = max(appCoordinator.playbackManager.volume - 0.05, 0.0)
            appCoordinator.playbackManager.setVolume(newVolume)
        } label: {
            Text("Volume Down")
        }
        .keyboardShortcut(.downArrow, modifiers: .command)
    }
    
    // MARK: - Window Menu Commands
    
    @CommandsBuilder
    private func windowMenuCommands() -> some Commands {
        CommandGroup(before: .windowList) {
            Button {
                openWindow(id: "equalizer")
            } label: {
                menuItemLabel(String(localized: "Equalizer"), systemImage: "slider.vertical.3")
            }
            .keyboardShortcut("e", modifiers: [.command, .option])

            Button {
                MiniPlayerWindowManager.shared.show()
            } label: {
                menuItemLabel(String(localized: "Mini Player"), systemImage: Icons.miniPlayer)
            }
            .keyboardShortcut("m", modifiers: [.command, .option])
            .disabled(!appCoordinator.playbackManager.hasPlayableContent)

            Button {
                NotificationCenter.default.post(name: .toggleImmersivePlayer, object: nil)
            } label: {
                menuItemLabel(String(localized: "Immersive Mode"), systemImage: Icons.immersive)
            }
            .keyboardShortcut("f", modifiers: [.command, .option])
            .disabled(!appCoordinator.playbackManager.hasPlayableContent)

            Divider()
        }
    }
    
    // MARK: - View Menu Commands
    
    @CommandsBuilder
    private func viewMenuCommands() -> some Commands {
        CommandGroup(after: .toolbar) {
            Divider()
            focusSearchMenuItem()
            foldersTabToggle()
            miniPlayerOnTopToggle()
        }
    }

    private func miniPlayerOnTopToggle() -> some View {
        Toggle(isOn: $miniPlayerAlwaysOnTop) {
            Text("Keep Mini Player Always on Top")
        }
    }
    
    private func focusSearchMenuItem() -> some View {
        Button {
            NotificationCenter.default.post(name: .focusSearchField, object: nil)
        } label: {
            Text("Search Library")
        }
        .keyboardShortcut("f", modifiers: .command)
    }
    
    private func foldersTabToggle() -> some View {
        Toggle(isOn: $showFoldersTab) {
            Text("Folders Tab")
        }
        .keyboardShortcut("f", modifiers: [.command, .option, .shift])
    }
    
    // MARK: - Help Menu Commands
    
    @CommandsBuilder
    private func helpMenuCommands() -> some Commands {
        CommandGroup(replacing: .help) {
            projectHomepageMenuItem()
            sponsorProjectMenuItem()
            licenseMenuItem()
            Divider()
            helpMenuItem()
            reportProblemMenuItem()
        }
    }

    private func reportProblemMenuItem() -> some View {
        Button {
            openWindow(id: "report-problem")
        } label: {
            menuItemLabel(String(localized: "Report a Problem..."), systemImage: "exclamationmark.bubble")
        }
    }
    
    private func projectHomepageMenuItem() -> some View {
        Button {
            if let url = URL(string: About.appWebsite) {
                NSWorkspace.shared.open(url)
            }
        } label: {
            Text("Project Homepage")
        }
    }
    
    private func sponsorProjectMenuItem() -> some View {
        Button {
            if let url = URL(string: About.donate) {
                NSWorkspace.shared.open(url)
            }
        } label: {
            Text("Support Development")
        }
    }

    private func licenseMenuItem() -> some View {
        Button {
            openWindow(id: "acknowledgements")
        } label: {
            Text("License & Acknowledgements")
        }
    }

    private func helpMenuItem() -> some View {
        Button {
            if let url = URL(string: About.appWiki) {
                NSWorkspace.shared.open(url)
            }
        } label: {
            Text("Petrichor User Guide")
        }
        .keyboardShortcut("?", modifiers: .command)
    }
    
    // MARK: - Helper Properties
    
    private var repeatModeLabel: String {
        switch appCoordinator.playlistManager.repeatMode {
        case .off: return String(localized: "Repeat: Off")
        case .one: return String(localized: "Repeat: Current Track")
        case .all: return String(localized: "Repeat: All")
        }
    }
}
