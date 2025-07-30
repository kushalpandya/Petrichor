import SwiftUI

struct AddSongsToPlaylistSheet: View {
    @AppStorage("hideDuplicateTracks")
    private var hideDuplicateTracks: Bool = true

    let playlist: Playlist
    @Environment(\.dismiss)
    private var dismiss
    @EnvironmentObject var libraryManager: LibraryManager
    @EnvironmentObject var playlistManager: PlaylistManager

    @State private var searchText = ""
    @State private var selectedTracks: Set<UUID> = []
    @State private var tracksToRemove: Set<UUID> = []
    @State private var sortOrder: SortOrder = .title
    @State private var searchResults: [Track] = []
    @State private var isSearching = false
    @State private var hasSearched = false
    @State private var searchTask: Task<Void, Never>?

    // Cache playlist track database IDs for faster lookup
    private var playlistTrackDatabaseIDs: Set<Int64> {
        Set(playlist.tracks.compactMap { $0.trackId })
    }

    enum SortOrder: String, CaseIterable {
        case title = "Title"
        case artist = "Artist"
        case album = "Album"
        case dateAdded = "Date Added"
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            sheetHeader

            Divider()

            // Search and sort controls
            controlsSection

            Divider()

            // Select all header
            if !searchResults.isEmpty {
                selectAllHeader
                Divider()
            }

            // Track list
            if !hasSearched {
                // Show search prompt
                searchPromptView
            } else if isSearching {
                // Show loading state
                loadingView
            } else if searchResults.isEmpty {
                // Show no results
                noResultsView
            } else {
                // Show results using List for performance
                List(visibleTracks, id: \.id) { track in
                    TrackSelectionRow(
                        track: track,
                        isSelected: selectedTracks.contains(track.id),
                        isAlreadyInPlaylist: track.trackId != nil && playlistTrackDatabaseIDs.contains(track.trackId!),
                        isMarkedForRemoval: tracksToRemove.contains(track.id)
                    ) {
                        toggleTrackSelection(track)
                    }
                    .listRowSeparator(.visible)
                    .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
                }
                .listStyle(.plain)
                .background(Color(NSColor.textBackgroundColor))
            }

            Divider()

