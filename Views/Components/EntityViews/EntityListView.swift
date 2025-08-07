import SwiftUI

struct EntityListView<T: Entity>: View {
    let entities: [T]
    let onSelectEntity: (T) -> Void
    let contextMenuItems: (T) -> [ContextMenuItem]

    @State private var hoveredEntityID: UUID?

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 0, pinnedViews: []) {
                ForEach(entities) { entity in
                    EntityListRow(
                        entity: entity,
                        isHovered: hoveredEntityID == entity.id,
                        onSelect: {
                            onSelectEntity(entity)
                        },
                        onHover: { isHovered in
                            hoveredEntityID = isHovered ? entity.id : nil
                        }
                    )
                    .equatable()
                    .contextMenu {
                        ForEach(contextMenuItems(entity), id: \.id) { item in
                            contextMenuItem(item)
                        }
                    }
                    .id(entity.id)
                }
            }
            .padding(5)
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

// MARK: - Entity List Row
private struct EntityListRow<T: Entity>: View, Equatable {
    let entity: T
    let isHovered: Bool
    let onSelect: () -> Void
    let onHover: (Bool) -> Void

    // Store a SwiftUI `Image` to avoid re-creating it on every view update
    @State private var artworkImage: Image?
    @State private var artworkLoadTask: Task<Void, Never>?

    var body: some View {
        HStack(spacing: 12) {
            // Artwork
            ZStack {
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.gray.opacity(0.2))
                    .frame(width: 48, height: 48)

                if let image = artworkImage {
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 48, height: 48)
                        .clipped()
                        .cornerRadius(6)
                } else {
                    Image(systemName: Icons.entityIcon(for: entity))
                        .font(.system(size: 20))
                        .foregroundColor(.gray)
                }
            }

            // Content
            VStack(alignment: .leading, spacing: 2) {
                Text(entity.name)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)
                    .truncationMode(.tail)
                
                if let subtitle = entity.subtitle {
                    Text(subtitle)
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                
                if entity is AlbumEntity {
                    Text("\(entity.trackCount) \(entity.trackCount == 1 ? "song" : "songs")")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Spacer()

            // Chevron on hover
            if isHovered {
                Image(systemName: Icons.chevronRight)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.secondary)
                    .transition(.opacity.combined(with: .scale))
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(backgroundView)
        .contentShape(Rectangle())
        .onTapGesture(perform: onSelect)
        .onHover(perform: onHover)
        .animation(.easeInOut(duration: 0.15), value: isHovered)
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

    private var backgroundView: some View {
        RoundedRectangle(cornerRadius: 6)
            .fill(isHovered ? Color(NSColor.selectedContentBackgroundColor).opacity(0.15) : Color.clear)
            .animation(.easeInOut(duration: 0.15), value: isHovered)
    }

    private func loadArtworkAsync() {
        // Try cache first
        let cacheKey = "\(entity.id.uuidString)-list"
        if let cachedNSImage = ImageCache.shared.image(forKey: cacheKey) {
            self.artworkImage = Image(nsImage: cachedNSImage)
            return
        }

        artworkLoadTask?.cancel()

        artworkLoadTask = Task {
            // Yield once to allow SwiftUI to finish layout work before decoding
            await Task.yield()

            guard !Task.isCancelled else { return }

            if let data = entity.artworkData {
                if let thumbnailImage = ThumbnailGenerator.makeThumbnailLimited(from: data, maxPixelSize: 96 * 2) {
                    ImageCache.shared.insertImage(thumbnailImage, forKey: cacheKey)

                    await MainActor.run {
                        guard !Task.isCancelled else { return }
                        self.artworkImage = Image(nsImage: thumbnailImage)
                    }
                }
            }
        }
    }

    static func == (lhs: EntityListRow<T>, rhs: EntityListRow<T>) -> Bool {
        lhs.entity.id == rhs.entity.id && lhs.isHovered == rhs.isHovered
    }
}

// MARK: - Preview

#Preview("Artist List") {
    let artists = [
        ArtistEntity(name: "Radiohead", trackCount: 15),
        ArtistEntity(name: "Arcade Fire", trackCount: 12),
        ArtistEntity(name: "The National", trackCount: 20)
    ]

    EntityListView(
        entities: artists,
        onSelectEntity: { artist in
            Logger.debugPrint("Selected: \(artist.name)")
        },
        contextMenuItems: { _ in [] }
    )
    .frame(height: 400)
}

#Preview("Album List") {
    let albums = [
        AlbumEntity(name: "OK Computer", trackCount: 12, year: "1997", duration: 3200),
        AlbumEntity(name: "The Suburbs", trackCount: 16, year: "2010", duration: 3840),
        AlbumEntity(name: "Sleep Well Beast", trackCount: 12, year: "2017", duration: 2880),
        AlbumEntity(name: "In Rainbows", trackCount: 10, year: "2007", duration: 2400)
    ]

    EntityListView(
        entities: albums,
        onSelectEntity: { album in
            Logger.debugPrint("Selected: \(album.name)")
        },
        contextMenuItems: { _ in [] }
    )
    .frame(height: 400)
}
