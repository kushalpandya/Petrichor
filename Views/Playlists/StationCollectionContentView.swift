import SwiftUI

/// The body of a station collection in `PlaylistDetailView`.
struct StationCollectionContentView: View {
    let collection: Playlist
    let stations: [RadioStation]
    let onEdit: () -> Void

    @EnvironmentObject var playlistManager: PlaylistManager

    @State private var stationsPendingRemoval: [RadioStation] = []

    var body: some View {
        if stations.isEmpty {
            emptyView
        } else {
            // Confirmed, unlike the context menu's Remove: Delete is easy to hit by
            // accident, and the collection's order isn't recoverable by re-adding.
            StationTableView(
                stations: stations,
                contextMenuItems: contextMenuItems
            ) { stationsPendingRemoval = $0 }
            .alert(removalAlertTitle, isPresented: removalAlertBinding) {
                Button("Cancel", role: .cancel) { stationsPendingRemoval = [] }
                Button("Remove", role: .destructive) {
                    let toRemove = stationsPendingRemoval
                    Task { await playlistManager.removeStations(toRemove, from: collection) }
                    stationsPendingRemoval = []
                }
            } message: {
                if stationsPendingRemoval.count == 1, let station = stationsPendingRemoval.first {
                    Text("Remove \"\(station.name)\" from \"\(collection.name)\"?")
                } else {
                    Text("Remove \(stationsPendingRemoval.count) stations from \"\(collection.name)\"?")
                }
            }
        }
    }

    private var removalAlertTitle: LocalizedStringKey {
        stationsPendingRemoval.count == 1 ? "Remove Station" : "Remove Stations"
    }

    private var removalAlertBinding: Binding<Bool> {
        Binding(
            get: { !stationsPendingRemoval.isEmpty },
            set: { if !$0 { stationsPendingRemoval = [] } }
        )
    }

    private var emptyView: some View {
        VStack(spacing: 20) {
            Image(systemName: Icons.radioFill)
                .font(.system(size: 60))
                .foregroundColor(.gray)

            Text("No Stations")
                .font(.headline)

            Text("Add stations to this collection to see them here.")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 300)

            Button("Edit", action: onEdit)
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    private func contextMenuItems(for stations: [RadioStation]) -> [ContextMenuItem] {
        StationMenuBuilder.items(for: stations, playlistManager: playlistManager, removeFrom: collection)
    }
}
