import SwiftUI

struct StationEditorSheet: View {
    let station: RadioStation?
    let onClose: () -> Void

    @State private var name: String
    @State private var streamURL: String
    @State private var description: String
    @State private var artworkData: Data?
    @State private var isProcessingArtwork = false
    @State private var isSaving = false

    init(station: RadioStation?, onClose: @escaping () -> Void) {
        self.station = station
        self.onClose = onClose
        _name = State(initialValue: station?.name ?? "")
        _streamURL = State(initialValue: station?.streamURL ?? "")
        _description = State(initialValue: station?.description ?? "")
        _artworkData = State(initialValue: station?.artworkData)
    }

    private var isEditing: Bool { station != nil }

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty
            && InternetRadioManager.validate(streamURL: streamURL) != nil
            // Saving mid-compression would persist the previous image, and the result would
            // then land on a dismissed view.
            && !isProcessingArtwork
            && !isSaving
    }

    var body: some View {
        VStack(spacing: 0) {
            PlaylistEditorHeader(title: isEditing ? String(localized: "Edit Station") : String(localized: "Add Station")) {
                // Closing mid-save would let the pending completion dismiss whichever editor
                // is open by then, not this one.
                guard !isSaving else { return }
                onClose()
            }

            Divider()

            PlaylistNameField(name: $name, placeholder: String(localized: "Station Name"))

            Divider()

            ScrollView {
                StationFormFields(
                    streamURL: $streamURL,
                    description: $description,
                    artworkData: $artworkData,
                    isProcessingArtwork: $isProcessingArtwork,
                    stationName: name
                )
                .padding(.vertical, 20)
            }

            Divider()

            PlaylistEditorFooter(
                summary: nil,
                saveTitle: isEditing ? String(localized: "Save") : String(localized: "Add"),
                canSave: canSave,
                onCancel: { if !isSaving { onClose() } },
                onSave: save
            )
        }
        .frame(width: 480, height: 620)
    }

    private func save() {
        var updated = station ?? RadioStation(name: "", streamURL: "")
        updated.name = name.trimmingCharacters(in: .whitespaces)
        updated.streamURL = streamURL.trimmingCharacters(in: .whitespacesAndNewlines)
        updated.description = description.isEmpty ? nil : description
        updated.artworkData = artworkData

        // Set before the task, not inside it: two clicks land on the main actor back to
        // back, and an async flag would let both through to insert the station twice.
        isSaving = true

        Task {
            let saved: Bool
            if isEditing {
                // Double optional: `nil` means "leave the column alone", so an edit that
                // didn't touch the image can't undo a favicon that arrived meanwhile.
                let artworkChange: Data?? = artworkData == station?.artworkData ? nil : .some(artworkData)
                saved = await InternetRadioManager.shared.update(updated, artwork: artworkChange)
            } else {
                saved = await InternetRadioManager.shared.save(updated) != nil
            }

            // A failure already raised a banner; keeping the sheet open is what stops the
            // user's input disappearing with it.
            guard saved else {
                await MainActor.run { isSaving = false }
                return
            }
            await MainActor.run { onClose() }
        }
    }
}

struct StationFormFields: View {
    @Binding var streamURL: String
    @Binding var description: String
    @Binding var artworkData: Data?
    @Binding var isProcessingArtwork: Bool
    /// Seeds generated artwork, so the same station name always produces the same image.
    let stationName: String

    private var urlIsInvalid: Bool {
        !streamURL.trimmingCharacters(in: .whitespaces).isEmpty
            && InternetRadioManager.validate(streamURL: streamURL) == nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            ArtworkImageWell(
                artworkData: $artworkData,
                isProcessing: $isProcessingArtwork,
                placeholderIcon: Icons.antennaRadiowaves,
                secondaryActionTitle: String(localized: "Generate"),
                secondaryActionHelp: String(localized: "Create artwork from the station name"),
                onSecondaryAction: generateArtwork,
                onImported: nil
            )
            .frame(maxWidth: .infinity, alignment: .center)

            VStack(alignment: .leading, spacing: 6) {
                Text("Stream URL")
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                TextField("https://example.com/stream", text: $streamURL)
                    .textFieldStyle(.roundedBorder)

                if urlIsInvalid {
                    Text("Enter a valid http:// or https:// stream address")
                        .font(.caption)
                        .foregroundColor(.red)
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Description")
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                TextField("Optional", text: $description, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(4...8)
                    .frame(minHeight: 72, alignment: .top)
            }
        }
        .padding(.horizontal, 20)
    }

    private func generateArtwork() {
        let seedName = stationName.trimmingCharacters(in: .whitespaces)
        artworkData = ImageUtils.generateStationArtwork(name: seedName.isEmpty ? "Radio" : seedName)
    }
}
