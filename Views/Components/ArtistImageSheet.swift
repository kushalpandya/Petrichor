import SwiftUI

struct ArtistImageSheet: View {
    let artistName: String
    let artistId: Int64?
    @Binding var isPresented: Bool
    var onImageSelected: ((Data?) -> Void)?

    @State private var searchQuery: String = ""
    @State private var images: [ArtistBioManager.ImageResult] = []
    @State private var isLoading = true
    @State private var selectedIndex: Int?

    var body: some View {
        VStack(spacing: 0) {
            sheetHeader
            Divider()
            imageGrid
            Divider()
            sheetFooter
        }
        .frame(width: 580, height: 520)
        .task {
            searchQuery = artistName
            await loadImages()
        }
    }

    // MARK: - Header

    private var sheetHeader: some View {
        VStack(spacing: 10) {
            HStack {
                Button(action: { isPresented = false }) {
                    Image(systemName: Icons.xmarkCircleFill)
                        .font(.system(size: 18))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.escape)
                .focusable(false)
                .help("Dismiss")

                Text("Choose Artist Image")
                    .font(.headline)

                Spacer()
            }

            HStack(spacing: 8) {
                TextField("Search by artist name or paste image URL", text: $searchQuery)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit {
                        Task { await loadImages() }
                    }

                Button("Search") {
                    Task { await loadImages() }
                }
                .disabled(searchQuery.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding()
    }

    // MARK: - Image Grid

    private var imageGrid: some View {
        Group {
            if isLoading {
                VStack {
                    Spacer()
                    ProgressView()
                        .scaleEffect(0.8)
                    Text("Searching for images...")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.top, 8)
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if images.isEmpty {
                VStack {
                    Spacer()
                    Text("No images available")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVGrid(
                        columns: [GridItem(.adaptive(minimum: 140, maximum: 160), spacing: 12)],
                        spacing: 12
                    ) {
                        ForEach(Array(images.enumerated()), id: \.offset) { index, result in
                            imageCell(result: result, index: index)
                        }
                    }
                    .padding()
                }
            }
        }
    }

    private func imageCell(result: ArtistBioManager.ImageResult, index: Int) -> some View {
        let isSelected = selectedIndex == index

        return Group {
            if let nsImage = NSImage(data: result.imageData) {
                Image(nsImage: nsImage)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 140, height: 140)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .strokeBorder(
                                isSelected ? Color.accentColor : Color.clear,
                                lineWidth: 3
                            )
                    )
            }
        }
        .onTapGesture {
            selectedIndex = index
        }
    }

    // MARK: - Footer

    private var libraryManager: LibraryManager? {
        AppCoordinator.shared?.libraryManager
    }

    private func saveArtistImage(_ imageData: Data, url: String, source: String) {
        guard let artistId, let libraryManager else { return }

        libraryManager.databaseManager.updateArtistInfo(
            artistId: artistId,
            imageData: imageData,
            imageUrl: url,
            imageSource: source
        )
        onImageSelected?(imageData)
        libraryManager.updateArtistEntityArtwork(name: artistName, artworkData: imageData)
    }

    private var sheetFooter: some View {
        HStack {
            Button {
                guard let artistId, let libraryManager else { return }
                libraryManager.databaseManager.deleteArtistImage(artistId: artistId)
                onImageSelected?(nil)
                libraryManager.updateArtistEntityArtwork(name: artistName, artworkData: nil)
                isPresented = false
            } label: {
                Text("Delete Image")
                    .foregroundColor(.red)
            }
            .disabled(artistId == nil)

            Spacer()

            Button("Cancel") {
                isPresented = false
            }
            .keyboardShortcut(.cancelAction)

            Button("Save") {
                guard let index = selectedIndex, index < images.count else { return }
                let result = images[index]

                if let compressed = ImageUtils.compressImage(from: result.imageData, source: "ArtistImageSheet/\(result.source)") {
                    let source = result.source.components(separatedBy: " – ").first ?? result.source
                    saveArtistImage(compressed, url: result.imageUrl, source: source)
                }
                isPresented = false
            }
            .buttonStyle(.borderedProminent)
            .disabled(selectedIndex == nil)
            .keyboardShortcut(.defaultAction)
        }
        .padding()
    }

    // MARK: - Data Loading

    private func loadImages() async {
        let query = searchQuery.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return }
        isLoading = true
        selectedIndex = nil

        if let url = URL(string: query), url.scheme == "http" || url.scheme == "https" {
            // Direct URL — download the image
            images = await downloadImage(from: url)
        } else {
            images = await ArtistBioManager.shared.searchAllImages(for: query)
        }

        isLoading = false
    }

    private func downloadImage(from url: URL) async -> [ArtistBioManager.ImageResult] {
        // Cap download size at 50 MB to prevent a potential memory overload
        // if image URL points an unusually large image.
        let maxBytes: Int64 = 50 * 1024 * 1024

        do {
            var request = URLRequest(url: url)
            request.setValue(AppInfo.userAgent, forHTTPHeaderField: "User-Agent")

            let (bytes, response) = try await AppInfo.urlSession.bytes(for: request)
            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else {
                Logger.error("Failed to download image from URL: \(url)")
                return []
            }

            // Reject when size is over the limit
            if response.expectedContentLength > maxBytes {
                Logger.error("Image size is too large: \(response.expectedContentLength) > \(maxBytes)")
                return []
            }

            var data = Data()
            if response.expectedContentLength > 0 {
                data.reserveCapacity(Int(response.expectedContentLength))
            }
            for try await byte in bytes {
                data.append(byte)
                if data.count > maxBytes {
                    Logger.error("Image size is too large: \(response.expectedContentLength) > \(maxBytes)")
                    return []
                }
            }

            guard !data.isEmpty, NSImage(data: data) != nil else {
                Logger.error("Image is empty or invalid: \(response.expectedContentLength)")
                return []
            }
            
            return [ArtistBioManager.ImageResult(imageData: data, imageUrl: url.absoluteString, source: "url")]
        } catch {
            return []
        }
    }
}
