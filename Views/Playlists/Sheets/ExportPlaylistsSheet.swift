import SwiftUI

struct ExportPlaylistsSheet: View {
    @EnvironmentObject var playlistManager: PlaylistManager
    @Binding var isPresented: Bool
    
    @State private var selectedPlaylistIds: Set<UUID> = []
    @State private var selectAll: Bool = false
    
    private var exportablePlaylists: [Playlist] {
        playlistManager.playlists.filter { $0.type == .regular }
    }
    
    private var selectedCount: Int {
        selectedPlaylistIds.count
    }
    
    var body: some View {
        VStack(spacing: 0) {
            sheetHeader
            Divider()
            playlistList
            Divider()
            sheetFooter
        }
        .frame(width: 500, height: 600)
        .onAppear {
            selectAllPlaylists()
        }
    }
    
    // MARK: - Header
    
    private var sheetHeader: some View {
        HStack {
            Button(action: { isPresented = false }) {
                Image(systemName: Icons.xmarkCircleFill)
                    .font(.system(size: 18))
                    .foregroundColor(.secondary)
                    .background(Circle().fill(Color.clear))
            }
            .help("Dismiss")
            .buttonStyle(.plain)
            .keyboardShortcut(.escape)
            .focusable(false)
            
            Text("Export Playlists")
                .font(.headline)
            
            Spacer()
        }
        .padding()
    }
    
    // MARK: - Playlist List
    
    private var playlistList: some View {
        VStack(spacing: 0) {
            Text("Select playlists to export:")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal)
                .padding(.top, 12)
                .padding(.bottom, 8)
            
            HStack {
                Toggle(isOn: $selectAll) {
                    Text("Select All (\(exportablePlaylists.count))")
                        .font(.subheadline)
                        .fontWeight(.medium)
                }
                .toggleStyle(.checkbox)
                .onChange(of: selectAll) { _, newValue in
                    newValue ? selectAllPlaylists() : deselectAllPlaylists()
                }
                
                Spacer()
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
            
            Divider()
            
            if exportablePlaylists.isEmpty {
                emptyState
            } else {
                playlistScrollView
            }
        }
    }
    
    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "music.note.list")
                .font(.system(size: 48))
                .foregroundColor(.secondary)
            
            Text("No playlists to export")
                .font(.headline)
                .foregroundColor(.secondary)
            
            Text("Create some playlists first")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
    
    private var playlistScrollView: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(exportablePlaylists) { playlist in
                    playlistRow(playlist)
                    
                    if playlist.id != exportablePlaylists.last?.id {
                        Divider()
                            .padding(.leading, 44)
                    }
                }
            }
        }
    }
    
    private func playlistRow(_ playlist: Playlist) -> some View {
        HStack(spacing: 12) {
            Toggle(isOn: Binding(
                get: { selectedPlaylistIds.contains(playlist.id) },
                set: { isSelected in
                    if isSelected {
                        selectedPlaylistIds.insert(playlist.id)
                    } else {
                        selectedPlaylistIds.remove(playlist.id)
                        selectAll = false
                    }
                    updateSelectAllState()
                }
            )) {
                EmptyView()
            }
            .toggleStyle(.checkbox)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(playlist.name)
                    .font(.body)
                    .lineLimit(1)
                
                Text("\(playlist.trackCount) \(playlist.trackCount == 1 ? "track" : "tracks")")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .contentShape(Rectangle())
        .onTapGesture {
            toggleSelection(for: playlist.id)
        }
    }
    
    // MARK: - Footer
    
    private var sheetFooter: some View {
        HStack {
            Spacer()
            
            Button("Cancel") {
                isPresented = false
            }
            .keyboardShortcut(.cancelAction)
            
            Button(action: exportSelectedPlaylists) {
                Text("Export (\(selectedCount))")
            }
            .keyboardShortcut(.defaultAction)
            .disabled(selectedCount == 0)
        }
        .padding()
    }
    
    // MARK: - Actions
    
    private func selectAllPlaylists() {
        selectedPlaylistIds = Set(exportablePlaylists.map { $0.id })
        selectAll = true
    }
    
    private func deselectAllPlaylists() {
        selectedPlaylistIds.removeAll()
        selectAll = false
    }
    
    private func toggleSelection(for playlistId: UUID) {
        if selectedPlaylistIds.contains(playlistId) {
            selectedPlaylistIds.remove(playlistId)
            selectAll = false
        } else {
            selectedPlaylistIds.insert(playlistId)
        }
        updateSelectAllState()
    }
    
    private func updateSelectAllState() {
        selectAll = selectedPlaylistIds.count == exportablePlaylists.count
    }
    
    private func exportSelectedPlaylists() {
        guard !selectedPlaylistIds.isEmpty else { return }
        
        let playlistsToExport = exportablePlaylists.filter { selectedPlaylistIds.contains($0.id) }
        
        let panel = NSOpenPanel()
        panel.title = "Export Playlists"
        panel.message = "Choose where to save \(playlistsToExport.count) playlist file\(playlistsToExport.count == 1 ? "" : "s")"
        panel.prompt = "Export"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        
        panel.begin { response in
            guard response == .OK, let directoryURL = panel.url else { return }
            
            isPresented = false
            NotificationManager.shared.startActivity("Exporting playlists...")
            
            Task {
                let result = await playlistManager.exportPlaylists(playlistsToExport, to: directoryURL)
                
                await MainActor.run {
                    NotificationManager.shared.stopActivity()
                    showExportNotifications(result: result, directory: directoryURL)
                }
            }
        }
    }
    
    private func showExportNotifications(result: BulkExportResult, directory: URL) {
        func pluralize(_ count: Int, singular: String) -> String {
            count == 1 ? singular : "\(singular)s"
        }
        
        var notifications: [(type: NotificationType, message: String)] = []
        
        for (playlistName, error) in result.failed {
            notifications.append((.error, "Failed to export '\(playlistName)': \(error.localizedDescription)"))
        }
        
        if result.successful > 0 {
            let message = "Exported \(result.successful) \(pluralize(result.successful, singular: "playlist")) to \(directory.lastPathComponent)"
            notifications.append((.info, message))
        }
        
        if result.totalPlaylists > 0 && result.successful == 0 {
            let message = "Failed to export all \(result.totalPlaylists) \(pluralize(result.totalPlaylists, singular: "playlist"))"
            notifications.append((.error, message))
        }
        
        for notification in notifications {
            NotificationManager.shared.addMessage(notification.type, notification.message)
        }
    }
}

