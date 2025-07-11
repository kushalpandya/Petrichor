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
        }
        .windowStyle(.hiddenTitleBar)
        .windowToolbarStyle(.unified)
        .defaultSize(width: 1200, height: 800)
        .windowResizability(.contentMinSize)
        .handlesExternalEvents(matching: Set(arrayLiteral: "main"))
        .commands {
            // Remove the default Preferences menu item
            CommandGroup(replacing: .appSettings) {}
            
            // Replace the default About menu item
            CommandGroup(replacing: .appInfo) {
                Button("About Petrichor") {
                    NotificationCenter.default.post(
                        name: NSNotification.Name("OpenSettingsAboutTab"),
                        object: nil
                    )
                }
            }
            
            // Add custom menu items under Petrichor menu
            CommandGroup(after: .appInfo) {
                Button("Settings") {
                    NotificationCenter.default.post(name: NSNotification.Name("OpenSettings"), object: nil)
                }
                .keyboardShortcut(",", modifiers: .command)
            }
            
            CommandMenu("Playback") {
                Button("Play/Pause") {
                    if appCoordinator.playbackManager.currentTrack != nil {
                        appCoordinator.playbackManager.togglePlayPause()
                    }
                }
                .keyboardShortcut(" ", modifiers: [])
                .disabled(appCoordinator.playbackManager.currentTrack == nil)
                
                Button(appCoordinator.playbackManager.currentTrack?.isFavorite == true ? "Remove from Favorites" : "Add to Favorites") {
                    if let track = appCoordinator.playbackManager.currentTrack {
                        appCoordinator.playlistManager.toggleFavorite(for: track)
                        menuUpdateTrigger = UUID()
                    }
                }
                .keyboardShortcut("f", modifiers: [.command, .shift])
                .disabled(appCoordinator.playbackManager.currentTrack == nil)
                .id(menuUpdateTrigger)
                
                Divider()
                
                Button("Shuffle") {
                    appCoordinator.playlistManager.toggleShuffle()
                }
                .keyboardShortcut("s", modifiers: .command)
                
                Button(repeatModeLabel) {
                    appCoordinator.playlistManager.toggleRepeatMode()
                    menuUpdateTrigger = UUID()
                }
                .keyboardShortcut("r", modifiers: .command)
                .id(menuUpdateTrigger)
                
                Divider()
                
                Button("Next") {
                    appCoordinator.playlistManager.playNextTrack()
                }
                .keyboardShortcut(.rightArrow, modifiers: .command)
                .disabled(appCoordinator.playbackManager.currentTrack == nil)
                
                Button("Previous") {
                    appCoordinator.playlistManager.playPreviousTrack()
                }
                .keyboardShortcut(.leftArrow, modifiers: .command)
                .disabled(appCoordinator.playbackManager.currentTrack == nil)
                
                Button("Seek Forward") {
                    if let currentTrack = appCoordinator.playbackManager.currentTrack {
                        let newTime = min(appCoordinator.playbackManager.actualCurrentTime + 10, currentTrack.duration)
                        appCoordinator.playbackManager.seekTo(time: newTime)
                    }
                }
                .keyboardShortcut(.rightArrow, modifiers: [])
                .disabled(appCoordinator.playbackManager.currentTrack == nil)
                
                Button("Seek Backward") {
                    if appCoordinator.playbackManager.currentTrack != nil {
                        let newTime = max(appCoordinator.playbackManager.actualCurrentTime - 10, 0)
                        appCoordinator.playbackManager.seekTo(time: newTime)
                    }
                }
                .keyboardShortcut(.leftArrow, modifiers: [])
                .disabled(appCoordinator.playbackManager.currentTrack == nil)
                
                Divider()
                
                Button("Volume Up") {
                    let newVolume = min(appCoordinator.playbackManager.volume + 0.05, 1.0)
                    appCoordinator.playbackManager.setVolume(newVolume)
                }
                .keyboardShortcut(.upArrow, modifiers: [])
                
                Button("Volume Down") {
                    let newVolume = max(appCoordinator.playbackManager.volume - 0.05, 0.0)
                    appCoordinator.playbackManager.setVolume(newVolume)
                }
                .keyboardShortcut(.downArrow, modifiers: [])
            }
            
            // Add to View menu
            CommandGroup(after: .toolbar) {
                Toggle("Folders tab", isOn: $showFoldersTab)
                    .keyboardShortcut("f", modifiers: [.command, .option])
            }
            
            // Customize the Help menu
            CommandGroup(replacing: .help) {
                Button("Petrichor Help") {
                    if let url = URL(string: About.appWiki) {
                        NSWorkspace.shared.open(url)
                    }
                }
                .keyboardShortcut("?", modifiers: .command)
            }
        }
    }
    
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
