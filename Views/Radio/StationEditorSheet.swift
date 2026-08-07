import SwiftUI
import UniformTypeIdentifiers

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
            StationArtworkWell(
                artworkData: $artworkData,
                isProcessing: $isProcessingArtwork,
                stationName: stationName
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
}

/// Square artwork target: drop onto it, or click it to focus and press Command-V.
/// Clicking **only focuses**; browsing for a file is its own button underneath.
/// The paste handler has to live on this box: `onPasteCommand` only fires on a view that
/// can become first responder, which a plain sheet root can't.
struct StationArtworkWell: View {
    @Binding var artworkData: Data?
    @Binding var isProcessing: Bool
    let stationName: String

    @FocusState private var isFocused: Bool
    @State private var isDropTargeted = false
    /// Only the newest selection may win: two quick picks would otherwise race, and the
    /// slower first one would land last.
    @State private var compressionTask: Task<Void, Never>?
    /// Advanced by every artwork action, so a provider load already in flight when Generate
    /// or Clear wins can tell that its result is no longer wanted.
    @State private var artworkGeneration = 0

    private let side: CGFloat = 170
    private let actionButtonWidth: CGFloat = 80

    var body: some View {
        VStack(spacing: 10) {
            box
            actions
        }
    }

    private var box: some View {
        ZStack {
            if let artworkData, let image = NSImage(data: artworkData) {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: side, height: side)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(alignment: .topTrailing) { clearButton }
            } else {
                emptyWell
            }
        }
        .frame(width: side, height: side)
        .overlay(focusRing)
        .contentShape(RoundedRectangle(cornerRadius: 8))
        .onTapGesture { isFocused = true }
        .focusable()
        .focused($isFocused)
        .onPasteCommand(of: [.image, .fileURL]) { _ in pasteFromClipboard() }
        .onDrop(of: [.image, .fileURL], isTargeted: $isDropTargeted) { providers in
            load(from: providers)
        }
        .help("Drop an image here, or click to select this box and press Command-V")
    }

    /// Outside the box: a button inside a focusable, tappable container is ambiguous.
    private var actions: some View {
        // Width on each label, not the button: a bordered button sizes chrome to its label.
        HStack(spacing: 8) {
            Button {
                pickImageFile()
            } label: {
                Text("Browse").frame(width: actionButtonWidth)
            }
            .help("Choose an image file")

            Button {
                generateArtwork()
            } label: {
                Text("Generate").frame(width: actionButtonWidth)
            }
            .help("Create artwork from the station name")
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
    }

    private var emptyWell: some View {
        VStack(spacing: 8) {
            Image(systemName: Icons.antennaRadiowaves)
                .font(.system(size: 28))
                .foregroundColor(.secondary)

            Text("Drop or paste image")
                .font(.system(size: 12))
                .foregroundColor(.secondary)
        }
        .frame(width: side, height: side)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(
                    Color.secondary.opacity(0.5),
                    style: StrokeStyle(lineWidth: 1.5, dash: [6, 4])
                )
        )
    }

    private var clearButton: some View {
        Button {
            supersedeCompression()
            artworkData = nil
        } label: {
            Image(systemName: Icons.xmarkCircleFill)
                .font(.system(size: 16))
                .foregroundStyle(.white, Color.black.opacity(0.5))
        }
        .buttonStyle(.plain)
        .padding(6)
        .help("Remove artwork")
    }

    /// The only signal that Command-V lands here rather than in a text field.
    private var focusRing: some View {
        RoundedRectangle(cornerRadius: 8)
            .strokeBorder(Color.accentColor, lineWidth: 2)
            .opacity(isFocused || isDropTargeted ? 1 : 0)
    }

    private func generateArtwork() {
        supersedeCompression()
        let seedName = stationName.trimmingCharacters(in: .whitespaces)
        artworkData = ImageUtils.generateStationArtwork(name: seedName.isEmpty ? "Radio" : seedName)
    }

    /// Every artwork mutation goes through here first, so a slow import can't land on top
    /// of a later Generate or Clear.
    private func supersedeCompression() {
        compressionTask?.cancel()
        compressionTask = nil
        artworkGeneration += 1
        isProcessing = false
    }

    private func pickImageFile() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.image]
        panel.prompt = String(localized: "Choose")

        guard panel.runModal() == .OK, let url = panel.url, let data = try? Data(contentsOf: url) else { return }
        apply(data)
    }

    /// Reads the pasteboard directly: an image copied from another app arrives as
    /// several flavors and `readObjects` picks a usable one.
    private func pasteFromClipboard() {
        let pasteboard = NSPasteboard.general
        if let images = pasteboard.readObjects(forClasses: [NSImage.self]) as? [NSImage],
           let tiff = images.first?.tiffRepresentation {
            apply(tiff)
            return
        }
        if let urls = pasteboard.readObjects(forClasses: [NSURL.self]) as? [URL],
           let url = urls.first,
           let data = try? Data(contentsOf: url) {
            apply(data)
        }
    }

    private func load(from providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first else { return false }

        // Claimed now: the provider can take long enough for the user to press Generate or
        // Clear before it finishes, and its result must lose to that. Processing is marked
        // here rather than when compression starts, so Save can't run during a slow load
        // and persist the previous image.
        supersedeCompression()
        let generation = artworkGeneration
        isProcessing = true

        if provider.canLoadObject(ofClass: NSImage.self) {
            _ = provider.loadObject(ofClass: NSImage.self) { object, _ in
                guard let image = object as? NSImage, let tiff = image.tiffRepresentation else {
                    DispatchQueue.main.async { abandonProviderLoad(generation: generation) }
                    return
                }
                DispatchQueue.main.async { apply(tiff, generation: generation) }
            }
            return true
        }

        provider.loadDataRepresentation(forTypeIdentifier: UTType.fileURL.identifier) { data, _ in
            guard let data,
                  let path = String(data: data, encoding: .utf8),
                  let url = URL(string: path),
                  let imageData = try? Data(contentsOf: url) else {
                DispatchQueue.main.async { abandonProviderLoad(generation: generation) }
                return
            }
            DispatchQueue.main.async { apply(imageData, generation: generation) }
        }
        return true
    }

    /// Releases the processing flag for a load that produced nothing, unless a later action
    /// already owns it.
    private func abandonProviderLoad(generation: Int) {
        guard generation == artworkGeneration else { return }
        isProcessing = false
    }

    /// Off the main thread: a pasted screenshot is easily tens of megabytes.
    private func apply(_ data: Data, generation: Int? = nil) {
        // A provider load that lost to a later action never starts compressing.
        if let generation, generation != artworkGeneration { return }

        supersedeCompression()
        let current = artworkGeneration
        isProcessing = true

        compressionTask = Task {
            let compressed = await Task.detached(priority: .userInitiated) {
                ImageUtils.compressStationArtwork(from: data)
            }.value

            guard !Task.isCancelled, current == artworkGeneration else { return }
            isProcessing = false

            guard let compressed else {
                NotificationManager.shared.addMessage(.error, String(localized: "Couldn't read that image"))
                return
            }
            artworkData = compressed
        }
    }
}
