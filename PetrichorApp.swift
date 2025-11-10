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
                .environmentObject(appCoordinator.playbackManager.playbackProgressState)
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
        Button {
            NotificationCenter.default.post(
                name: NSNotification.Name("OpenSettingsAboutTab"),
                object: nil
            )
        } label: {
            if #available(macOS 26.0, *) {
                Label("About Petrichor", systemImage: Icons.infoCircle)
            } else {
                Text("About Petrichor")
            }
        }
    }
    
    private func settingsMenuItem() -> some View {
        Button {
            NotificationCenter.default.post(
                name: NSNotification.Name("OpenSettings"),
                object: nil
            )
        } label: {
            if #available(macOS 26.0, *) {
                Label("Settings", systemImage: Icons.settings)
            } else {
                Text("Settings")
            }
        }
        .keyboardShortcut(",", modifiers: .command)
    }
    
    private func checkForUpdatesMenuItem() -> some View {
        Button {
            if let updater = appDelegate.updaterController?.updater {
                updater.checkForUpdates()
            }
        } label: {
            if #available(macOS 26.0, *) {
                Label("Check for Updates...", systemImage: Icons.checkForUpdates)
            } else {
                Text("Check for Updates...")
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
        Button {
            if appCoordinator.playbackManager.currentTrack != nil {
                appCoordinator.playbackManager.togglePlayPause()
            }
        } label: {
            if #available(macOS 26.0, *) {
                Label(
                    "Play/Pause",
                    systemImage: Icons.playPauseFill
                )
            } else {
                Text("Play/Pause")
            }
        }
        .keyboardShortcut(" ", modifiers: [])
        .disabled(appCoordinator.playbackManager.currentTrack == nil)
    }
    
    private func favoriteMenuItem() -> some View {
        Button {
            if let track = appCoordinator.playbackManager.currentTrack {
                appCoordinator.playlistManager.toggleFavorite(for: track)
                menuUpdateTrigger = UUID()
            }
        } label: {
            let isFavorite = appCoordinator.playbackManager.currentTrack?.isFavorite == true

            if #available(macOS 26.0, *) {
                Label(
                    isFavorite ? "Remove from Favorites" : "Add to Favorites",
                    systemImage: isFavorite ? Icons.starFill : Icons.star
                )
            } else {
                Text(isFavorite ? "Remove from Favorites" : "Add to Favorites")
            }
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
            if #available(macOS 26.0, *) {
                Label("Shuffle", systemImage: Icons.shuffleFill)
            } else {
                Text("Shuffle")
            }
        }
        .keyboardShortcut("s", modifiers: .command)
        .id(menuUpdateTrigger)
    }
    
    private func repeatMenuItem() -> some View {
        Button {
            appCoordinator.playlistManager.toggleRepeatMode()
            menuUpdateTrigger = UUID()
        } label: {
            if #available(macOS 26.0, *) {
                Label(
                    repeatModeLabel,
                    systemImage: Icons.repeatFill
                )
            } else {
                Text(repeatModeLabel)
            }
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
            if #available(macOS 26.0, *) {
                Label(
                    "Next",
                    systemImage: Icons.nextFill
                )
            } else {
                Text("Next")
            }
        }
        .keyboardShortcut(.rightArrow, modifiers: .command)
        .disabled(appCoordinator.playbackManager.currentTrack == nil)
    }
    
    private func previousMenuItem() -> some View {
        Button {
            appCoordinator.playlistManager.playPreviousTrack()
        } label: {
            if #available(macOS 26.0, *) {
                Label(
                    "Previous",
                    systemImage: Icons.previousFIll
                )
            } else {
                Text("Previous")
            }
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
            if #available(macOS 26.0, *) {
                Label(
                    "Seek Forward",
                    systemImage: Icons.forwardFill
                )
            } else {
                Text("Seek Formward")
            }
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
            if #available(macOS 26.0, *) {
                Label(
                    "Seek Backward",
                    systemImage: Icons.backwardFill
                )
            } else {
                Text("Seek Backward")
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
        Button {
            let newVolume = min(appCoordinator.playbackManager.volume + 0.05, 1.0)
            appCoordinator.playbackManager.setVolume(newVolume)
        } label: {
            if #available(macOS 26.0, *) {
                Label(
                    "Volume Up",
                    systemImage: Icons.volumeIncrease
                )
            } else {
                Text("Volume Up")
            }
        }
        .keyboardShortcut(.upArrow, modifiers: .command)
    }
    
    private func volumeDownMenuItem() -> some View {
        Button {
            let newVolume = max(appCoordinator.playbackManager.volume - 0.05, 0.0)
            appCoordinator.playbackManager.setVolume(newVolume)
        } label: {
            if #available(macOS 26.0, *) {
                Label(
                    "Volume Down",
                    systemImage: Icons.volumeDecrease
                )
            } else {
                Text("Volume Down")
            }
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
        Button {
            NotificationCenter.default.post(name: .focusSearchField, object: nil)
        } label: {
            if #available(macOS 26.0, *) {
                Label(
                    "Search Library",
                    systemImage: Icons.magnifyingGlass
                )
            } else {
                Text("Search Library")
            }
        }
        .keyboardShortcut("f", modifiers: .command)
    }
    
    private func foldersTabToggle() -> some View {
        Toggle(isOn: $showFoldersTab) {
            if #available(macOS 26.0, *) {
                Label("Folders Tab", systemImage: Icons.folderFill)
            } else {
                Text("Folders Tab")
            }
        }
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
        Button {
            if let url = URL(string: About.appWebsite) {
                NSWorkspace.shared.open(url)
            }
        } label: {
            if #available(macOS 26.0, *) {
                Label(
                    "Project Homepage",
                    systemImage: "globe"
                )
            } else {
                Text("Project Homepage")
            }
        }
    }
    
    private func sponsorProjectMenuItem() -> some View {
        Button {
            if let url = URL(string: About.sponsor) {
                NSWorkspace.shared.open(url)
            }
        } label: {
            if #available(macOS 26.0, *) {
                Label(
                    "Support Development",
                    systemImage: "dollarsign.circle"
                )
            } else {
                Text("Support Development")
            }
        }
    }
    
    private func helpMenuItem() -> some View {
        Button {
            if let url = URL(string: About.appWiki) {
                NSWorkspace.shared.open(url)
            }
        } label: {
            if #available(macOS 26.0, *) {
                Label(
                    "Petrichor User Guide",
                    systemImage: "book.pages"
                )
            } else {
                Text("Petrichor User Guide")
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
