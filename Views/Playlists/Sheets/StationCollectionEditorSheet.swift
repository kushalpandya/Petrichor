import SwiftUI

/// A picker over existing stations, mirroring the regular playlist editor's "Add Songs"
/// tab. Creating stations lives in Home > Internet Radio and File > New.
struct StationCollectionEditorSheet: View {
    @Binding var isPresented: Bool
    private let editingCollection: Playlist?

    @EnvironmentObject var playlistManager: PlaylistManager
    @ObservedObject private var radioManager = InternetRadioManager.shared

    @State private var name: String

    /// Staged membership: the exact set that will be saved, in order.
    @State private var stagedStationIDs: [Int64] = []
    @State private var didLoad = false
    @State private var searchText = ""
    @State private var isSaving = false

    init(isPresented: Binding<Bool>, editingCollection: Playlist?) {
        self._isPresented = isPresented
        self.editingCollection = editingCollection
        _name = State(initialValue: editingCollection?.name ?? "")
    }

    private var isEditing: Bool { editingCollection != nil }

    var body: some View {
        VStack(spacing: 0) {
            PlaylistEditorHeader(
                title: isEditing
                    ? String(localized: "Edit Station Collection")
                    : String(localized: "New Station Collection")
            ) {
                guard !isSaving else { return }
                isPresented = false
            }

            Divider()

            PlaylistNameField(name: $name, placeholder: String(localized: "Collection Name"))

            Divider()

            stationPicker

            Divider()

            PlaylistEditorFooter(
                summary: summary,
                saveTitle: isEditing ? String(localized: "Save") : String(localized: "Create"),
                canSave: !name.trimmingCharacters(in: .whitespaces).isEmpty && !isSaving,
                onCancel: { if !isSaving { isPresented = false } },
                onSave: save
            )
        }
        .frame(width: 640, height: 700)
        .onAppear(perform: loadExistingStations)
    }

    private var summary: String? {
        stagedStationIDs.isEmpty ? nil : String(localized: "\(stagedStationIDs.count) stations")
    }

    private var filteredStations: [RadioStation] {
        let query = searchText.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return radioManager.stations }
        return radioManager.stations.filter {
            $0.name.localizedCaseInsensitiveContains(query)
                || ($0.description?.localizedCaseInsensitiveContains(query) ?? false)
        }
    }

    private var stationPicker: some View {
        VStack(spacing: 8) {
            searchBox

            if radioManager.stations.isEmpty {
                emptyLibraryView
            } else if filteredStations.isEmpty {
                noMatchesView
            } else {
                List(filteredStations) { station in
                    StationEditorRow(
                        station: station,
                        isStaged: station.id.map { stagedStationIDs.contains($0) } ?? false
                    ) {
                        toggle(station)
                    }
                    .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
                }
                .listStyle(.plain)
            }
        }
        .padding(.top, 8)
        .frame(maxHeight: .infinity)
    }

    private var searchBox: some View {
        EditorSearchField(text: $searchText, placeholder: "Search stations...")
            .padding(.horizontal, 16)
    }

    private var emptyLibraryView: some View {
        placeholder(icon: Icons.radioFill, title: "No stations yet") {
            Text("Add stations from Home > Internet Radio, then group them here.")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }

    private var noMatchesView: some View {
        placeholder(icon: Icons.magnifyingGlass, title: "No stations match your search") { EmptyView() }
    }

    private func placeholder(
        icon: String,
        title: LocalizedStringKey,
        @ViewBuilder detail: () -> some View
    ) -> some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 32))
                .foregroundColor(.secondary.opacity(0.5))
            Text(title)
                .font(.subheadline)
                .foregroundColor(.secondary)
            detail()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func loadExistingStations() {
        guard !didLoad else { return }
        didLoad = true

        guard let editingCollection else { return }
        stagedStationIDs = playlistManager.stations(in: editingCollection).compactMap(\.id)
    }

    private func toggle(_ station: RadioStation) {
        guard let stationId = station.id else { return }
        if let index = stagedStationIDs.firstIndex(of: stationId) {
            stagedStationIDs.remove(at: index)
        } else {
            stagedStationIDs.append(stationId)
        }
    }

    private func save() {
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        let ids = stagedStationIDs

        // Set before the task: two activations land on the main actor back to back, and an
        // async flag would let both through and persist the collection twice.
        isSaving = true

        Task {
            let saved: Bool
            if let editingCollection {
                saved = await playlistManager.updateStationCollection(
                    editingCollection, name: trimmedName, stationIds: ids
                )
            } else {
                saved = await playlistManager.createStationCollection(name: trimmedName, stationIds: ids) != nil
            }
            await MainActor.run {
                isSaving = false
                if saved { isPresented = false }
            }
        }
    }
}

private struct StationEditorRow: View {
    let station: RadioStation
    let isStaged: Bool
    let onToggle: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            StationArtworkThumb(station: station, side: 32)

            VStack(alignment: .leading, spacing: 2) {
                Text(station.name)
                    .font(.system(size: 13))
                    .lineLimit(1)

                if let description = station.description, !description.isEmpty {
                    Text(description)
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 12)

            Button(action: onToggle) {
                Image(systemName: isStaged ? Icons.minusCircleFill : Icons.plusCircleFill)
                    .font(.system(size: 16))
                    .foregroundColor(isStaged ? .red : .accentColor)
            }
            .buttonStyle(.plain)
            .help(isStaged
                ? String(localized: "Remove from collection")
                : String(localized: "Add to collection"))
        }
        .padding(.vertical, 6)
        .contentShape(Rectangle())
    }
}
