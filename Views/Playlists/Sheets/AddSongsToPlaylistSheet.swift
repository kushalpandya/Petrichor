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

    // Cache playlist track database IDs for faster lookup
    private var playlistTrackDatabaseIDs: Set<Int64> {
        Set(playlist.tracks.compactMap { $0.trackId })
    }

    enum SortOrder: String, CaseIterable {
        case title = "Title"
        case artist = "Artist"
        case album = "Album"
        case dateAdded = "Date Added"

        var icon: String {
            switch self {
            case .title: return "textformat"
            case .artist: return "person"
            case .album: return "opticaldisc"
            case .dateAdded: return "calendar"
            }
        }
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
            if !visibleTracks.isEmpty {
                selectAllHeader
                Divider()
            }

            // Track list using List for better performance
            if libraryManager.tracks.isEmpty {
                emptyLibrary
            } else {
                // Using List instead of ScrollView for better performance
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

                    Text("Select all \(selectableTracksCount) results")
                        .font(.system(size: 13))

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
        .background(Color(NSColor.controlBackgroundColor).opacity(0.3))
    }

    private var sheetHeader: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Add Songs to \"\(playlist.name)\"")
                    .font(.headline)

                Text("Select songs to add or remove from this playlist")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            Button(action: { dismiss() }) {
                Image(systemName: "xmark.circle.fill")
                    .font(.title2)
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
    }

    private var controlsSection: some View {
        HStack(spacing: 16) {
            // Search field
            HStack {
                Image(systemName: Icons.magnifyingGlass)
                    .foregroundColor(.secondary)

                TextField("Search by title, artist, album, or genre...", text: $searchText)
                    .textFieldStyle(.plain)

                if !searchText.isEmpty {
                    Button(action: { searchText = "" }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(Color(NSColor.textBackgroundColor))
            .cornerRadius(6)

            // Sort picker
            Picker("Sort by", selection: $sortOrder) {
                ForEach(SortOrder.allCases, id: \.self) { order in
                    Label(order.rawValue, systemImage: order.icon)
                        .tag(order)
                }
            }
            .pickerStyle(.menu)
            .frame(width: 120)
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
    }

    private var emptyLibrary: some View {
        VStack(spacing: 16) {
            Image(systemName: Icons.musicNoteList)
                .font(.system(size: 48))
                .foregroundColor(.gray)

            Text("No Music in Library")
                .font(.headline)

            Text("Add some music to your library first")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(NSColor.textBackgroundColor))
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
        let filtered: [Track]

        let availableTracks = hideDuplicateTracks ?
            libraryManager.tracks.filter { !$0.isDuplicate } :
            libraryManager.tracks
        
        if searchText.isEmpty {
            // No search - show all library tracks (playlist status will be determined by playlistTrackIDs)
            filtered = availableTracks
        } else {
            // When searching, only show library tracks that match
            let searchLower = searchText.lowercased()
            filtered = availableTracks.filter { track in
                track.title.lowercased().contains(searchLower) ||
                track.artist.lowercased().contains(searchLower) ||
                track.album.lowercased().contains(searchLower) ||
                track.genre.lowercased().contains(searchLower)
            }
        }

        return filtered.sorted { track1, track2 in
            switch sortOrder {
            case .title:
                return track1.title.localizedCaseInsensitiveCompare(track2.title) == .orderedAscending
            case .artist:
                return track1.artist.localizedCaseInsensitiveCompare(track2.artist) == .orderedAscending
            case .album:
                return track1.album.localizedCaseInsensitiveCompare(track2.album) == .orderedAscending
            case .dateAdded:
                return track1.title.localizedCaseInsensitiveCompare(track2.title) == .orderedAscending
            }
        }
    }

    private var hasChanges: Bool {
        !selectedTracks.isEmpty || !tracksToRemove.isEmpty
    }

    private var actionButtonTitle: String {
        var parts: [String] = []

        if !selectedTracks.isEmpty {
            parts.append("Add \(selectedTracks.count)")
        }

        if !tracksToRemove.isEmpty {
            parts.append("Remove \(tracksToRemove.count)")
        }

        return parts.isEmpty ? "Apply" : parts.joined(separator: ", ")
    }

    private var selectionInfoText: String {
        var parts: [String] = []

        if !selectedTracks.isEmpty {
            parts.append("\(selectedTracks.count) to add")
        }

        if !tracksToRemove.isEmpty {
            parts.append("\(tracksToRemove.count) to remove")
        }

        return parts.isEmpty ? "No changes" : parts.joined(separator: ", ")
    }

    // MARK: - Actions

    private func toggleSelectAll() {
        let selectableTracks = visibleTracks.filter { track in
            guard let trackId = track.trackId else { return true }
            return !playlistTrackDatabaseIDs.contains(trackId)
        }

        if allSelectableTracksSelected {
            // Deselect all
            selectedTracks.removeAll()
        } else {
            // Select all tracks not in playlist
            for track in selectableTracks {
                selectedTracks.insert(track.id)
            }
        }

        // Don't auto-select tracks for removal
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
        // Collect tracks to add
        var tracksToAdd: [Track] = []
        for trackId in selectedTracks {
            if let track = libraryManager.tracks.first(where: { $0.id == trackId }) {
                tracksToAdd.append(track)
            }
        }

        // Collect tracks to remove
        var tracksToRemoveList: [Track] = []
        for trackId in tracksToRemove {
            if let track = libraryManager.tracks.first(where: { $0.id == trackId }) {
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

        dismiss()
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
