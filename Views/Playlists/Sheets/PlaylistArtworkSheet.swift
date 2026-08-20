import SwiftUI

struct PlaylistArtworkSheet: View {
    let playlist: Playlist
    let defaultArtworkData: Data?
    let stationArtworkSources: [Data]
    @Binding var isPresented: Bool
    let onSaved: (Data?) -> Void

    @EnvironmentObject private var playlistManager: PlaylistManager
    @State private var artworkData: Data?
    @State private var defaultPreviewArtwork: Data?
    @State private var shouldPersistArtwork: Bool
    @State private var imageURL = ""
    @State private var isLoadingURL = false
    @State private var isProcessingArtwork = false
    @State private var isSaving = false
    @State private var artworkTask: Task<Void, Never>?
    @State private var artworkGeneration = 0
    @State private var wellInvalidationToken = 0

    init(
        playlist: Playlist,
        defaultArtworkData: Data?,
        stationArtworkSources: [Data] = [],
        isPresented: Binding<Bool>,
        onSaved: @escaping (Data?) -> Void
    ) {
        self.playlist = playlist
        self.defaultArtworkData = defaultArtworkData
        self.stationArtworkSources = stationArtworkSources
        _isPresented = isPresented
        self.onSaved = onSaved
        _artworkData = State(initialValue: playlist.coverArtworkData ?? defaultArtworkData)
        _defaultPreviewArtwork = State(initialValue: defaultArtworkData)
        _shouldPersistArtwork = State(initialValue: playlist.coverArtworkData != nil)
    }

    private var canSave: Bool {
        !isLoadingURL && !isProcessingArtwork && !isSaving
    }

    var body: some View {
        VStack(spacing: 0) {
            PlaylistEditorHeader(title: String(localized: "Choose Playlist Artwork")) {
                guard !isSaving else { return }
                isPresented = false
            }

            Divider()

            VStack(spacing: 22) {
                ArtworkImageWell(
                    artworkData: $artworkData,
                    isProcessing: $isProcessingArtwork,
                    placeholderIcon: Icons.defaultPlaylistIcon(for: playlist),
                    secondaryActionTitle: String(localized: "Reshuffle"),
                    secondaryActionHelp: String(localized: "Create a new collage from playlist items"),
                    onSecondaryAction: reshuffle,
                    onImported: markCustomImport,
                    showsClearButton: shouldPersistArtwork,
                    onArtworkAction: cancelParentArtworkOperation,
                    invalidationToken: wellInvalidationToken
                )
                .onChange(of: artworkData) {
                    if artworkData == nil {
                        artworkData = defaultPreviewArtwork
                        shouldPersistArtwork = false
                    }
                }

                ArtworkInputField(
                    text: $imageURL,
                    placeholder: "Load image from URL",
                    leadingIcon: "link",
                    actionIcon: Icons.arrowDownCircleFill,
                    actionHelp: "Load Image",
                    isActionEnabled: parsedImageURL != nil,
                    isLoading: isLoadingURL,
                    action: startURLLoad
                )
            }
            .padding(24)
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider()

            PlaylistEditorFooter(
                summary: nil,
                saveTitle: String(localized: "Save"),
                canSave: canSave,
                leadingActionTitle: String(localized: "Reset"),
                leadingActionEnabled: playlist.coverArtworkData != nil || shouldPersistArtwork,
                onLeadingAction: resetArtwork,
                onCancel: { if !isSaving { isPresented = false } },
                onSave: save
            )
        }
        .frame(width: 480, height: 520)
        .task { await loadDefaultArtworkIfNeeded() }
        .onDisappear { artworkTask?.cancel() }
    }

    private var parsedImageURL: URL? {
        ArtworkImageLoader.httpURL(from: imageURL)
    }

    private func reshuffle() {
        supersedeAllArtworkOperations()
        let sources: [Data?]
        if playlist.type == .stations {
            sources = Array(stationArtworkSources.shuffled().prefix(4)).map(Optional.some)
        } else {
            sources = playlist.collageArtworkSources(shuffled: true)
        }
        let generation = artworkGeneration
        isProcessingArtwork = true
        artworkTask = Task {
            let collage = await Task.detached(priority: .userInitiated) {
                Playlist.renderCollageArtwork(fromArtwork: sources)
            }.value
            guard !Task.isCancelled, generation == artworkGeneration else { return }
            isProcessingArtwork = false
            guard let collage else { return }
            artworkData = collage
            shouldPersistArtwork = true
        }
    }

    private func markCustomImport() {
        shouldPersistArtwork = true
    }

    private func resetArtwork() {
        supersedeAllArtworkOperations()
        artworkData = defaultPreviewArtwork
        shouldPersistArtwork = false
    }

    private func loadImageURL() async {
        guard let url = parsedImageURL else { return }
        let generation = artworkGeneration
        isLoadingURL = true

        guard let compressed = await ArtworkImageLoader.downloadAndCompress(
            from: url,
            maxDimension: 480,
            source: "PlaylistArtworkSheet/url"
        ) else {
            guard !Task.isCancelled, generation == artworkGeneration else { return }
            isLoadingURL = false
            NotificationManager.shared.addMessage(.error, String(localized: "Couldn't load that image"))
            return
        }
        guard !Task.isCancelled, generation == artworkGeneration else { return }
        isLoadingURL = false
        artworkData = compressed
        shouldPersistArtwork = true
    }

    private func startURLLoad() {
        guard parsedImageURL != nil, !isLoadingURL else { return }
        supersedeAllArtworkOperations()
        artworkTask = Task { await loadImageURL() }
    }

    private func save() {
        isSaving = true
        let persistedArtwork = shouldPersistArtwork ? artworkData : nil
        Task {
            let saved = await playlistManager.updatePlaylistArtwork(playlist, artworkData: persistedArtwork)
            guard saved else {
                await MainActor.run { isSaving = false }
                return
            }
            await MainActor.run {
                onSaved(persistedArtwork ?? defaultPreviewArtwork)
                isPresented = false
            }
        }
    }

    private func cancelParentArtworkOperation() {
        artworkTask?.cancel()
        artworkTask = nil
        artworkGeneration += 1
        isLoadingURL = false
        isProcessingArtwork = false
    }

    private func supersedeAllArtworkOperations() {
        cancelParentArtworkOperation()
        wellInvalidationToken += 1
    }

    private func loadDefaultArtworkIfNeeded() async {
        guard defaultPreviewArtwork == nil else { return }

        let sources: [Data?]
        if playlist.type == .stations {
            sources = Array(stationArtworkSources.prefix(4)).map(Optional.some)
        } else {
            sources = playlist.collageArtworkSources()
        }
        let collage = await Task.detached(priority: .utility) {
            Playlist.renderCollageArtwork(fromArtwork: sources)
        }.value
        guard !Task.isCancelled else { return }
        defaultPreviewArtwork = collage
        if !shouldPersistArtwork {
            artworkData = collage
        }
    }
}
