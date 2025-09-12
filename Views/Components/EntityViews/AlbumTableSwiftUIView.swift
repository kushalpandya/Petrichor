import SwiftUI

struct AlbumTableSwiftUIView: View {
    let albums: [AlbumEntity]
    let onSelectAlbum: (AlbumEntity) -> Void
    let contextMenuItems: (AlbumEntity) -> [ContextMenuItem]

    @StateObject private var columnManager = ColumnVisibilityManager.shared

    @State private var tableRowSize: TableRowSize = .cozy
    @State private var selection: AlbumEntity.ID?
    @State private var sortedAlbums: [AlbumEntity] = []
    @State private var sortOrder = [KeyPathComparator(\AlbumEntity.name)]
    @State private var lastSelectionTime: Date = Date()
    @State private var lastSelectedAlbumID: AlbumEntity.ID?

    @State private var columnCustomization = TableColumnCustomization<AlbumEntity>()

    @AppStorage("albumTableColumnCustomizationData")
    private var columnCustomizationData = Data()

    var body: some View {
        tableView
            .contextMenu(forSelectionType: AlbumEntity.ID.self) { selectedIDs in
                if let albumID = selectedIDs.first,
                   let album = albums.first(where: { $0.id == albumID }) {
                    ForEach(contextMenuItems(album), id: \.id) { item in
                        contextMenuItem(item)
                    }
                }
            } primaryAction: { selectedIDs in
                if let albumID = selectedIDs.first,
                   let album = albums.first(where: { $0.id == albumID }) {
                    handleSelection(on: album)
                }
            }
            .onChange(of: columnCustomization) { _, newValue in
                saveColumnCustomization(newValue)
            }
            .onChange(of: sortOrder) { oldValue, newValue in
                if oldValue != newValue {
                    performBackgroundSort(with: newValue)
                }
                saveSortOrderToUserDefaults(newValue)
            }
            .onChange(of: albums) { _, newAlbums in
                if !newAlbums.isEmpty {
                    performBackgroundSort(with: sortOrder)
                }
            }
            .onAppear {
                initializeSortedAlbums()
                restoreColumnCustomization()
            }
    }

