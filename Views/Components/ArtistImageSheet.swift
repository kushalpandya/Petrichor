import SwiftUI

struct ArtistImageSheet: View {
    let artistName: String
    let artistId: Int64?
    @Binding var isPresented: Bool
    var onImageSelected: ((Data?) -> Void)?

    @State private var searchQuery: String
    @State private var imageURL = ""
    @State private var images: [ArtistBioManager.ImageResult] = []
    @State private var selectedIndex: Int?
    @State private var artworkData: Data?
    @State private var artworkURL = ""
    @State private var artworkSource = "manual"
    @State private var isSearching = false
    @State private var isLoadingURL = false
    @State private var isProcessingArtwork = false
    @State private var isSaving = false
    @State private var isDeletingImage = false
    @State private var searchTask: Task<Void, Never>?
    @State private var artworkTask: Task<Void, Never>?
    @State private var artworkGeneration = 0
    @State private var wellInvalidationToken = 0

    init(
        artistName: String,
        artistId: Int64?,
        isPresented: Binding<Bool>,
        onImageSelected: ((Data?) -> Void)? = nil
    ) {
        self.artistName = artistName
        self.artistId = artistId
        _isPresented = isPresented
        self.onImageSelected = onImageSelected
        _searchQuery = State(initialValue: artistName)
    }

    private var canSave: Bool {
        (artworkData != nil || isDeletingImage) && !isProcessingArtwork && !isLoadingURL && !isSaving
    }

    var body: some View {
        VStack(spacing: 0) {
            PlaylistEditorHeader(title: String(localized: "Choose Artist Image")) {
                guard !isSaving else { return }
                isPresented = false
            }

            Divider()

            artworkSection

            Divider()

            searchSection

            Divider()
            footer
        }
        .frame(width: 540, height: 620)
        .task {
            let generation = artworkGeneration
            await loadCurrentImage(generation: generation)
            startImageSearch()
        }
        .onDisappear {
            searchTask?.cancel()
            artworkTask?.cancel()
        }
    }

    private var searchSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            ArtworkInputField(
                text: $searchQuery,
                placeholder: "Search artist images",
                leadingIcon: Icons.magnifyingGlass,
                actionIcon: "arrow.right.circle.fill",
                actionHelp: "Search",
                isActionEnabled: !searchQuery.trimmingCharacters(in: .whitespaces).isEmpty,
                isLoading: isSearching,
                action: startImageSearch
            )