            // Footer with action buttons
            sheetFooter
        }
        .frame(width: 600, height: 700)
        .onDisappear {
            // Clean up memory when sheet is dismissed
            searchResults = []
            selectedTracks = []
            tracksToRemove = []
            searchText = ""
            hasSearched = false
        }
    }

    // MARK: - Cached Properties

    // Cache playlist track IDs for faster lookup
    private var playlistTrackIDs: Set<UUID> {
        Set(playlist.tracks.map { $0.id })
    }

    // MARK: - Subviews

    private var selectAllHeader: some View {
        HStack {
            Button(action: toggleSelectAll) {
                HStack(spacing: 8) {
                    Image(systemName: selectAllCheckboxImage)
                        .font(.system(size: 16))
                        .foregroundColor(selectAllCheckboxColor)

                    HStack(spacing: 4) {
                        Text("Select all \(selectableTracksCount)")
                            .font(.system(size: 13))
                        
                        if inPlaylistTracksCount > 0 {
                            Text("(\(inPlaylistTracksCount) already in playlist)")
                                .font(.system(size: 13))
                                .foregroundColor(.secondary)
                        }
                    }

                    if !searchText.isEmpty {
                        Text("for \"\(searchText)\"")
                            .font(.system(size: 13))
                            .foregroundColor(.secondary)
                    }
                }
            }
            .buttonStyle(.plain)

            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Color(NSColor.windowBackgroundColor))
    }

    private var sheetHeader: some View {
        HStack {
            // Close button
            Button(action: { dismiss() }) {
                Image(systemName: Icons.xmarkCircleFill)
                    .font(.system(size: 18))
                    .foregroundColor(.secondary)
                    .background(Circle().fill(Color.clear))
            }
            .help("Dismiss")
            .buttonStyle(.plain)
            .keyboardShortcut(.escape)
            .focusable(false)
            
            VStack(alignment: .leading, spacing: 4) {
                Text("Add Songs to Playlist")
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                Text(playlist.name)
                    .font(.headline)
            }

            Spacer()

            // Stats
            VStack(alignment: .trailing, spacing: 4) {
                Text("\(playlist.tracks.count) songs")
                    .font(.caption)
                    .foregroundColor(.secondary)

                if !selectedTracks.isEmpty || !tracksToRemove.isEmpty {
                    HStack(spacing: 4) {
                        if !selectedTracks.isEmpty {
                            Text("+\(selectedTracks.count)")
                                .font(.caption)
                                .foregroundColor(.green)
                        }
                        if !tracksToRemove.isEmpty {
                            Text("-\(tracksToRemove.count)")
                                .font(.caption)
                                .foregroundColor(.red)
                        }
                    }
                }
            }
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor).opacity(0.3))
    }

    private var controlsSection: some View {
        HStack(spacing: 12) {
            // Search field
            HStack {
                Image(systemName: Icons.magnifyingGlass)
                    .foregroundColor(.secondary)

                TextField("Search songs...", text: $searchText)
                    .textFieldStyle(.plain)
                    .onSubmit {
                        performSearch()
                    }
                    .onChange(of: searchText) {
                        performSearch()
                    }

                if !searchText.isEmpty {
                    Button(action: {
                        searchText = ""
                        performSearch()
                    }) {
                        Image(systemName: Icons.xmarkCircleFill)
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(8)
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(6)
            .frame(maxWidth: .infinity)

            // Sort picker
            Picker("Sort by", selection: $sortOrder) {
                ForEach(SortOrder.allCases, id: \.self) { order in
                    Text(order.rawValue)
                        .tag(order)
                }
            }
            .pickerStyle(.menu)
            .frame(width: 150)
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
    }

    private var sheetFooter: some View {
        HStack {
            // Selection info
            Text(selectionInfoText)
                .font(.caption)
                .foregroundColor(.secondary)

            Spacer()

            // Action buttons
            HStack(spacing: 12) {
                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.escape)

                Button(actionButtonTitle) {
                    applyChanges()
                }
                .keyboardShortcut(.return)
                .disabled(!hasChanges)
            }
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor).opacity(0.3))
    }

    // MARK: - Helper Properties

    private var selectableTracksCount: Int {
        visibleTracks.filter { track in
            guard let trackId = track.trackId else { return true }
            return !playlistTrackDatabaseIDs.contains(trackId)
        }.count
    }
    
    private var inPlaylistTracksCount: Int {
        visibleTracks.filter { track in
            guard let trackId = track.trackId else { return false }
            return playlistTrackDatabaseIDs.contains(trackId)
        }.count
    }

    private var allSelectableTracksSelected: Bool {
        let selectableTracks = visibleTracks.filter { track in
            guard let trackId = track.trackId else { return true }
            return !playlistTrackDatabaseIDs.contains(trackId)
        }
        return !selectableTracks.isEmpty && selectableTracks.allSatisfy { selectedTracks.contains($0.id) }
    }

    private var someSelectableTracksSelected: Bool {
        let selectableTracks = visibleTracks.filter { track in
            guard let trackId = track.trackId else { return true }
            return !playlistTrackDatabaseIDs.contains(trackId)
        }
        let selectedCount = selectableTracks.filter { selectedTracks.contains($0.id) }.count
        return selectedCount > 0 && selectedCount < selectableTracks.count
    }

    private var selectAllCheckboxImage: String {
        if allSelectableTracksSelected {
            return Icons.checkmarkSquareFill
        } else if someSelectableTracksSelected {
            return Icons.minusSquareFill
        } else {
            return Icons.square
        }
    }

    private var selectAllCheckboxColor: Color {
        if allSelectableTracksSelected || someSelectableTracksSelected {
            return .accentColor
        } else {
            return .secondary
        }
    }

    private var visibleTracks: [Track] {
        // Return search results directly since we're already filtering in performSearch
        let sorted: [Track]
        
        switch sortOrder {
        case .title:
            sorted = searchResults.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
        case .artist:
            sorted = searchResults.sorted { $0.artist.localizedCaseInsensitiveCompare($1.artist) == .orderedAscending }
        case .album:
            sorted = searchResults.sorted { $0.album.localizedCaseInsensitiveCompare($1.album) == .orderedAscending }
        case .dateAdded:
            sorted = searchResults.sorted { first, second in
                let firstDate = first.dateAdded ?? Date()
                let secondDate = second.dateAdded ?? Date()
                return firstDate > secondDate
            }
        }
        
        return sorted
    }

    private var hasChanges: Bool {
        !selectedTracks.isEmpty || !tracksToRemove.isEmpty
    }

    private var selectionInfoText: String {
        let addCount = selectedTracks.count
        let removeCount = tracksToRemove.count

        if addCount > 0 && removeCount > 0 {
            return "\(addCount) to add, \(removeCount) to remove"
        } else if addCount > 0 {
            return "\(addCount) song\(addCount == 1 ? "" : "s") to add"
        } else if removeCount > 0 {
            return "\(removeCount) song\(removeCount == 1 ? "" : "s") to remove"
        } else {
            return "\(visibleTracks.count) song\(visibleTracks.count == 1 ? "" : "s")"
        }
    }

    private var actionButtonTitle: String {
        let addCount = selectedTracks.count
        let removeCount = tracksToRemove.count

        if addCount > 0 && removeCount > 0 {
            return "Apply Changes"
        } else if addCount > 0 {
            return "Add \(addCount) Song\(addCount == 1 ? "" : "s")"
        } else if removeCount > 0 {
            return "Remove \(removeCount) Song\(removeCount == 1 ? "" : "s")"
        } else {
            return "Done"
        }
    }

    // MARK: - Actions

    private func toggleSelectAll() {
        let selectableTracks = visibleTracks.filter { track in
            guard let trackId = track.trackId else { return true }
            return !playlistTrackDatabaseIDs.contains(trackId)
        }

        if allSelectableTracksSelected {
            // Deselect all
            for track in selectableTracks {
                selectedTracks.remove(track.id)
            }
        } else {
            // Select all
            for track in selectableTracks {
                selectedTracks.insert(track.id)
            }
        }
    }

    private func toggleTrackSelection(_ track: Track) {
        let isInPlaylist = track.trackId != nil && playlistTrackDatabaseIDs.contains(track.trackId!)

        if isInPlaylist {
            // Track is in playlist - toggle removal
            if tracksToRemove.contains(track.id) {
                tracksToRemove.remove(track.id)
            } else {
                tracksToRemove.insert(track.id)
            }
        } else {
            // Track not in playlist - toggle addition
            if selectedTracks.contains(track.id) {
                selectedTracks.remove(track.id)
            } else {
                selectedTracks.insert(track.id)
            }
        }
    }

    private func applyChanges() {
        // Collect tracks to add from search results instead of libraryManager.tracks
        var tracksToAdd: [Track] = []
        for trackId in selectedTracks {
            if let track = searchResults.first(where: { $0.id == trackId }) {
                tracksToAdd.append(track)
            }
        }

        // Collect tracks to remove from search results
        var tracksToRemoveList: [Track] = []
        for trackId in tracksToRemove {
            if let track = searchResults.first(where: { $0.id == trackId }) {
                tracksToRemoveList.append(track)
            }
        }

        // Apply operations
        for track in tracksToAdd {
            playlistManager.addTrackToPlaylist(track: track, playlistID: playlist.id)
        }

        for track in tracksToRemoveList {
            playlistManager.removeTrackFromPlaylist(track: track, playlistID: playlist.id)
        }

        // Clean up before dismissing
        searchResults = []
        selectedTracks = []
        tracksToRemove = []
        
        dismiss()
    }

    private func performSearch() {
        // Cancel any existing search
        searchTask?.cancel()
        
        let trimmedQuery = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Clear results if search is empty or too short
        guard !trimmedQuery.isEmpty else {
            searchResults = []
            hasSearched = false
            return
        }
        
        // Require at least 2 characters
        guard trimmedQuery.count >= 2 else {
            searchResults = []
            hasSearched = true
            isSearching = false
            return
        }
        
        isSearching = true
        hasSearched = true
        
        // Create new search task with debouncing
        searchTask = Task {
            // Debounce: wait 300ms
            try? await Task.sleep(nanoseconds: 300_000_000)
            
            // Check if task was cancelled
            guard !Task.isCancelled else { return }
            
            // Use LibrarySearch as requested
            let allResults = LibrarySearch.searchTracks([], with: trimmedQuery)

            // Separate tracks into those in playlist and those not
            let playlistTrackIds = Set(playlist.tracks.compactMap { $0.trackId })
            var tracksInPlaylist: [Track] = []
            var tracksNotInPlaylist: [Track] = []

            for track in allResults {
                if let trackId = track.trackId, playlistTrackIds.contains(trackId) {
                    tracksInPlaylist.append(track)
                } else {
                    tracksNotInPlaylist.append(track)
                }
            }

            let combinedResults = tracksInPlaylist + tracksNotInPlaylist

            await MainActor.run {
                guard !Task.isCancelled else { return }
                searchResults = combinedResults
                isSearching = false
            }
        }
    }

    // MARK: - Search State Views

    private var searchPromptView: some View {
        VStack(spacing: 16) {
            Image(systemName: Icons.magnifyingGlass)
                .font(.system(size: 48))
                .foregroundColor(.gray)
            
            Text("Search for songs to add")
                .font(.headline)
            
            Text("Enter a search term above to find songs")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(NSColor.textBackgroundColor))
    }

    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .scaleEffect(1.5)
            
            Text("Searching...")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(NSColor.textBackgroundColor))
    }

    private var noResultsView: some View {
        VStack(spacing: 16) {
            Image(systemName: Icons.magnifyingGlass)
                .font(.system(size: 48))
                .foregroundColor(.gray)
            
            if searchText.trimmingCharacters(in: .whitespacesAndNewlines).count < 2 {
                Text("Search term too short")
                    .font(.headline)
                
                Text("Enter at least 2 characters to search")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            } else {
                Text("No results found")
                    .font(.headline)
                
                Text("Try a different search term")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(NSColor.textBackgroundColor))
    }
}

