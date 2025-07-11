import Foundation
import AppKit

/// A shared in-memory image cache for storing already-resized artwork images.
/// The cache uses `NSCache` so the system can automatically purge it under memory pressure.
final class ImageCache {
    static let shared = ImageCache()

    private let cache: NSCache<NSString, NSImage>

    private init() {
        let cache = NSCache<NSString, NSImage>()
        // Limit the number of thumbnails and total memory cost (in bytes) to avoid unbounded growth.
        cache.countLimit = 10_000
        cache.totalCostLimit = 600 * 1_024 * 1_024 // ~600 MB
        self.cache = cache
    }

    func image(forKey key: String) -> NSImage? {
        cache.object(forKey: key as NSString)
    }

    func insertImage(_ image: NSImage, forKey key: String) {
        cache.setObject(image, forKey: key as NSString, cost: image.representationSize)
    }
}

private extension NSImage {
    /// Rough estimate of the memory footprint of the bitmap representation of the image.
    var representationSize: Int {
        guard let tiffRepresentation = tiffRepresentation else { return 0 }
        return tiffRepresentation.count
    }
} 