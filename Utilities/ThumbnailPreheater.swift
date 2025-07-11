import Foundation
import AppKit

/// Preheats (generates + caches) artwork thumbnails for a collection of library entities.
/// This runs off the main thread so that UI interactions remain smooth.
final class ThumbnailPreheater {
    static let shared = ThumbnailPreheater()

    // MARK: - Internal state
    private var preheatTask: Task<Void, Never>?
    private let listThumbnailSize = 96 * 2  // Same maxPixelSize used in EntityListView
    private let gridItemWidth: CGFloat = 180 // Matches `itemWidth` in EntityGridView

    private init() {}

    /// Begins asynchronously generating thumbnails for the provided entities (albums/artists…) and
    /// stores them in the shared `ImageCache` so that views can reuse them instantly.
    /// If a previous pre-heat is still running it will be cancelled.
    /// - Parameter entities: The entities whose artwork should be pre-cached.
    func preheat<T: Entity>(entities: [T]) {
        // Cancel any in-flight work so we don’t waste resources if the library refreshed.
        preheatTask?.cancel()

        preheatTask = Task.detached(priority: .utility) { [listThumbnailSize, gridItemWidth] in
            for entity in entities {
                // Respect cancellation – user may refresh library, quit the app, etc.
                guard !Task.isCancelled else { return }

                guard let artworkData = entity.artworkData, !artworkData.isEmpty else {
                    continue
                }

                // List thumbnail (48×48 points, rendered at 2× scale)
                let listKey = "\(entity.id.uuidString)-list"
                if ImageCache.shared.image(forKey: listKey) == nil {
                    if let image = ThumbnailGenerator.makeThumbnailLimited(from: artworkData,
                                                                          maxPixelSize: listThumbnailSize) {
                        ImageCache.shared.insertImage(image, forKey: listKey)
                    }
                }

                // Grid thumbnail (180×180 points, rendered at 2× scale)
                let gridKey = "\(entity.id.uuidString)-grid-\(Int(gridItemWidth))"
                if ImageCache.shared.image(forKey: gridKey) == nil {
                    if let image = ThumbnailGenerator.makeThumbnailLimited(from: artworkData,
                                                                          maxPixelSize: Int(gridItemWidth * 2)) {
                        ImageCache.shared.insertImage(image, forKey: gridKey)
                    }
                }
            }
        }
    }
} 