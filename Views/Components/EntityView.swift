import SwiftUI

// MARK: - Entity View
struct EntityView<T: Entity>: View {
    let entities: [T]
    let viewType: LibraryViewType
    let onSelectEntity: (T) -> Void
    let contextMenuItems: (T) -> [ContextMenuItem]

    var body: some View {
        switch viewType {
        case .list:
            EntityListView(
                entities: entities,
                onSelectEntity: onSelectEntity,
                contextMenuItems: contextMenuItems
            )
        case .grid:
            EntityGridView(
                entities: entities,
                onSelectEntity: onSelectEntity,
                contextMenuItems: contextMenuItems
            )
        case .table:
            // Table view doesn't make sense for artists/albums
            // Fall back to list view
            EntityListView(
                entities: entities,
                onSelectEntity: onSelectEntity,
                contextMenuItems: contextMenuItems
            )
        }
    }
}

// MARK: - NSImage Extension
extension NSImage {
    func resized(to size: NSSize) -> NSImage? {
        guard let bitmapRep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int(size.width),
            pixelsHigh: Int(size.height),
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else { return nil }

        bitmapRep.size = size
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmapRep)
        draw(in: NSRect(origin: .zero, size: size), from: .zero, operation: .copy, fraction: 1.0)
        NSGraphicsContext.restoreGraphicsState()

        let resizedImage = NSImage(size: size)
        resizedImage.addRepresentation(bitmapRep)
        return resizedImage
    }
}

// MARK: - Async Entity Artwork Loading

extension View {
    func loadEntityArtworkAsync(
        from data: Data?,
        into binding: Binding<NSImage?>,
        delay: UInt64 = TimeConstants.fiftyMilliseconds
    ) async {
        guard binding.wrappedValue == nil, let data = data else { return }
        
        if delay > 0 {
            try? await Task.sleep(nanoseconds: delay)
            guard !Task.isCancelled else { return }
        }
        
        let image = await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let image = NSImage(data: data)
                continuation.resume(returning: image)
            }
        }
        
        guard !Task.isCancelled else { return }
        
        if let image = image {
            await MainActor.run {
                binding.wrappedValue = image
            }
        }
    }
}

// MARK: - Preview

#Preview("Artist List") {
    let artists = [
        ArtistEntity(name: "Artist 0", trackCount: 4),
        ArtistEntity(name: "Artist 1", trackCount: 7),
        ArtistEntity(name: "Artist 2", trackCount: 3)
    ]

    EntityView(
        entities: artists,
        viewType: .list,
        onSelectEntity: { artist in
            Logger.debugPrint("Selected: \(artist.name)")
        },
        contextMenuItems: { _ in [] }
    )
    .frame(height: 400)
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
