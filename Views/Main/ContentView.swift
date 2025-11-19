import SwiftUI

struct ContentView: View {
    @EnvironmentObject var playbackManager: PlaybackManager
    @EnvironmentObject var libraryManager: LibraryManager
    @EnvironmentObject var playlistManager: PlaylistManager
        
    @AppStorage("rightSidebarSplitPosition")
    private var splitPosition: Double = 200
    
    @AppStorage("showFoldersTab")
    private var showFoldersTab = false
    
    @State private var selectedTab: Sections = .home
    @State private var showingSettings = false
    @State private var settingsInitialTab: SettingsView.SettingsTab = .general
    @State private var showingQueue = false
    @State private var showingTrackDetail = false
    @State private var detailTrack: Track?
    @State private var pendingLibraryFilter: LibraryFilterRequest?
    @State private var windowDelegate = WindowDelegate()
    @State private var isSettingsHovered = false
    @State private var shouldFocusSearch = false
    
    @ObservedObject private var notificationManager = NotificationManager.shared

    var body: some View {
        VStack(spacing: 0) {
            Divider()
            // Main Content Area with Queue
            mainContentArea

            playerControls
                .animation(.easeInOut(duration: 0.3), value: libraryManager.folders.isEmpty)
        }
        .onKeyPress(.space) {
            if isCurrentlyEditingText() {
                return .ignored
            }
            
            if playbackManager.currentTrack != nil {
                DispatchQueue.main.async {
                    playbackManager.togglePlayPause()
                }
                return .handled
            }
            
            return .ignored
        }
        .frame(minWidth: 1000, minHeight: 600)
        .onAppear(perform: handleOnAppear)
        .contentViewNotificationHandlers(
            shouldFocusSearch: $shouldFocusSearch,
            showingSettings: $showingSettings,
            selectedTab: $selectedTab,
            libraryManager: libraryManager,
            pendingLibraryFilter: $pendingLibraryFilter,
            showTrackDetail: showTrackDetail
        )
        .onChange(of: playbackManager.currentTrack?.id) { oldId, _ in
            if showingTrackDetail,
               let detailTrack = detailTrack,
               detailTrack.id == oldId,
               let newTrack = playbackManager.currentTrack {
                self.detailTrack = newTrack
            }
        }
        .onChange(of: libraryManager.globalSearchText) { _, newValue in
            if !newValue.isEmpty && selectedTab != .library {
                withAnimation(.easeInOut(duration: 0.25)) {
                    selectedTab = .library
                }
            }
        }
        .onChange(of: showFoldersTab) { _, newValue in
            if !newValue && selectedTab == .folders {
                withAnimation(.easeInOut(duration: 0.25)) {
                    selectedTab = .home
                }
            }
        }
        .background(WindowAccessor(windowDelegate: windowDelegate))
        .navigationTitle("")
        .toolbar {
            if #available(macOS 26.0, *) {
                modernToolbarContent
            } else {
                toolbarContent
            }
        }
        .sheet(isPresented: $showingSettings) {
            SettingsView()
                .environmentObject(libraryManager)
        }
        .sheet(isPresented: $playlistManager.showingCreatePlaylistModal) {
            CreatePlaylistSheet(
                isPresented: $playlistManager.showingCreatePlaylistModal,
                playlistName: $playlistManager.newPlaylistName,
                tracksToAdd: playlistManager.tracksToAddToNewPlaylist
            ) {
                playlistManager.createPlaylistFromModal()
            }
            .environmentObject(playlistManager)
        }
    }

    // MARK: - View Components

    private var mainContentArea: some View {
        PersistentSplitView(
            main: {
                sectionContent
            },
            right: {
                sidePanel
            },
            rightStorageKey: "rightSidebarSplitPosition"
        )
        .frame(minHeight: 0, maxHeight: .infinity)
    }

    private var sectionContent: some View {
        ZStack {
            HomeView(isShowingEntities: .constant(false))
                .opacity(selectedTab == .home ? 1 : 0)
                .allowsHitTesting(selectedTab == .home)
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            if selectedTab == .library {
                LibraryView(pendingFilter: $pendingLibraryFilter)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            if selectedTab == .playlists {
                PlaylistsView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            if selectedTab == .folders && showFoldersTab {
                FoldersView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private var sidePanel: some View {
        if showingQueue {
            PlayQueueView(showingQueue: $showingQueue)
        } else if showingTrackDetail, let track = detailTrack {
            TrackDetailView(track: track, onClose: hideTrackDetail)
        }
    }

    @ViewBuilder
    private var playerControls: some View {
        if !libraryManager.folders.isEmpty {
            Divider()

            PlayerView(showingQueue: Binding(
                get: { showingQueue },
                set: { newValue in
                    if newValue {
                        showingTrackDetail = false
                        detailTrack = nil
                    }
                    showingQueue = newValue
                    if let coordinator = AppCoordinator.shared {
                        coordinator.isQueueVisible = newValue
                    }
                }
            ))
            .frame(height: 90)
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .principal) {
            TabbedButtons(
                items: Sections.allCases.filter { $0 != .folders || showFoldersTab },
                selection: $selectedTab,
                animation: .transform,
                isDisabled: libraryManager.folders.isEmpty
            )
        }
        
        // Do not remove this spacer, it allows
        // for pushing toolbar items below to the
        // right-edge of window frame on macOS 14.x
        ToolbarItem { Spacer() }
        
        ToolbarItem(placement: .confirmationAction) {
            HStack(spacing: 8) {
                NotificationTray()
                    .frame(width: 24, height: 24)

                SearchInputField(
                    text: $libraryManager.globalSearchText,
                    placeholder: "Search",
                    fontSize: 12,
                    width: 280,
                    shouldFocus: shouldFocusSearch
                )
                .frame(width: 280)
                .disabled(libraryManager.folders.isEmpty)
                
                settingsButton
                    .disabled(libraryManager.folders.isEmpty)
            }
        }
    }
    
    @available(macOS 26.0, *)
    @ToolbarContentBuilder
    private var modernToolbarContent: some ToolbarContent {
        ToolbarItem(placement: .principal) {
            TabbedButtons(
                items: Sections.allCases.filter { $0 != .folders || showFoldersTab },
                selection: $selectedTab,
                style: .modern,
                animation: .transform,
                isDisabled: libraryManager.folders.isEmpty
            )
        }
        
        ToolbarItem(placement: .confirmationAction) {
            NotificationTray()
                .frame(width: 34, height: 30)
        }
        .sharedBackgroundVisibility(.hidden)

        ToolbarItem(placement: .confirmationAction) {
            SearchInputField(
                text: $libraryManager.globalSearchText,
                placeholder: "Search",
                fontSize: 12,
                shouldFocus: shouldFocusSearch
            )
            .frame(width: 280)
            .disabled(libraryManager.folders.isEmpty)
        }
    }
    
    private var settingsButton: some View {
        Button(action: {
            showingSettings = true
        }) {
            Image(systemName: "gear")
                .font(.system(size: 16))
                .frame(width: 24, height: 24)
                .foregroundColor(isSettingsHovered ? .primary : .secondary)
        }
        .buttonStyle(.borderless)
        .background(
            Circle()
                .fill(Color.gray.opacity(isSettingsHovered ? 0.1 : 0))
                .animation(.easeInOut(duration: AnimationDuration.standardDuration), value: isSettingsHovered)
        )
        .onHover { hovering in
            isSettingsHovered = hovering
        }
        .help("Settings")
    }

    // MARK: - Event Handlers

    private func handleOnAppear() {
        if let coordinator = AppCoordinator.shared {
            showingQueue = coordinator.isQueueVisible
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            NSApp.keyWindow?.makeFirstResponder(nil)
        }
    }

    private func handleLibraryFilter(_ notification: Notification) {
        if let filterType = notification.userInfo?["filterType"] as? LibraryFilterType,
           let filterValue = notification.userInfo?["filterValue"] as? String {
            selectedTab = .library
            pendingLibraryFilter = LibraryFilterRequest(filterType: filterType, value: filterValue)
        }
    }

    private func handleShowTrackInfo(_ notification: Notification) {
        if let track = notification.userInfo?["track"] as? Track {
            showTrackDetail(for: track)
        }
    }

    // MARK: - Helper Methods

    private func showTrackDetail(for track: Track) {
        showingQueue = false
        detailTrack = track
        showingTrackDetail = true
    }

    private func hideTrackDetail() {
        showingTrackDetail = false
        detailTrack = nil
    }
    
    private func isCurrentlyEditingText() -> Bool {
        guard let firstResponder = NSApp.keyWindow?.firstResponder else {
            return false
        }
        
        if firstResponder is NSText || firstResponder is NSTextView {
            return true
        }
        
        if let textField = firstResponder as? NSTextField, textField.isEditable {
            return true
        }
        
        return false
    }
}

extension View {
    func contentViewNotificationHandlers(
        shouldFocusSearch: Binding<Bool>,
        showingSettings: Binding<Bool>,
        selectedTab: Binding<Sections>,
        libraryManager: LibraryManager,
        pendingLibraryFilter: Binding<LibraryFilterRequest?>,
        showTrackDetail: @escaping (Track) -> Void
    ) -> some View {
        self
            .onReceive(NotificationCenter.default.publisher(for: .focusSearchField)) { _ in
                shouldFocusSearch.wrappedValue.toggle()
            }
            .onReceive(NotificationCenter.default.publisher(for: .goToLibraryFilter)) { notification in
                if let filterType = notification.userInfo?["filterType"] as? LibraryFilterType,
                   let filterValue = notification.userInfo?["filterValue"] as? String {
                    withAnimation(.easeInOut(duration: AnimationDuration.standardDuration)) {
                        selectedTab.wrappedValue = .library
                        pendingLibraryFilter.wrappedValue = LibraryFilterRequest(filterType: filterType, value: filterValue)
                    }
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("ShowTrackInfo"))) { notification in
                if let track = notification.userInfo?["track"] as? Track {
                    showTrackDetail(track)
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("OpenSettings"))) { _ in
                showingSettings.wrappedValue = true
            }
            .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("OpenSettingsAboutTab"))) { _ in
                showingSettings.wrappedValue = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    NotificationCenter.default.post(
                        name: NSNotification.Name("SettingsSelectTab"),
                        object: SettingsView.SettingsTab.about
                    )
                }
            }
    }
}

// MARK: - Create Playlist Sheet

struct CreatePlaylistSheet: View {
    @EnvironmentObject var playlistManager: PlaylistManager
    @Binding var isPresented: Bool
    @Binding var playlistName: String
    let tracksToAdd: [Track]
    let onCreate: () -> Void
    
    var body: some View {
        VStack(spacing: 20) {
            Text("New Playlist")
                .font(.headline)

            TextField("Playlist Name", text: $playlistName)
                .textFieldStyle(.roundedBorder)
                .frame(width: 250)
                .onSubmit {
                    if !playlistName.isEmpty {
                        onCreate()
                    }
                }

            if !tracksToAdd.isEmpty {
                Text("Will add: \(tracksToAdd.count) track\(tracksToAdd.count == 1 ? "" : "s")")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            HStack(spacing: 12) {
                Button("Cancel") {
                    playlistName = ""
                    isPresented = false
                }
                .keyboardShortcut(.escape)

                Button("Create") {
                    onCreate()
                }
                .keyboardShortcut(.return)
                .disabled(playlistName.isEmpty)
            }
        }
        .padding(30)
        .frame(width: 350)
    }
}

// MARK: - Window Accessor

struct WindowAccessor: NSViewRepresentable {
    let windowDelegate: WindowDelegate

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            if let window = view.window {
                window.delegate = windowDelegate
                window.identifier = NSUserInterfaceItemIdentifier("MainWindow")
                window.setFrameAutosaveName("MainWindow")
                WindowManager.shared.mainWindow = window
                window.title = ""
                window.isExcludedFromWindowsMenu = true
            }
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}

// MARK: - Window Manager

class WindowManager {
    static let shared = WindowManager()
    weak var mainWindow: NSWindow?

    private init() {}
}

// MARK: - Preview

#Preview {
    ContentView()
        .environmentObject({
            let coordinator = AppCoordinator()
            return coordinator.playbackManager
        }())
        .environmentObject({
            let coordinator = AppCoordinator()
            NotificationManager.shared.isActivityInProgress = true
            coordinator.libraryManager.folders = [Folder(url: URL(fileURLWithPath: "/Music"))]
            return coordinator.libraryManager
        }())
        .environmentObject({
            let coordinator = AppCoordinator()
            return coordinator.playlistManager
        }())
}
