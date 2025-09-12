import SwiftUI

@main
struct PetrichorApp: App {
    @StateObject private var appCoordinator = AppCoordinator()
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    @AppStorage("showFoldersTab")
    private var showFoldersTab = false
    
    @State private var menuUpdateTrigger = UUID()

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
        .windowResizability(.contentMinSize)
        .handlesExternalEvents(matching: Set(arrayLiteral: "main"))
        .commands {
            // App Menu Commands
            appMenuCommands()
            
            // Playback Menu
            playbackMenuCommands()
            
            // View Menu Commands
            viewMenuCommands()
            
            // Help Menu Commands
            helpMenuCommands()
        }
    }
    
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
        Button("About Petrichor") {
            NotificationCenter.default.post(
                name: NSNotification.Name("OpenSettingsAboutTab"),
                object: nil
            )
        }
    }
    
    private func settingsMenuItem() -> some View {
        Button("Settings") {
            NotificationCenter.default.post(
                name: NSNotification.Name("OpenSettings"),
                object: nil
            )
        }
        .keyboardShortcut(",", modifiers: .command)
    }
    
    private func checkForUpdatesMenuItem() -> some View {
        Button("Check for Updates...") {
            if let updater = appDelegate.updaterController?.updater {
                updater.checkForUpdates()
            }
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
        Button("Play/Pause") {
            if appCoordinator.playbackManager.currentTrack != nil {
                appCoordinator.playbackManager.togglePlayPause()
            }
        }
        .keyboardShortcut(" ", modifiers: [])
        .disabled(appCoordinator.playbackManager.currentTrack == nil)
    }
    
    private func favoriteMenuItem() -> some View {
        Button(appCoordinator.playbackManager.currentTrack?.isFavorite == true ?
               "Remove from Favorites" : "Add to Favorites") {
            if let track = appCoordinator.playbackManager.currentTrack {
                appCoordinator.playlistManager.toggleFavorite(for: track)
                menuUpdateTrigger = UUID()
            }
        }
        .keyboardShortcut("f", modifiers: [.command, .shift])
        .disabled(appCoordinator.playbackManager.currentTrack == nil)
        .id(menuUpdateTrigger)
    }
    
    private func shuffleMenuItem() -> some View {
        Toggle("Shuffle", isOn: Binding(
            get: { appCoordinator.playlistManager.isShuffleEnabled },
            set: { _ in
                appCoordinator.playlistManager.toggleShuffle()
                menuUpdateTrigger = UUID()
            }
        ))
        .keyboardShortcut("s", modifiers: .command)
        .id(menuUpdateTrigger)
    }
    
    private func repeatMenuItem() -> some View {
        Button(repeatModeLabel) {
            appCoordinator.playlistManager.toggleRepeatMode()
            menuUpdateTrigger = UUID()
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
        Button("Next") {
            appCoordinator.playlistManager.playNextTrack()
        }
        .keyboardShortcut(.rightArrow, modifiers: .command)
        .disabled(appCoordinator.playbackManager.currentTrack == nil)
    }
    
    private func previousMenuItem() -> some View {
        Button("Previous") {
            appCoordinator.playlistManager.playPreviousTrack()
        }
        .keyboardShortcut(.leftArrow, modifiers: .command)
        .disabled(appCoordinator.playbackManager.currentTrack == nil)
    }
    
    private func seekForwardMenuItem() -> some View {
        Button("Seek Forward") {
            if let currentTrack = appCoordinator.playbackManager.currentTrack {
                let newTime = min(
                    appCoordinator.playbackManager.actualCurrentTime + 10,
                    currentTrack.duration
                )
                appCoordinator.playbackManager.seekTo(time: newTime)
            }
        }
        .keyboardShortcut(.rightArrow, modifiers: [.command, .shift])
        .disabled(appCoordinator.playbackManager.currentTrack == nil)
    }
    
    private func seekBackwardMenuItem() -> some View {
        Button("Seek Backward") {
            if appCoordinator.playbackManager.currentTrack != nil {
                let newTime = max(
                    appCoordinator.playbackManager.actualCurrentTime - 10,
                    0
                )
                appCoordinator.playbackManager.seekTo(time: newTime)
            }
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
        Button("Volume Up") {
            let newVolume = min(appCoordinator.playbackManager.volume + 0.05, 1.0)
            appCoordinator.playbackManager.setVolume(newVolume)
        }
        .keyboardShortcut(.upArrow, modifiers: .command)
    }
    
    private func volumeDownMenuItem() -> some View {
        Button("Volume Down") {
            let newVolume = max(appCoordinator.playbackManager.volume - 0.05, 0.0)
            appCoordinator.playbackManager.setVolume(newVolume)
        }
        .keyboardShortcut(.downArrow, modifiers: .command)
    }
    
    // MARK: - View Menu Commands
    
    @CommandsBuilder
    private func viewMenuCommands() -> some Commands {
        CommandGroup(after: .toolbar) {
            focusSearchMenuItem()
            foldersTabToggle()
        }
    }
    
    private func focusSearchMenuItem() -> some View {
        Button("Search Library") {
            NotificationCenter.default.post(name: .focusSearchField, object: nil)
        }
        .keyboardShortcut("f", modifiers: .command)
    }
    
    private func foldersTabToggle() -> some View {
        Toggle("Folders tab", isOn: $showFoldersTab)
            .keyboardShortcut("f", modifiers: [.command, .option])
    }
    
    // MARK: - Help Menu Commands
    
    @CommandsBuilder
    private func helpMenuCommands() -> some Commands {
        CommandGroup(replacing: .help) {
            projectHomepageMenuItem()
            sponsorProjectMenuItem()
            Divider()
            helpMenuItem()
        }
    }
    
    private func projectHomepageMenuItem() -> some View {
        Button("Project Homepage") {
            if let url = URL(string: About.appWebsite) {
                NSWorkspace.shared.open(url)
            }
        }
    }
    
    private func sponsorProjectMenuItem() -> some View {
        Button("Support Development") {
            if let url = URL(string: About.sponsor) {
                NSWorkspace.shared.open(url)
            }
        }
    }
    
    private func helpMenuItem() -> some View {
        Button("Petrichor Help") {
            if let url = URL(string: About.appWiki) {
                NSWorkspace.shared.open(url)
            }
        }
        .keyboardShortcut("?", modifiers: .command)
    }
    
    // MARK: - Helper Properties
    
    private var repeatModeLabel: String {
        switch appCoordinator.playlistManager.repeatMode {
        case .off:
            return "Repeat: Off"
        case .all:
            return "Repeat: All"
        case .one:
            return "Repeat: One"
        }
    }
}
