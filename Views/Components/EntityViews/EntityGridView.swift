import SwiftUI

struct EntityGridView<T: Entity>: View {
    let entities: [T]
    let onSelectEntity: (T) -> Void
    let contextMenuItems: (T) -> [ContextMenuItem]

    @State private var hoveredEntityID: UUID?
    @State private var hoverWorkItem: DispatchWorkItem?

    private let columns = [
        GridItem(.adaptive(minimum: 160, maximum: 200), spacing: 16)
    ]

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 16) {
                ForEach(entities) { entity in
                    EntityGridItem(
                        entity: entity,
                        isHovered: hoveredEntityID == entity.id,
                        onSelect: {
                            onSelectEntity(entity)
                        },
                        onHover: { isHovered in
                            handleHover(for: entity, isHovered: isHovered)
                        }
                    )
                    .contextMenu {
                        ForEach(contextMenuItems(entity), id: \.id) { item in
                            contextMenuItem(item)
                        }
                    }
                    .id(entity.id)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
        }
    }
    
    private func handleHover(for entity: T, isHovered: Bool) {
        hoverWorkItem?.cancel()
        
        if isHovered {
            hoveredEntityID = entity.id
        } else {
            let entityID = entity.id
            hoverWorkItem = DispatchWorkItem {
                if hoveredEntityID == entityID {
                    hoveredEntityID = nil
                }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05, execute: hoverWorkItem!)
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
private struct EntityGridItem<T: Entity>: View {
    let entity: T
    let isHovered: Bool
    let onSelect: () -> Void
    let onHover: (Bool) -> Void

    @State private var artworkImage: NSImage?
    @State private var artworkLoadTask: Task<Void, Never>?

    var body: some View {
        VStack(spacing: 8) {
            artworkSection
            textSection
        }
        .padding(8)
        .background(backgroundView)
        .contentShape(Rectangle())
        .onTapGesture(perform: onSelect)
        .onHover(perform: onHover)
    }
    
    @ViewBuilder
    private var artworkSection: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.gray.opacity(0.2))
                .aspectRatio(1, contentMode: .fit)

            if let image = artworkImage {
                Image(nsImage: image)
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
        .task(id: entity.id) {
            await loadArtworkAsync()
        }
        .onDisappear {
            artworkLoadTask?.cancel()
            artworkLoadTask = nil
            artworkImage = nil
        }
    }
    
    private var textSection: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(entity.name)
                .font(.system(size: 13, weight: .semibold))
                .lineLimit(1)
                .foregroundColor(.primary)
                .help(entity.name)

            if let subtitle = entity.subtitle {
                Text(subtitle)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
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

    private var backgroundView: some View {
        RoundedRectangle(cornerRadius: 10)
            .fill(isHovered ? Color(NSColor.selectedContentBackgroundColor).opacity(0.15) : Color.clear)
            .animation(.easeInOut(duration: 0.15), value: isHovered)
    }

    private func loadArtworkAsync() async {
        loadEntityArtworkAsync(
            from: entity.artworkLarge,
            into: $artworkImage,
            with: $artworkLoadTask
        )
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