// MARK: - Simple Row Component

struct TrackSelectionRow: View {
    let track: Track
    let isSelected: Bool
    let isAlreadyInPlaylist: Bool
    let isMarkedForRemoval: Bool
    let onToggle: () -> Void

    var body: some View {
        Button(action: onToggle) {
            HStack(spacing: 12) {
                // Checkbox
                Image(systemName: checkboxImage)
                    .font(.system(size: 16))
                    .foregroundColor(checkboxColor)
                    .frame(width: 20)

                // Track info
                VStack(alignment: .leading, spacing: 2) {
                    Text(track.title)
                        .font(.system(size: 13))
                        .lineLimit(1)
                        .foregroundColor(textColor)
                        .strikethrough(isMarkedForRemoval)

                    Text("\(track.artist) • \(track.album)")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }

                Spacer()

                // Status
                if isAlreadyInPlaylist && !isMarkedForRemoval {
                    Text("In playlist")
                        .font(.caption)
                        .foregroundColor(.secondary)
                } else if isMarkedForRemoval {
                    Text("Will remove")
                        .font(.caption)
                        .foregroundColor(.red)
                } else if isSelected {
                    Text("Will add")
                        .font(.caption)
                        .foregroundColor(.green)
                }

                // Duration
                Text(formatDuration(track.duration))
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .monospacedDigit()
            }
            .padding(.vertical, 6)
        }
        .buttonStyle(.plain)
        .background(backgroundColor)
    }

