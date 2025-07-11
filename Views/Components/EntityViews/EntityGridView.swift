import SwiftUI

struct EntityGridView<T: Entity>: View {
    let entities: [T]
    let onSelectEntity: (T) -> Void
    let contextMenuItems: (T) -> [ContextMenuItem]

    @State private var gridWidth: CGFloat = 0

    private let itemWidth: CGFloat = 180
    private let itemHeight: CGFloat = 240
    private let spacing: CGFloat = 16

    private var columns: Int {
        max(1, Int((gridWidth + spacing) / (itemWidth + spacing)))
    }

    private var gridColumns: [GridItem] {
        Array(repeating: GridItem(.fixed(itemWidth), spacing: spacing), count: columns)
    }

    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                LazyVGrid(columns: gridColumns, spacing: spacing) {
                    ForEach(Array(entities.enumerated()), id: \.element.id) { _, entity in
                        EntityGridItem(
                            entity: entity,
                            itemWidth: itemWidth
                        ) {
                            onSelectEntity(entity)
                        }
                        .equatable()
                        .frame(width: itemWidth, height: itemHeight)
                        .contextMenu {
                            ForEach(contextMenuItems(entity), id: \.id) { item in
                                contextMenuItem(item)
                            }
                        }
                        .id(entity.id)
                    }
                }
                .padding(.horizontal)
                .padding(.bottom)
            }
            .background(Color.clear)
            .onAppear {
                gridWidth = geometry.size.width - 32  // 16 padding on each side
            }
            .onChange(of: geometry.size.width) { _, newWidth in
                gridWidth = newWidth - 32  // 16 padding on each side
            }
        }
    }

    @ViewBuilder
    private func contextMenuItem(_ item: ContextMenuItem) -> some View {
        switch item {
        case .button(let title, let role, let action):
            Button(title, role: role, action: action)
        case .menu(let title, let items):
            Menu(title) {
                ForEach(items, id: \.id) { subItem in
                    if case .button(let subTitle, let subRole, let subAction) = subItem {
                        Button(subTitle, role: subRole, action: subAction)
                    }
                }
            }
        case .divider:
            Divider()
        }
    }
}

// MARK: - Entity Grid Item
private struct EntityGridItem<T: Entity>: View, Equatable {
    let entity: T
    let itemWidth: CGFloat
    let onSelect: () -> Void

    @State private var isHovered = false
    // Cache a SwiftUI `Image` so we don’t recreate it every render pass
    @State private var artworkImage: Image?
    @State private var artworkLoadTask: Task<Void, Never>?

    var body: some View {
        VStack(spacing: 8) {
            // Artwork
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.gray.opacity(0.2))
                    .aspectRatio(1, contentMode: .fit)

                if let image = artworkImage {
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 160, height: 160)
                        .clipped()
                        .cornerRadius(8)
                } else {
                    VStack(spacing: 8) {
                        Image(systemName: Icons.entityIcon(for: entity))
                            .font(.system(size: 48))
                            .foregroundColor(.gray)

                        Text(entity.name)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.gray)
                            .lineLimit(2)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 8)
                    }
                }
            }
            .frame(width: 160, height: 160)

            // Text content
            VStack(alignment: .leading, spacing: 2) {
                Text(entity.name)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(2)
                    .foregroundColor(.primary)

                if let subtitle = entity.subtitle {
                    Text(subtitle)
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                        .help(subtitle)
                }

                if entity is AlbumEntity {
                    Text("\(entity.trackCount) \(entity.trackCount == 1 ? "song" : "songs")")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }
            .frame(width: 160, alignment: .leading)
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(isHovered ? Color(NSColor.selectedContentBackgroundColor).opacity(0.15) : Color.clear)
        )
        .contentShape(Rectangle())
        .onTapGesture(perform: onSelect)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovered = hovering
            }
        }
        .onAppear {
            loadArtworkAsync()
        }
        .onDisappear {
            // Cancel loading task and clear image to free memory
            artworkLoadTask?.cancel()
            artworkLoadTask = nil
            artworkImage = nil
        }
    }

    private func loadArtworkAsync() {
        // Attempt to fetch from cache first
        let cacheKey = "\(entity.id.uuidString)-grid-\(Int(itemWidth))"
        if let cachedNSImage = ImageCache.shared.image(forKey: cacheKey) {
            // Convert once and store the SwiftUI `Image` so we don't recreate it repeatedly
            self.artworkImage = Image(nsImage: cachedNSImage)
            return
        }

        artworkLoadTask?.cancel()

        artworkLoadTask = Task {
            // Yield once to allow SwiftUI to finish layout work before decoding image
            await Task.yield()

            guard !Task.isCancelled else { return }

            if let data = entity.artworkData {
                if let thumbnailImage = ThumbnailGenerator.makeThumbnailLimited(from: data, maxPixelSize: Int(itemWidth * 2)) {
                    ImageCache.shared.insertImage(thumbnailImage, forKey: cacheKey)

                    await MainActor.run {
                        guard !Task.isCancelled else { return }
                        self.artworkImage = Image(nsImage: thumbnailImage)
                    }
                }
            }
        }
    }

    static func == (lhs: EntityGridItem<T>, rhs: EntityGridItem<T>) -> Bool {
        lhs.entity.id == rhs.entity.id
    }
}

// MARK: - Preview

#Preview("Artist Grid") {
    let artists = [
        ArtistEntity(name: "The Beatles", trackCount: 25),
        ArtistEntity(name: "Pink Floyd", trackCount: 18),
        ArtistEntity(name: "Led Zeppelin", trackCount: 22),
        ArtistEntity(name: "Queen", trackCount: 30)
    ]

    EntityGridView(
        entities: artists,
        onSelectEntity: { artist in
            Logger.debugPrint("Selected: \(artist.name)")
        },
        contextMenuItems: { _ in [] }
    )
    .frame(height: 600)
}

#Preview("Album Grid") {
    let albums = [
        AlbumEntity(name: "Abbey Road", trackCount: 17, year: "1969", duration: 2832),
        AlbumEntity(name: "The Dark Side of the Moon", trackCount: 10, year: "1973", duration: 2580),
        AlbumEntity(name: "Led Zeppelin IV", trackCount: 8, year: "1971", duration: 2556),
        AlbumEntity(name: "A Night at the Opera", trackCount: 12, year: "1975", duration: 2628)
    ]

    EntityGridView(
        entities: albums,
        onSelectEntity: { album in
            Logger.debugPrint("Selected: \(album.name)")
        },
        contextMenuItems: { _ in [] }
    )
    .frame(height: 600)
}
