import Foundation
import AppKit
import ImageIO

/// A helper that uses CGImageSource to create downsampled thumbnails efficiently.
/// This avoids loading the full-size image into memory before resizing.
struct ThumbnailGenerator {
    /// Generate an `NSImage` thumbnail from raw image data.
    /// - Parameters:
    ///   - data: Encoded image data (PNG, JPEG, etc.).
    ///   - maxPixelSize: The maximum width/height in pixels for the thumbnail.
    /// - Returns: Downsampled `NSImage` or `nil`.
    static func makeThumbnail(from data: Data, maxPixelSize: Int) -> NSImage? {
        // Create image source without caching the full image into memory.
        guard let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary) else {
            return nil
        }

        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true
        ]

        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return nil
        }

        // Match the pixel dimensions – size given in points, so divide by scale.
        let scale = NSScreen.main?.backingScaleFactor ?? 2
        let size = NSSize(width: CGFloat(cgImage.width) / scale, height: CGFloat(cgImage.height) / scale)

        return NSImage(cgImage: cgImage, size: size)
    }

    // MARK: - Internal concurrency limiter
    // Creating thumbnails can be CPU-intensive; we gate the number of simultaneous
    // decodes so scrolling won't spawn hundreds of threads.
    private static let semaphore: DispatchSemaphore = {
        // Allow more parallel decodes but keep an upper bound to avoid CPU starvation.
        let coreCount = ProcessInfo.processInfo.activeProcessorCount
        let limit = min(max(coreCount * 2, 8), 16) // 2× cores, at least 8, capped at 16
        return DispatchSemaphore(value: limit)
    }()

    /// Same as `makeThumbnail`, but limits the number of concurrent thumbnail generations.
    static func makeThumbnailLimited(from data: Data, maxPixelSize: Int) -> NSImage? {
        semaphore.wait()
        defer { semaphore.signal() }
        return makeThumbnail(from: data, maxPixelSize: maxPixelSize)
    }
} 