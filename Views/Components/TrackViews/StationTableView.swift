import SwiftUI

/// The station counterpart to `TrackTableView`.
///
/// **Brings its own scrolling.** Host it directly, never inside a `ScrollView`.
struct StationTableView: View {
    let stations: [RadioStation]
    let contextMenuItems: ([RadioStation]) -> [ContextMenuItem]
    /// The Delete key, handed the selection: the library deletes, a collection only unlinks.
    let onDeleteCommand: ([RadioStation]) -> Void

    @EnvironmentObject var playbackManager: PlaybackManager

    @AppStorage("trackTableRowSize")
    private var rowSize: TableRowSize = .expanded

    // Shared with `StationOptionsDropdown` and the sibling surface: Home and a collection
    // sort their stations alike.
    @AppStorage("stationSortField")
    private var sortFieldRaw: String = StationSortField.name.rawValue

    @AppStorage("stationSortAscending")
    private var sortAscending: Bool = true

    @AppStorage("stationTableColumnCustomizationData")
    private var columnCustomizationData = Data()

    @State private var selection: Set<RadioStation.ID> = []
    @State private var sortedStations: [RadioStation] = []
    @State private var sortOrder: [KeyPathComparator<RadioStation>] = []
    @State private var hasInitializedCustomization = false
    @State private var columnCustomization: TableColumnCustomization<RadioStation> = {
        if let data = UserDefaults.standard.data(forKey: "stationTableColumnCustomizationData"),
           !data.isEmpty,
           let decoded = try? JSONDecoder().decode(TableColumnCustomization<RadioStation>.self, from: data) {
            return decoded
        }
        return TableColumnCustomization<RadioStation>()
    }()

    var body: some View {
        table
            .scrollContentBackground(.hidden)
            .environment(\.defaultMinListRowHeight, rowSize.rowHeight)
            .contextMenu(forSelectionType: RadioStation.ID.self) { ids in
                let selected = sortedStations.filter { ids.contains($0.id) }
                if !selected.isEmpty {
                    ForEach(contextMenuItems(selected), id: \.id) { item in
                        ContextMenuItemView(item: item)
                    }
                }
            } primaryAction: { ids in
                if let id = ids.first, let station = sortedStations.first(where: { $0.id == id }) {
                    handleDoubleTap(on: station)
                }
            }
            .onDeleteCommand {
                let selected = sortedStations.filter { selection.contains($0.id) }
                guard !selected.isEmpty else { return }
                onDeleteCommand(selected)
            }
            .onAppear {
                syncSortOrderFromStorage()
                hasInitializedCustomization = true
            }
            .onChange(of: stations) { _, newStations in
                resort(newStations, using: sortOrder)
            }
            .onChange(of: sortOrder) { _, newOrder in
                guard let first = newOrder.first, let field = StationSortField.from(first) else { return }
                sortFieldRaw = field.rawValue
                sortAscending = first.order == .forward
                resort(stations, using: newOrder)
            }
            .onChange(of: sortFieldRaw) { syncSortOrderFromStorage() }
            .onChange(of: sortAscending) { syncSortOrderFromStorage() }
            .onChange(of: columnCustomization) { _, newValue in
                guard hasInitializedCustomization else { return }
                saveColumnCustomization(newValue)
            }
            .onReceive(NotificationCenter.default.publisher(for: .trackTableRowSizeChanged)) { notification in
                if let newRowSize = notification.userInfo?["rowSize"] as? TableRowSize {
                    rowSize = newRowSize
                }
            }
    }

