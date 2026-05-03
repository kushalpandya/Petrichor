import SwiftUI

struct EntityGridView<T: Entity>: View {
    let entities: [T]
    let onSelectEntity: (T) -> Void
    let contextMenuItems: (T) -> [ContextMenuItem]

    @State private var hoveredEntityID: UUID?

    private let columns = [
        GridItem(.adaptive(minimum: ViewDefaults.gridArtworkSize, maximum: ViewDefaults.gridArtworkSize + 40), spacing: 16)
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
                            hoveredEntityID = isHovered ? entity.id : nil
                        }
                    )
                    .contextMenu {
                        ForEach(contextMenuItems(entity), id: \.id) { item in
                            contextMenuItem(item)
                        }
                    }
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
        }
    }

    @ViewBuilder
    private func contextMenuItem(_ item: ContextMenuItem) -> some View {
        ContextMenuItemView(item: item)
    }
}

// MARK: - Image Cache

private final class EntityArtworkCache: @unchecked Sendable {
    static let shared = EntityArtworkCache()
    private let cache = NSCache<NSString, NSImage>()
    private let loadQueue: OperationQueue = {
        let queue = OperationQueue()
        queue.maxConcurrentOperationCount = max(2, ProcessInfo.processInfo.activeProcessorCount / 2)
        queue.qualityOfService = .utility
        return queue
    }()

    private static let pixelSize = Int(ViewDefaults.gridArtworkSize * 2)
    private static let bytesPerImage = pixelSize * pixelSize * 4

    init() {
        cache.countLimit = 500
        cache.totalCostLimit = 80 * 1024 * 1024
    }

    private func cacheKey(for entity: any Entity) -> NSString {
        let artworkSize = entity.artworkData?.count ?? 0
        return "\(entity.id.uuidString)-\(artworkSize)-rendered" as NSString
    }

    func getCachedImage(for entity: any Entity) -> NSImage? {
        cache.object(forKey: cacheKey(for: entity))
    }

    func loadImage(for entity: any Entity) async -> NSImage? {
        let key = cacheKey(for: entity)

        if let cached = cache.object(forKey: key) {
            return cached
        }

        guard let artworkData = entity.artworkData else { return nil }

        return await loadQueue.renderArtwork { [self] in
            // Re-check cache, another operation may have loaded it while queued
            if let cached = cache.object(forKey: key) {
                return cached
            }

            let renderedImage = createRenderedImage(from: artworkData)

            if let image = renderedImage {
                cache.setObject(image, forKey: key, cost: Self.bytesPerImage)
            }

            return renderedImage
        }
    }
    
    private func createRenderedImage(from data: Data) -> NSImage? {
        guard let nsImage = NSImage(data: data),
              let cgImage = nsImage.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return nil
        }

        // Rasterize at 2x to provide enough pixels for Retina displays
        let pointSize = ViewDefaults.gridArtworkSize
        let scale: CGFloat = 2
        let pixelSize = Int(pointSize * scale)
        let srcWidth = cgImage.width
        let srcHeight = cgImage.height

        // Aspect-fill: crop to centered square region from source
        let cropRect: CGRect
        if srcWidth > srcHeight {
            let offset = (srcWidth - srcHeight) / 2
            cropRect = CGRect(x: offset, y: 0, width: srcHeight, height: srcHeight)
        } else {
            let offset = (srcHeight - srcWidth) / 2
            cropRect = CGRect(x: 0, y: offset, width: srcWidth, height: srcWidth)
        }

        guard let croppedCG = cgImage.cropping(to: cropRect) else { return nil }

        // Draw into a square context with rounded corners via clipping path
        guard let context = CGContext(
            data: nil,
            width: pixelSize,
            height: pixelSize,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        ) else { return nil }

        let drawRect = CGRect(x: 0, y: 0, width: pixelSize, height: pixelSize)
        let cornerRadius: CGFloat = 8 * scale
        let path = CGPath(roundedRect: drawRect, cornerWidth: cornerRadius, cornerHeight: cornerRadius, transform: nil)
        context.addPath(path)
        context.clip()
        context.interpolationQuality = .high
        context.draw(croppedCG, in: drawRect)

        guard let finalCG = context.makeImage() else { return nil }
        return NSImage(cgImage: finalCG, size: NSSize(width: pointSize, height: pointSize))
    }
}

// MARK: - Grid Item for Album and Artist views

private struct EntityGridItem<T: Entity>: View {
    let entity: T
    let isHovered: Bool
    let onSelect: () -> Void
    let onHover: (Bool) -> Void

    @State private var renderedImage: NSImage?

    var body: some View {
        VStack(spacing: 8) {
            Group {
                if let image = renderedImage {
                    Image(nsImage: image)
                        .resizable()
                        .interpolation(.high)
                        .frame(width: ViewDefaults.gridArtworkSize, height: ViewDefaults.gridArtworkSize)
                        .shadow(color: .black.opacity(0.2), radius: 10, x: 0, y: 5)
                } else {
                    Rectangle()
                        .fill(Color.gray.opacity(0.2))
                        .frame(width: ViewDefaults.gridArtworkSize, height: ViewDefaults.gridArtworkSize)
                        .overlay(
                            Group {
                                if entity is ArtistEntity {
                                    Text(entity.name.artistInitials)
                                        .font(.system(size: 40, weight: .medium, design: .rounded))
                                        .foregroundColor(.gray)
                                } else {
                                    Image(systemName: Icons.entityIcon(for: entity))
                                        .font(.system(size: 48))
                                        .foregroundColor(.gray)
                                }
                            }
                        )
                        .cornerRadius(8)
                        .shadow(color: .black.opacity(0.2), radius: 10, x: 0, y: 5)
                }
            }
            .task(id: artworkTaskID) {
                await loadArtwork()
            }
            
            VStack(alignment: .leading, spacing: 2) {
                Text(entity.name)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                    .foregroundColor(.primary)
                    .help(entity.name)

                if let albumEntity = entity as? AlbumEntity {
                    if let artistName = albumEntity.artistName {
                        Text(artistName)
                            .font(.system(size: 11))
                            .foregroundColor(.primary)
                            .lineLimit(1)
                            .help(artistName)
                    }
                    
                    if let year = albumEntity.year {
                        Text(year)
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                            .help(year)
                    }
                } else if let subtitle = entity.subtitle {
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
            .frame(width: ViewDefaults.gridArtworkSize, alignment: .leading)
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(isHovered ? Color(NSColor.selectedContentBackgroundColor).opacity(0.15) : Color.clear)
                .animation(.easeInOut(duration: 0.08), value: isHovered)
        )
        .contentShape(Rectangle())
        .onTapGesture(perform: onSelect)
        .onHover(perform: onHover)
    }
    
    private var artworkTaskID: String {
        "\(entity.id.uuidString)-\(entity.artworkData?.count ?? 0)"
    }

    private func loadArtwork() async {
        // Serve cache hits synchronously to avoid placeholder flicker on scroll recycle
        if let cached = EntityArtworkCache.shared.getCachedImage(for: entity) {
            renderedImage = cached
            return
        }

        let image = await EntityArtworkCache.shared.loadImage(for: entity)

        guard !Task.isCancelled else { return }
        renderedImage = image
    }
}
