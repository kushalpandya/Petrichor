import SwiftUI

struct EntityGridView<T: Entity>: View {
    let entities: [T]
    let onSelectEntity: (T) -> Void
    let contextMenuItems: (T) -> [ContextMenuItem]

    @State private var hoveredEntityID: UUID?
    @State private var isScrolling = false
    
    private let columns = [
        GridItem(.adaptive(minimum: ViewDefaults.gridArtworkSize, maximum: ViewDefaults.gridArtworkSize + 40), spacing: 16)
    ]

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 16) {
                ForEach(entities) { entity in
                    EntityGridItem(
                        entity: entity,
                        isHovered: isScrolling ? false : (hoveredEntityID == entity.id),
                        isScrolling: isScrolling,
                        onSelect: {
                            onSelectEntity(entity)
                        },
                        onHover: { isHovered in
                            if !isScrolling {
                                hoveredEntityID = isHovered ? entity.id : nil
                            }
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
        .coordinateSpace(name: "scroll")
        .modifier(ScrollDetectionModifier(isScrolling: $isScrolling, hoveredEntityID: $hoveredEntityID))
    }

    @ViewBuilder
    private func contextMenuItem(_ item: ContextMenuItem) -> some View {
        ContextMenuItemView(item: item)
    }
}

// MARK: - Cross-OS Scroll Detection

private struct ScrollDetectionModifier: ViewModifier {
    @Binding var isScrolling: Bool
    @Binding var hoveredEntityID: UUID?
    
    func body(content: Content) -> some View {
        if #available(macOS 15.0, *) {
            content
                .onScrollPhaseChange { _, newPhase in
                    withAnimation(.none) {
                        let wasScrolling = isScrolling
                        isScrolling = newPhase == .interacting || newPhase == .decelerating
                        
                        if isScrolling && !wasScrolling {
                            hoveredEntityID = nil
                        }
                    }
                }
        } else {
            content
                .background(
                    ScrollDetectionView { isDetectedScrolling in
                        if isDetectedScrolling != isScrolling {
                            withAnimation(.none) {
                                isScrolling = isDetectedScrolling
                                if isScrolling {
                                    hoveredEntityID = nil
                                }
                            }
                        }
                    }
                )
        }
    }
}

// MARK: - Scroll Detection for macOS 14

private struct ScrollDetectionView: View {
    let onScrollingChanged: (Bool) -> Void
    @State private var lastOffset: CGFloat = 0
    @State private var scrollTimer: Timer?
    
    var body: some View {
        GeometryReader { geometry in
            Color.clear
                .preference(
                    key: ScrollOffsetKey.self,
                    value: geometry.frame(in: .named("scroll")).origin.y
                )
        }
        .onPreferenceChange(ScrollOffsetKey.self) { newOffset in
            if abs(newOffset - lastOffset) > 1 {
                onScrollingChanged(true)
                lastOffset = newOffset
                
                scrollTimer?.invalidate()
                scrollTimer = Timer.scheduledTimer(withTimeInterval: 0.15, repeats: false) { _ in
                    onScrollingChanged(false)
                }
            }
        }
    }
}

private struct ScrollOffsetKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

// MARK: - Image Cache

private class RenderedImageCache {
    static let shared = RenderedImageCache()
    private let cache = NSCache<NSString, NSImage>()
    
    init() {
        cache.countLimit = 1000
    }
    
    func getImage(for entity: any Entity) -> NSImage? {
        let artworkHash = entity.artworkData?.hashValue ?? 0
        let key = "\(entity.id.uuidString)-\(artworkHash)-rendered" as NSString

        if let cached = cache.object(forKey: key) {
            return cached
        }

        // Use original artworkData (not artworkLarge) to preserve aspect ratio
        guard let artworkData = entity.artworkData else { return nil }

        let renderedImage = createRenderedImage(from: artworkData)
        
        if let image = renderedImage {
            cache.setObject(image, forKey: key)
        }
        
        return renderedImage
    }
    
    private func createRenderedImage(from data: Data) -> NSImage? {
        guard let imageSource = CGImageSourceCreateWithData(data as CFData, nil),
              let cgImage = CGImageSourceCreateImageAtIndex(imageSource, 0, [
                kCGImageSourceShouldCacheImmediately: true
              ] as CFDictionary) else {
            return nil
        }

        let targetSize = Int(ViewDefaults.gridArtworkSize)
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
            width: targetSize,
            height: targetSize,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        ) else { return nil }

        let drawRect = CGRect(x: 0, y: 0, width: targetSize, height: targetSize)
        let cornerRadius: CGFloat = 8
        let path = CGPath(roundedRect: drawRect, cornerWidth: cornerRadius, cornerHeight: cornerRadius, transform: nil)
        context.addPath(path)
        context.clip()
        context.interpolationQuality = .high
        context.draw(croppedCG, in: drawRect)

        guard let finalCG = context.makeImage() else { return nil }
        return NSImage(cgImage: finalCG, size: NSSize(width: targetSize, height: targetSize))
    }
}

// MARK: - Grid Item for Album and Artist views

private struct EntityGridItem<T: Entity>: View {
    let entity: T
    let isHovered: Bool
    let isScrolling: Bool
    let onSelect: () -> Void
    let onHover: (Bool) -> Void

    @State private var renderedImage: NSImage?

    var body: some View {
        VStack(spacing: 8) {
            Group {
                if let image = renderedImage {
                    Image(nsImage: image)
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
            .onAppear {
                loadArtwork()
            }
            .onChange(of: entity.artworkData) {
                loadArtwork()
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
                .animation(
                    isScrolling ? .none : .easeInOut(duration: 0.08),
                    value: isHovered
                )
        )
        .contentShape(Rectangle())
        .onTapGesture(perform: onSelect)
        .onHover(perform: onHover)
    }
    
    private func loadArtwork() {
        DispatchQueue.global(qos: .userInitiated).async {
            let image = RenderedImageCache.shared.getImage(for: entity)

            DispatchQueue.main.async {
                self.renderedImage = image
            }
        }
    }
}