// MARK: - Preview

#Preview("Export Playlists Sheet") {
    @Previewable @State var isPresented = true
    
    let previewManager = {
        let manager = PlaylistManager()
        
        var track1 = Track(url: URL(fileURLWithPath: "/sample1.mp3"))
        track1.title = "Sample Song 1"
        
        var track2 = Track(url: URL(fileURLWithPath: "/sample2.mp3"))
        track2.title = "Sample Song 2"
        
        manager.playlists = [
            Playlist(name: "Summer Mix", tracks: [track1, track2]),
            Playlist(name: "Workout Beats", tracks: [track1]),
            Playlist(name: "Chill Vibes", tracks: [track2]),
            Playlist(name: "Road Trip", tracks: []),
            Playlist(name: "Indie Rock", tracks: [track1, track2]),
            Playlist(
                name: DefaultPlaylists.favorites,
                criteria: SmartPlaylistCriteria(
                    rules: [SmartPlaylistCriteria.Rule(
                        field: "isFavorite",
                        condition: .equals,
                        value: "true"
                    )],
                    sortBy: "title",
                    sortAscending: true
                ),
                isUserEditable: false
            )
        ]
        
        return manager
    }()
    
    return ExportPlaylistsSheet(isPresented: $isPresented)
        .environmentObject(previewManager)
}

#Preview("Empty State") {
    @Previewable @State var isPresented = true
    
    let emptyManager = PlaylistManager()
    
    return ExportPlaylistsSheet(isPresented: $isPresented)
        .environmentObject(emptyManager)
}
