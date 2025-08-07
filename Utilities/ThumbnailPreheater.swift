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

    // Track list thumbnail properties
    private let trackThumbnailSize = 40 * 4 // 40pt thumbnail rendered at 2× (plus wiggle room for higher density)

    // Separate task for track thumbnail preheating so album/artist and track preheats don't cancel each other out
    private var trackPreheatTask: Task<Void, Never>?

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

    /// Begins asynchronously generating thumbnails for the provided tracks and stores them in `ImageCache`.
    /// Cancels any previous track preheat work to prioritize the newest list being shown.
    /// - Parameter tracks: The tracks whose artwork should be pre-cached.
    func preheat(tracks: [Track]) {
        // Cancel any in-flight track work so we don’t waste resources if the list changes.
        trackPreheatTask?.cancel()

        trackPreheatTask = Task.detached(priority: .utility) { [trackThumbnailSize] in
            for track in tracks {
                // Respect cancellation
                guard !Task.isCancelled else { return }

                guard let artworkData = track.artworkData, !artworkData.isEmpty else {
                    continue
                }

                // Track list thumbnail (40×40 points, rendered at 2× scale)
                let listKey = "\(track.id.uuidString)-track-list"
                if ImageCache.shared.image(forKey: listKey) == nil {
                    if let image = ThumbnailGenerator.makeThumbnailLimited(from: artworkData,
                                                                          maxPixelSize: trackThumbnailSize) {
                        ImageCache.shared.insertImage(image, forKey: listKey)
                    }
                }
            }
        }
    }
} 