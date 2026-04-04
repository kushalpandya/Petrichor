import SwiftUI

struct ReorderTracksSheet: View {
    let playlist: Playlist
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var playlistManager: PlaylistManager

    @State private var reorderedTracks: [Track] = []
    @State private var hasChanges = false

    var body: some View {
        VStack(spacing: 0) {
            sheetHeader

            Divider()

            infoBar

            Divider()

            trackList

            Divider()

            sheetFooter
        }
        .frame(width: 600, height: 700)
        .onAppear {
            reorderedTracks = playlist.tracks
        }
    }

    // MARK: - Header

    private var sheetHeader: some View {
        HStack {
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
                Text("Reorder Tracks")
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                Text(playlist.name)
                    .font(.headline)
            }

            Spacer()

            Text("\(reorderedTracks.count) songs")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor).opacity(0.3))
    }

    // MARK: - Info Bar

    private var infoBar: some View {
        HStack {
            Image(systemName: "info.circle")
                .font(.system(size: 12))
                .foregroundColor(.secondary)

            Text("Drag items to reorder")
                .font(.system(size: 12))
                .foregroundColor(.secondary)

            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    // MARK: - Track List

    private var trackList: some View {
        List {
            ForEach(reorderedTracks) { track in
                ReorderTrackRow(track: track)
                    .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
            }
            .onMove(perform: moveTrack)
        }
        .listStyle(.plain)
    }

    // MARK: - Footer

    private var sheetFooter: some View {
        HStack {
            Text(hasChanges ? "Order changed" : "\(reorderedTracks.count) songs")
                .font(.caption)
                .foregroundColor(.secondary)

            Spacer()

            HStack(spacing: 12) {
                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.escape)

                Button("Save") {
                    saveOrder()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.return)
                .disabled(!hasChanges)
            }
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor).opacity(0.3))
    }

    // MARK: - Actions

    private func moveTrack(from source: IndexSet, to destination: Int) {
        reorderedTracks.move(fromOffsets: source, toOffset: destination)
        hasChanges = true
    }

    private func saveOrder() {
        let playlistID = playlist.id
        let tracks = reorderedTracks

        dismiss()

        Task {
            await playlistManager.reorderPlaylistTracks(playlistID: playlistID, reorderedTracks: tracks)

            await MainActor.run {
                PlaylistSortManager.shared.setSortField(.custom, for: playlistID)

                NotificationCenter.default.post(
                    name: .trackTableSortChanged,
                    object: nil,
                    userInfo: ["isCustomSort": true]
                )
            }
        }
    }
}

// MARK: - Track Row

private struct ReorderTrackRow: View {
    let track: Track

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "line.3.horizontal")
                .font(.system(size: 12))
                .foregroundColor(.secondary.opacity(0.5))

            VStack(alignment: .leading, spacing: 2) {
                Text(track.title)
                    .font(.system(size: 13))
                    .lineLimit(1)

                Text("\(track.artist) • \(track.album)")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            Text(formatDuration(track.duration))
                .font(.system(size: 11))
                .foregroundColor(.secondary)
                .monospacedDigit()
        }
        .padding(.vertical, 4)
    }

    private func formatDuration(_ seconds: Double) -> String {
        let minutes = Int(seconds) / 60
        let seconds = Int(seconds) % 60
        return String(format: StringFormat.mmss, minutes, seconds)
    }
}

#Preview {
    ReorderTracksSheet(playlist: Playlist(name: "My Playlist", tracks: []))
        .environmentObject(PlaylistManager())
}