    private var tableView: some View {
        Table(sortedAlbums, selection: $selection, sortOrder: $sortOrder, columnCustomization: $columnCustomization) {
            // Title with Artwork
            TableColumn("Album", value: \.name) { album in
                AlbumTitleCell(
                    tableRowSize: tableRowSize,
                    album: album,
                    isSelected: selection == album.id
                )
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .width(min: 200, ideal: 300)
            .customizationID("album")
            .defaultVisibility(.visible)

            // Artist
            TableColumn("Artist", value: \.sortableArtistName) { album in
                HStack {
                    Text(album.artistName ?? "Unknown Artist")
                        .font(.system(size: 13))
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .width(min: 100, ideal: 200)
            .customizationID("artist")
            .defaultVisibility(.visible)

            // Year
            TableColumn("Year", value: \.sortableYear) { album in
                HStack {
                    Text(album.year ?? "")
                        .font(.system(size: 13))
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .width(min: 40, ideal: 60, max: 100)
            .customizationID("year")
            .defaultVisibility(.visible)

            // Track Count
            TableColumn("Tracks", value: \.trackCount) { album in
                HStack {
                    Text("\(album.trackCount)")
                        .font(.system(size: 13))
                        .lineLimit(1)
                        .monospacedDigit()
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .width(min: 40, ideal: 60, max: 100)
            .customizationID("tracks")
            .defaultVisibility(.visible)

            // Duration
            TableColumn("Duration", value: \.sortableDuration) { album in
                HStack {
                    Text(formatDuration(album.duration ?? 0))
                        .font(.system(size: 13))
                        .lineLimit(1)
                        .monospacedDigit()
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .width(min: 60, ideal: 80, max: 120)
            .customizationID("duration")
            .defaultVisibility(.visible)
        }
        .background(Color(NSColor.controlBackgroundColor))
        .environment(\.defaultMinListRowHeight, tableRowSize.rowHeight)
    }

    // MARK: - Helper Methods

    private func initializeSortedAlbums() {
        if let savedSort = UserDefaults.standard.dictionary(forKey: "albumTableSortOrder"),
           let key = savedSort["key"] as? String,
           let ascending = savedSort["ascending"] as? Bool {

            let sortComparators: [String: KeyPathComparator<AlbumEntity>] = [
                "name": KeyPathComparator(\AlbumEntity.name, order: ascending ? .forward : .reverse),
                "sortableArtistName": KeyPathComparator(\AlbumEntity.sortableArtistName, order: ascending ? .forward : .reverse),
                "sortableYear": KeyPathComparator(\AlbumEntity.sortableYear, order: ascending ? .forward : .reverse),
                "trackCount": KeyPathComparator(\AlbumEntity.trackCount, order: ascending ? .forward : .reverse),
                "sortableDuration": KeyPathComparator(\AlbumEntity.sortableDuration, order: ascending ? .forward : .reverse)
            ]

            if let comparator = sortComparators[key] {
                sortOrder = [comparator]
            }
        }

        if sortedAlbums.isEmpty && !albums.isEmpty {
            sortedAlbums = albums.sorted(using: sortOrder)
        }
    }

    private func handleSelection(on album: AlbumEntity) {
        onSelectAlbum(album)
    }

    private func formatDuration(_ seconds: Double) -> String {
        let totalSeconds = Int(max(0, seconds))
        let minutes = totalSeconds / 60
        let remainingSeconds = totalSeconds % 60
        return String(format: "%d:%02d", minutes, remainingSeconds)
    }

    @ViewBuilder
    private func contextMenuItem(_ item: ContextMenuItem) -> some View {
        switch item {
        case .button(let title, _, let action):
            Button(title, action: action)
        case .menu(let title, let items):
            Menu(title) {
                ForEach(items, id: \.id) { subItem in
                    contextMenuSubItem(subItem)
                }
            }
        case .divider:
            Divider()
        }
    }

    @ViewBuilder
    private func contextMenuSubItem(_ item: ContextMenuItem) -> some View {
        switch item {
        case .button(let title, _, let action):
            Button(title, action: action)
        case .menu(let title, let items):
            Menu(title) {
                ForEach(items, id: \.id) { nestedItem in
                    if case .button(let nestedTitle, _, let nestedAction) = nestedItem {
                        Button(nestedTitle, action: nestedAction)
                    }
                }
            }
        case .divider:
            Divider()
        }
    }

    // MARK: - Sorting Helpers

    private func performBackgroundSort(with newSortOrder: [KeyPathComparator<AlbumEntity>]) {
        Task.detached(priority: .userInitiated) {
            let sorted = albums.sorted(using: newSortOrder)
            await MainActor.run {
                self.sortedAlbums = sorted
            }
        }
    }

    private func saveSortOrderToUserDefaults(_ sortOrder: [KeyPathComparator<AlbumEntity>]) {
        guard let firstSort = sortOrder.first else { return }

        let sortString = String(describing: firstSort)
        let ascending = sortString.contains("forward")

        let sortKeys = [
            "name": "name",
            "sortableArtistName": "sortableArtistName",
            "sortableYear": "sortableYear",
            "trackCount": "trackCount",
            "sortableDuration": "sortableDuration"
        ]

        if let key = sortKeys.first(where: { sortString.contains($0.key) })?.value {
            let storage = ["key": key, "ascending": ascending] as [String: Any]
            UserDefaults.standard.set(storage, forKey: "albumTableSortOrder")
        }
    }

    // MARK: - Column Customization Persistence

    private func saveColumnCustomization(_ newValue: TableColumnCustomization<AlbumEntity>) {
        do {
            let data = try JSONEncoder().encode(newValue)
            columnCustomizationData = data
        } catch {
            Logger.warning("Failed to encode TableColumnCustomization: \(error)")
        }
    }

    private func restoreColumnCustomization() {
        guard !columnCustomizationData.isEmpty else { return }
        do {
            let decoded = try JSONDecoder().decode(
                TableColumnCustomization<AlbumEntity>.self,
                from: columnCustomizationData
            )
            columnCustomization = decoded
        } catch {
            Logger.warning("Failed to decode TableColumnCustomization: \(error)")
        }
    }
}

// MARK: - Album Title Cell with Artwork

private struct AlbumTitleCell: View {
    let tableRowSize: TableRowSize
    let album: AlbumEntity
    let isSelected: Bool

    @State private var artworkImage: NSImage?

    var body: some View {
        HStack(spacing: 8) {
            if tableRowSize == .cozy {
                ZStack {
                    if let artworkImage = artworkImage {
                        Image(nsImage: artworkImage)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: ViewDefaults.listArtworkSize, height: ViewDefaults.listArtworkSize)
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                    } else {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.gray.opacity(0.2))
                            .frame(width: ViewDefaults.listArtworkSize, height: ViewDefaults.listArtworkSize)
                            .overlay(
                                Image(systemName: Icons.musicNote)
                                    .font(.system(size: 18))
                                    .foregroundColor(.secondary)
                            )
                    }
                }
                .frame(width: ViewDefaults.listArtworkSize, height: ViewDefaults.listArtworkSize)
                .task(id: album.id) {
                    await loadArtwork()
                }
                .onDisappear {
                    artworkImage = nil
                }
            }

            // Album title
            Text(album.name)
                .font(.system(size: 13))
                .lineLimit(1)

            Spacer()
        }
    }

    private func loadArtwork() async {
        guard artworkImage == nil, let data = album.artworkMedium else { return }

        let image = await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let image = NSImage(data: data)
                continuation.resume(returning: image)
            }
        }

        guard !Task.isCancelled else { return }

        if let image = image {
            await MainActor.run {
                artworkImage = image
            }
        }
    }
}

// MARK: - AlbumEntity Extension for Sorting

extension AlbumEntity {
    var sortableArtistName: String {
        artistName ?? "Unknown Artist"
    }

    var sortableYear: String {
        year ?? ""
    }

    var sortableDuration: Double {
        duration ?? 0
    }
}

// MARK: - Preview

#Preview("Album Table View") {
    let sampleAlbums = [
        AlbumEntity(name: "Abbey Road", trackCount: 17, year: "1969", duration: 2832, artistName: "The Beatles"),
        AlbumEntity(name: "The Dark Side of the Moon", trackCount: 10, year: "1973", duration: 2580, artistName: "Pink Floyd"),
        AlbumEntity(name: "Led Zeppelin IV", trackCount: 8, year: "1971", duration: 2556, artistName: "Led Zeppelin"),
        AlbumEntity(name: "A Night at the Opera", trackCount: 12, year: "1975", duration: 2628, artistName: "Queen")
    ]

    AlbumTableSwiftUIView(
        albums: sampleAlbums,
        onSelectAlbum: { album in
            // Preview selection handler
        },
        contextMenuItems: { _ in [] }
    )
    .frame(height: 400)
}
