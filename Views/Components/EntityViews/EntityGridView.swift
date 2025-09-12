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
        let key = "\(entity.id.uuidString)-rendered" as NSString
        
        if let cached = cache.object(forKey: key) {
            return cached
        }
        
        guard let artworkData = entity.artworkLarge else { return nil }
        
        let renderedImage = createRenderedImage(from: artworkData)
        
        if let image = renderedImage {
            cache.setObject(image, forKey: key)
        }
        
        return renderedImage
    }
    
    private func createRenderedImage(from data: Data) -> NSImage? {
        guard let originalImage = NSImage(data: data) else { return nil }
        
        let size = NSSize(width: ViewDefaults.gridArtworkSize, height: ViewDefaults.gridArtworkSize)
        let renderedImage = NSImage(size: size)
        
        renderedImage.lockFocus()
        
        let rect = NSRect(origin: .zero, size: size)
        let path = NSBezierPath(roundedRect: rect, xRadius: 8, yRadius: 8)
        path.addClip()
        
        originalImage.draw(in: rect, from: .zero, operation: .copy, fraction: 1.0)
        
        renderedImage.unlockFocus()
        
        return renderedImage
    }
}

// MARK: - Simplified Grid Item
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
                            Image(systemName: Icons.entityIcon(for: entity))
                                .font(.system(size: 48))
                                .foregroundColor(.gray)
                        )
                        .cornerRadius(8)
                        .shadow(color: .black.opacity(0.2), radius: 10, x: 0, y: 5)
                }
            }
            .onAppear {
                loadArtwork()
            }
            
            VStack(alignment: .leading, spacing: 2) {
                Text(entity.name)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                    .foregroundColor(.primary)

                if let subtitle = entity.subtitle {
                    Text(subtitle)
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
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