    private var table: some View {
        Table(sortedStations, selection: $selection, sortOrder: $sortOrder, columnCustomization: $columnCustomization) {
            // `localizedStandard` so "Radio 9" precedes "Radio 10"; must stay identical to
            // `StationSortField.comparator`.
            TableColumn("Name", value: \.name, comparator: String.StandardComparator.localizedStandard) { station in
                StationTitleCell(
                    station: station,
                    rowSize: rowSize,
                    isCurrentStation: isCurrentStation(station),
                    isPlaying: isCurrentStation(station) && playbackManager.isPlaying,
                    isSelected: selection.contains(station.id)
                ) {
                    handleDoubleTap(on: station)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .width(min: 220)
            .customizationID("name")
            .defaultVisibility(.visible)

            TableColumn("Date Added", value: \.sortableDateAdded) { station in
                Text(station.dateAdded.map(Self.dateFormatter.string(from:)) ?? "")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .width(min: 100)
            .customizationID("dateAdded")
            .defaultVisibility(.visible)

            TableColumn("Last Played", value: \.sortableLastPlayed) { station in
                Text(station.lastPlayed.map(Self.dateFormatter.string(from:)) ?? "")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .width(min: 100)
            .customizationID("lastPlayed")
            .defaultVisibility(.visible)

            TableColumn("Plays", value: \.playCount) { station in
                Text("\(station.playCount)")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                    .monospacedDigit()
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .width(min: 50)
            .customizationID("playCount")
            .defaultVisibility(.visible)
        }
    }

    // MARK: - Playback

    private func isCurrentStation(_ station: RadioStation) -> Bool {
        playbackManager.currentStation?.id == station.id
    }

    private func handleDoubleTap(on station: RadioStation) {
        if isCurrentStation(station) {
            playbackManager.togglePlayPause()
        } else {
            playbackManager.playStation(station)
        }
    }

    // MARK: - Sorting

    /// Lets the dropdown's stored field drive the header's `sortOrder`. The equality bail
    /// is what stops the two `onChange` handlers bouncing off each other.
    private func syncSortOrderFromStorage() {
        let field = StationSortField(rawValue: sortFieldRaw) ?? .name
        let desired = [field.comparator(ascending: sortAscending)]
        guard desired != sortOrder else { return }
        sortOrder = desired
        resort(stations, using: desired)
    }

    private func resort(_ stations: [RadioStation], using order: [KeyPathComparator<RadioStation>]) {
        guard !order.isEmpty else {
            sortedStations = stations
            return
        }
        sortedStations = stations.sorted(using: order)
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter
    }()

    private func saveColumnCustomization(_ newValue: TableColumnCustomization<RadioStation>) {
        do {
            columnCustomizationData = try JSONEncoder().encode(newValue)
        } catch {
            Logger.warning("Failed to encode station TableColumnCustomization: \(error)")
        }
    }
}

// MARK: - Name Cell

private struct StationTitleCell: View {
    let station: RadioStation
    let rowSize: TableRowSize
    let isCurrentStation: Bool
    let isPlaying: Bool
    let isSelected: Bool
    let onPlay: () -> Void

    private var isExpanded: Bool { rowSize == .expanded }

    var body: some View {
        HStack(spacing: 10) {
            if isExpanded {
                artwork
            } else {
                compactPlayControl
            }

            if isExpanded {
                VStack(alignment: .leading, spacing: 2) {
                    titleText
                    subtitleText
                }
            } else {
                HStack(spacing: 6) {
                    titleText
                    subtitleText
                }
            }

            Spacer(minLength: 0)
        }
    }

    private var titleText: some View {
        Text(station.name)
            .font(.system(size: 13, weight: isCurrentStation ? .bold : .regular))
            .lineLimit(1)
            .animation(.none, value: isSelected)
    }

    private var subtitleText: some View {
        Text(subtitle)
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
            .lineLimit(1)
    }

    /// Missing parts are dropped so there's no dangling separator.
    private var subtitle: String {
        var parts = [station.description, station.country]
            .compactMap { $0?.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        if let bitrate = station.bitrate, bitrate > 0 {
            parts.append("\(bitrate) kbps")
        }
        return parts.joined(separator: " · ")
    }

    private var artwork: some View {
        ZStack {
            StationArtworkThumb(station: station, side: ViewDefaults.listArtworkSize)

            if isCurrentStation || isSelected {
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.black.opacity(0.5))
                    .frame(width: ViewDefaults.listArtworkSize, height: ViewDefaults.listArtworkSize)

                Button(action: onPlay) {
                    Image(systemName: playButtonIcon)
                        .font(.system(size: 20))
                        .foregroundColor(.white)
                        .frame(width: 22, height: 22)
                }
                .buttonStyle(.plain)
            }
        }
        .frame(width: ViewDefaults.listArtworkSize, height: ViewDefaults.listArtworkSize)
        .animation(.none, value: isSelected)
    }

    private var compactPlayControl: some View {
        ZStack {
            // Reserves the glyph's width so names stay aligned when no control shows.
            Image(systemName: Icons.playFill)
                .font(.system(size: 14))
                .foregroundColor(.clear)
                .frame(width: 20, height: 20)

            if isSelected || isCurrentStation {
                Button(action: onPlay) {
                    Image(systemName: playButtonIcon)
                        .font(.system(size: 14))
                        .foregroundColor(.primary)
                }
                .buttonStyle(.plain)
            }
        }
        .animation(.none, value: isSelected)
    }

    private var playButtonIcon: String {
        isCurrentStation && isPlaying ? Icons.stopFill : Icons.playFill
    }
}

// MARK: - Artwork

struct StationArtworkThumb: View {
    let station: RadioStation
    let side: CGFloat

    var body: some View {
        Group {
            if let image = station.artworkImage {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.gray.opacity(0.2))
                    .overlay(
                        Image(systemName: Icons.radioFill)
                            .font(.system(size: side * 0.45))
                            .foregroundColor(.secondary)
                    )
            }
        }
        .frame(width: side, height: side)
        .clipShape(RoundedRectangle(cornerRadius: 4))
    }
}
