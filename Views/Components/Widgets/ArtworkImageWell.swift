import SwiftUI
import UniformTypeIdentifiers

struct ArtworkImageWell: View {
    @Binding var artworkData: Data?
    @Binding var isProcessing: Bool
    var placeholderIcon: String
    var secondaryActionTitle: String?
    var secondaryActionHelp: String?
    var onSecondaryAction: (() -> Void)?
    var onImported: (() -> Void)?
    var showsClearButton = true
    var onClear: (() -> Void)?
    var maxDimension: CGFloat = 480
    var onArtworkAction: (() -> Void)?
    var invalidationToken = 0

    @FocusState private var isFocused: Bool
    @State private var isDropTargeted = false
    @State private var compressionTask: Task<Void, Never>?
    @State private var artworkGeneration = 0

    private let side: CGFloat = 170
    private let actionButtonWidth: CGFloat = 80

    var body: some View {
        VStack(spacing: 10) {
            box
            actions
        }
        .onDisappear { supersedeCompression() }
        .onChange(of: invalidationToken) { supersedeCompression() }
    }

    private var box: some View {
        ZStack {
            if let artworkData, let image = NSImage(data: artworkData) {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: side, height: side)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(alignment: .topTrailing) {
                        if showsClearButton {
                            clearButton
                        }
                    }
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

    private var actions: some View {
        HStack(spacing: 8) {
            Button {
                onArtworkAction?()
                pickImageFile()
            } label: {
                Text("Browse").frame(width: actionButtonWidth)
            }
            .help("Choose an image file")

            if let secondaryActionTitle, let onSecondaryAction {
                Button {
                    onArtworkAction?()
                    supersedeCompression()
                    onSecondaryAction()
                } label: {
                    Text(secondaryActionTitle).frame(width: actionButtonWidth)
                }
                .help(secondaryActionHelp ?? secondaryActionTitle)
            }
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
    }

    private var emptyWell: some View {
        VStack(spacing: 8) {
            SymbolImage(placeholderIcon)
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
            onArtworkAction?()
            supersedeCompression()
            artworkData = nil
            onClear?()
        } label: {
            Image(systemName: Icons.xmarkCircleFill)
                .font(.system(size: 16))
                .foregroundStyle(.white, Color.black.opacity(0.5))
        }
        .buttonStyle(.plain)
        .padding(6)
        .help("Remove artwork")
    }

    private var focusRing: some View {
        RoundedRectangle(cornerRadius: 8)
            .strokeBorder(Color.accentColor, lineWidth: 2)
            .opacity(isFocused || isDropTargeted ? 1 : 0)
    }

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

        guard panel.runModal() == .OK, let url = panel.url else { return }
        loadFile(url)
    }

    private func pasteFromClipboard() {
        let pasteboard = NSPasteboard.general
        if let images = pasteboard.readObjects(forClasses: [NSImage.self]) as? [NSImage],
           let tiff = images.first?.tiffRepresentation {
            onArtworkAction?()
            apply(tiff)
            return
        }
        if let urls = pasteboard.readObjects(forClasses: [NSURL.self]) as? [URL],
           let url = urls.first {
            onArtworkAction?()
            loadFile(url)
        }
    }

    private func load(from providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first else { return false }

        onArtworkAction?()
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
                  let url = URL(string: path) else {
                DispatchQueue.main.async { abandonProviderLoad(generation: generation) }
                return
            }
            Task {
                guard let imageData = await ArtworkImageLoader.readFile(from: url) else {
                    await MainActor.run { abandonProviderLoad(generation: generation) }
                    return
                }
                await MainActor.run { apply(imageData, generation: generation) }
            }
        }
        return true
    }

    private func loadFile(_ url: URL) {
        supersedeCompression()
        let generation = artworkGeneration
        isProcessing = true
        compressionTask = Task {
            guard let data = await ArtworkImageLoader.readFile(from: url),
                  !Task.isCancelled,
                  generation == artworkGeneration else {
                abandonProviderLoad(generation: generation)
                return
            }
            apply(data, generation: generation)
        }
    }

    private func abandonProviderLoad(generation: Int) {
        guard generation == artworkGeneration else { return }
        isProcessing = false
    }

    private func apply(_ data: Data, generation: Int? = nil) {
        if let generation, generation != artworkGeneration { return }

        supersedeCompression()
        let current = artworkGeneration
        isProcessing = true

        compressionTask = Task {
            let dimension = maxDimension
            let compressed = await Task.detached(priority: .userInitiated) {
                ImageUtils.compressImage(from: data, maxDimension: dimension)
            }.value

            guard !Task.isCancelled, current == artworkGeneration else { return }
            isProcessing = false

            guard let compressed else {
                NotificationManager.shared.addMessage(.error, String(localized: "Couldn't read that image"))
                return
            }
            artworkData = compressed
            onImported?()
        }
    }
}

enum ArtworkImageLoader {
    static let maxBytes: Int64 = 50 * 1024 * 1024

    static func httpURL(from input: String) -> URL? {
        guard let url = URL(string: input.trimmingCharacters(in: .whitespacesAndNewlines)),
              url.scheme == "http" || url.scheme == "https" else { return nil }
        return url
    }

    static func readFile(from url: URL, maxBytes: Int64 = maxBytes) async -> Data? {
        await Task.detached(priority: .userInitiated) {
            guard let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize,
                  Int64(size) <= maxBytes else { return nil }
            return try? Data(contentsOf: url, options: .mappedIfSafe)
        }.value
    }

    static func download(from url: URL, maxBytes: Int64 = 50 * 1024 * 1024) async -> Data? {
        do {
            var request = URLRequest(url: url)
            request.setValue(AppInfo.userAgent, forHTTPHeaderField: "User-Agent")

            let (bytes, response) = try await AppInfo.urlSession.bytes(for: request)
            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200,
                  response.expectedContentLength <= maxBytes else { return nil }

            var data = Data()
            if response.expectedContentLength > 0 {
                data.reserveCapacity(Int(response.expectedContentLength))
            }
            for try await byte in bytes {
                data.append(byte)
                guard data.count <= maxBytes else { return nil }
            }

            guard !data.isEmpty, NSImage(data: data) != nil else { return nil }
            return data
        } catch {
            Logger.error("Failed to download artwork from \(url): \(error)")
            return nil
        }
    }

    static func downloadAndCompress(
        from url: URL,
        maxDimension: CGFloat,
        source: String
    ) async -> Data? {
        guard let data = await download(from: url), !Task.isCancelled else { return nil }
        return await Task.detached(priority: .userInitiated) {
            ImageUtils.compressImage(from: data, maxDimension: maxDimension, source: source)
        }.value
    }
}