    private var checkboxImage: String {
        if isAlreadyInPlaylist {
            return isMarkedForRemoval ? "xmark.square.fill" : Icons.checkmarkSquareFill
        } else {
            return isSelected ? Icons.checkmarkSquareFill : Icons.square
        }
    }

    private var checkboxColor: Color {
        if isMarkedForRemoval {
            return .red
        } else if isSelected || isAlreadyInPlaylist {
            return .accentColor
        } else {
            return .secondary
        }
    }

    private var textColor: Color {
        if isMarkedForRemoval {
            return .secondary
        } else {
            return .primary
        }
    }

    private var backgroundColor: Color {
        if isMarkedForRemoval {
            return Color.red.opacity(0.08)
        } else if isSelected && !isAlreadyInPlaylist {
            return Color.accentColor.opacity(0.08)
        } else {
            return Color.clear
        }
    }

    private func formatDuration(_ seconds: Double) -> String {
        let minutes = Int(seconds) / 60
        let seconds = Int(seconds) % 60
        return String(format: StringFormat.mmss, minutes, seconds)
    }
}

#Preview {
    AddSongsToPlaylistSheet(playlist: Playlist(name: "My Playlist", tracks: []))
        .environmentObject(LibraryManager())
        .environmentObject(PlaylistManager())
}