            imageResults
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder private var imageResults: some View {
        if images.isEmpty, !isSearching {
            Text("No images available")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if !images.isEmpty {
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 104, maximum: 116), spacing: 10)], spacing: 10) {
                    ForEach(Array(images.enumerated()), id: \.offset) { index, result in
                        imageCell(result: result, index: index)
                    }
                }
                .padding(3)
            }
        } else {
            Color.clear
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func imageCell(result: ArtistBioManager.ImageResult, index: Int) -> some View {
        Group {
            if let image = NSImage(data: result.imageData) {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 108, height: 108)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .strokeBorder(selectedIndex == index ? Color.accentColor : .clear, lineWidth: 3)
                    )
            }
        }
        .contentShape(RoundedRectangle(cornerRadius: 8))
        .onTapGesture {
            supersedeAllArtworkOperations()
            selectedIndex = index
            artworkData = result.imageData
            artworkURL = result.imageUrl
            artworkSource = result.source.components(separatedBy: " – ").first ?? result.source
            isDeletingImage = false
        }
    }

    private var artworkSection: some View {
        VStack(spacing: 10) {
            ArtworkImageWell(
                artworkData: $artworkData,
                isProcessing: $isProcessingArtwork,
                placeholderIcon: Icons.personFill,
                onImported: markManualImport,
                onClear: markImageForDeletion,
                maxDimension: 960,
                onArtworkAction: cancelParentArtworkOperation,
                invalidationToken: wellInvalidationToken
            )

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
            .frame(width: 460)
        }
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity)
    }

    private var footer: some View {
        HStack {
            Button {
                deleteImage()
            } label: {
                Text("Delete Image").foregroundColor(.red)
            }
            .disabled(artistId == nil || isSaving)

            Spacer()

            Button("Cancel") { isPresented = false }
                .keyboardShortcut(.cancelAction)
                .disabled(isSaving)

            Button("Save") { save() }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(!canSave)
        }
        .padding()
    }

    private var parsedImageURL: URL? {
        ArtworkImageLoader.httpURL(from: imageURL)
    }

    private var libraryManager: LibraryManager? {
        AppCoordinator.shared?.libraryManager
    }

    private func searchImages() async {
        let query = searchQuery.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else {
            isSearching = false
            return
        }
        isSearching = true
        selectedIndex = nil
        let results = await ArtistBioManager.shared.searchAllImages(for: query)
        guard !Task.isCancelled else { return }
        images = results
        isSearching = false
    }

    private func startImageSearch() {
        searchTask?.cancel()
        searchTask = Task { await searchImages() }
    }

    private func startURLLoad() {
        guard parsedImageURL != nil, !isLoadingURL else { return }
        supersedeAllArtworkOperations()
        let generation = artworkGeneration
        artworkTask = Task { await loadImageURL(generation: generation) }
    }

    private func loadImageURL(generation: Int) async {
        guard let url = parsedImageURL else { return }
        isLoadingURL = true

        guard let compressed = await ArtworkImageLoader.downloadAndCompress(
            from: url,
            maxDimension: 960,
            source: "ArtistImageSheet/url"
        ) else {
            guard !Task.isCancelled, generation == artworkGeneration else { return }
            isLoadingURL = false
            NotificationManager.shared.addMessage(.error, String(localized: "Couldn't load that image"))
            return
        }
        guard !Task.isCancelled, generation == artworkGeneration else { return }
        isLoadingURL = false
        selectedIndex = nil
        artworkData = compressed
        artworkURL = url.absoluteString
        artworkSource = "url"
        isDeletingImage = false
    }

    private func save() {
        guard let artistId, let libraryManager else { return }
        if isDeletingImage {
            deleteImage()
            return
        }
        guard let imageData = artworkData else { return }
        isSaving = true
        let source = artworkSource
        let url = artworkURL

        Task {
            let compressed = await Task.detached(priority: .userInitiated) {
                ImageUtils.compressImage(from: imageData, source: "ArtistImageSheet/\(source)")
            }.value
            guard let compressed else {
                await MainActor.run { isSaving = false }
                return
            }
            do {
                try await libraryManager.databaseManager.setArtistImage(
                    artistId: artistId,
                    imageData: compressed,
                    imageUrl: url,
                    imageSource: source
                )
            } catch {
                Logger.error("Failed to save artist image for ID \(artistId): \(error)")
                await MainActor.run {
                    isSaving = false
                    NotificationManager.shared.addMessage(.error, String(localized: "Couldn't save the artwork"))
                }
                return
            }
            await MainActor.run {
                onImageSelected?(compressed)
                libraryManager.updateArtistEntityArtwork(name: artistName, artworkData: compressed)
                isPresented = false
            }
        }
    }

    private func markManualImport() {
        selectedIndex = nil
        artworkURL = ""
        artworkSource = "manual"
        isDeletingImage = false
    }

    private func markImageForDeletion() {
        selectedIndex = nil
        artworkURL = ""
        artworkSource = "deleted"
        isDeletingImage = true
    }

    private func loadCurrentImage(generation: Int) async {
        guard let artistId, let libraryManager else { return }
        do {
            let current = try await libraryManager.databaseManager.getArtistImage(artistId: artistId)
            guard !Task.isCancelled, generation == artworkGeneration else { return }
            artworkData = current.data
            artworkURL = current.url ?? ""
            artworkSource = current.source ?? "manual"
        } catch {
            Logger.error("Failed to load artist image for ID \(artistId): \(error)")
        }
    }

    private func deleteImage() {
        guard let artistId, let libraryManager else { return }
        isSaving = true
        Task {
            do {
                try await libraryManager.databaseManager.deleteArtistImageAsync(artistId: artistId)
            } catch {
                Logger.error("Failed to delete artist image for ID \(artistId): \(error)")
                await MainActor.run {
                    isSaving = false
                    NotificationManager.shared.addMessage(.error, String(localized: "Couldn't save the artwork"))
                }
                return
            }
            await MainActor.run {
                onImageSelected?(nil)
                libraryManager.updateArtistEntityArtwork(name: artistName, artworkData: nil)
                isPresented = false
            }
        }
    }

    private func cancelParentArtworkOperation() {
        artworkTask?.cancel()
        artworkTask = nil
        artworkGeneration += 1
        isLoadingURL = false
    }

    private func supersedeAllArtworkOperations() {
        cancelParentArtworkOperation()
        wellInvalidationToken += 1
    }
}
