import SwiftUI

struct InternetRadioView: View {
    @EnvironmentObject var playlistManager: PlaylistManager
    @ObservedObject private var radioManager = InternetRadioManager.shared

    @State private var stationsPendingDeletion: [RadioStation] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header

            Divider()

            // The spinner only stands in for an empty list; stored stations show at once.
            if radioManager.stations.isEmpty {
                if radioManager.isFetchingDefaults || !radioManager.hasLoadedStations {
                    fetchingView
                } else {
                    emptyStateView
                }
            } else {
                StationTableView(
                    stations: radioManager.stations,
                    contextMenuItems: contextMenuItems
                ) { stationsPendingDeletion = $0 }
            }
        }
        .alert(deletionAlertTitle, isPresented: deletionAlertBinding) {
            Button("Cancel", role: .cancel) { stationsPendingDeletion = [] }
            Button("Delete", role: .destructive) {
                let stations = stationsPendingDeletion
                Task { await radioManager.delete(stations) }
                stationsPendingDeletion = []
            }
        } message: {
            if stationsPendingDeletion.count == 1, let station = stationsPendingDeletion.first {
                Text("Are you sure you want to delete \"\(station.name)\"? This action cannot be undone.")
            } else {
                Text("Are you sure you want to delete \(stationsPendingDeletion.count) stations? This action cannot be undone.")
            }
        }
        // Opaque, matching PlaylistDetailView: a collection shows the same list, and a
        // transparent pane reads differently against the window in dark mode.
        .background(Color(NSColor.windowBackgroundColor))
    }

    private var header: some View {
        ListHeader(opaque: true) {
            Text("Internet Radio")
                .headerTitleStyle()

            Spacer()

            Button {
                radioManager.showAddStation()
            } label: {
                Label("Add station", systemImage: "plus")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .help("Add a new radio station")

            StationOptionsDropdown()
        }
    }

    // MARK: - States

    private var fetchingView: some View {
        VStack(spacing: 16) {
            Spacer()
            ActivityAnimation(size: .large)
            Text("Fetching popular stations...")
                .font(.headline)
                .foregroundColor(.secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyStateView: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: Icons.radioFill)
                .font(.system(size: 80))
                .foregroundColor(.secondary.opacity(0.5))

            VStack(spacing: 8) {
                Text("No Stations Yet")
                    .font(.largeTitle)
                    .fontWeight(.medium)

                Text("Add a station of your own, or start with some popular ones.")
                    .font(.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }

            Button {
                Task { await radioManager.downloadTopStations() }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: Icons.arrowDownCircleFill)
                        .font(.system(size: 16))
                    Text("Download Popular Stations")
                        .fontWeight(.medium)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 10)
                .background(Capsule().fill(Color.accentColor))
                .foregroundColor(.white)
            }
            .buttonStyle(.plain)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(40)
    }

    private func contextMenuItems(for stations: [RadioStation]) -> [ContextMenuItem] {
        StationMenuBuilder.items(for: stations, playlistManager: playlistManager) { toDelete in
            stationsPendingDeletion = toDelete
        }
    }

    private var deletionAlertTitle: LocalizedStringKey {
        stationsPendingDeletion.count == 1 ? "Delete Station" : "Delete Stations"
    }

    private var deletionAlertBinding: Binding<Bool> {
        Binding(
            get: { !stationsPendingDeletion.isEmpty },
            set: { if !$0 { stationsPendingDeletion = [] } }
        )
    }
}

// MARK: - Sort Dropdown

struct StationOptionsDropdown: View {
    @AppStorage("stationSortField")
    private var sortFieldRaw: String = StationSortField.name.rawValue

    @AppStorage("stationSortAscending")
    private var sortAscending: Bool = true

    @AppStorage("trackTableRowSize")
    private var tableRowSize: TableRowSize = .expanded

    private var sortField: StationSortField {
        StationSortField(rawValue: sortFieldRaw) ?? .name
    }

    var body: some View {
        Menu {
            Section("Sort by") {
                ForEach(StationSortField.allCases, id: \.self) { field in
                    Toggle(field.displayName, isOn: Binding(
                        get: { sortField == field },
                        set: { _ in sortFieldRaw = field.rawValue }
                    ))
                }
            }

            Divider()

            Section("Sort order") {
                Toggle("Ascending", isOn: Binding(get: { sortAscending }, set: { _ in sortAscending = true }))
                Toggle("Descending", isOn: Binding(get: { !sortAscending }, set: { _ in sortAscending = false }))
            }

            Divider()

            Section("Row size") {
                ForEach([TableRowSize.expanded, TableRowSize.compact], id: \.self) { size in
                    Toggle(size.displayName, isOn: Binding(
                        get: { tableRowSize == size },
                        set: { _ in setRowSize(size) }
                    ))
                }
            }
        } label: {
            Image(systemName: Icons.sortMenu)
                .font(.system(size: 14))
                .foregroundColor(.secondary)
        }
        .sortMenuChrome(help: String(localized: "Sort and display options"))
    }

    /// Shared with the track list, hence the broadcast.
    private func setRowSize(_ size: TableRowSize) {
        tableRowSize = size
        NotificationCenter.default.post(
            name: .trackTableRowSizeChanged,
            object: nil,
            userInfo: ["rowSize": size]
        )
    }
}
