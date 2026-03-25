import AppKit
import UniformTypeIdentifiers

enum ImageResizer {
    /// Compress image data to HEIC format, downscaling to fit within maxDimension while preserving aspect ratio.
    /// Never upscales images smaller than maxDimension.
    /// - Parameters:
    ///   - imageData: Original image data in any supported format (JPEG, PNG, HEIC, etc.)
    ///   - maxDimension: Maximum width or height in pixels (default: 960)
    ///   - quality: HEIC compression quality (0.0 to 1.0, default: 0.8)
    ///   - source: Optional source identifier (e.g. file path) included in failure logs
    /// - Returns: Compressed HEIC data, or nil if compression fails
    static func compressImage(
        from imageData: Data,
        maxDimension: CGFloat = 960,
        quality: CGFloat = 0.8,
        source: String? = nil
    ) -> Data? {
        guard let image = NSImage(data: imageData),
              let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            let context = source.map { " from \($0)" } ?? ""
            Logger.warning("Failed to create image\(context) (\(imageData.count) bytes)")
            return nil
        }

        let srcWidth = CGFloat(cgImage.width)
        let srcHeight = CGFloat(cgImage.height)

        var destWidth = srcWidth
        var destHeight = srcHeight

        if srcWidth > maxDimension || srcHeight > maxDimension {
            let scale = min(maxDimension / srcWidth, maxDimension / srcHeight)
            destWidth = (srcWidth * scale).rounded(.down)
            destHeight = (srcHeight * scale).rounded(.down)
        }

        let targetSize = NSSize(width: destWidth, height: destHeight)

        guard let context = CGContext(
            data: nil,
            width: Int(destWidth),
            height: Int(destHeight),
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        ) else {
            return resizeImage(from: imageData, to: targetSize)
        }
        context.interpolationQuality = .high
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: destWidth, height: destHeight))
        guard let finalCGImage = context.makeImage() else {
            return resizeImage(from: imageData, to: targetSize)
        }

        if let heicData = encodeHEIC(finalCGImage, quality: quality) {
            return heicData
        }

        // Fall back to JPEG if HEIC encoding fails
        let logContext = source.map { " from \($0)" } ?? ""
        Logger.warning("HEIC encoding failed\(logContext), falling back to JPEG")
        return resizeImage(from: imageData, to: targetSize)
    }

    /// Encode a CGImage as HEIC data.
    static func encodeHEIC(_ cgImage: CGImage, quality: CGFloat = 0.8) -> Data? {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            data as CFMutableData,
            UTType.heic.identifier as CFString,
            1,
            nil
        ) else { return nil }
        CGImageDestinationAddImage(destination, cgImage, [
            kCGImageDestinationLossyCompressionQuality: quality
        ] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else {
            Logger.warning("Failed to encode image as HEIC")
            return nil
        }
        return data as Data
    }

    /// Resize an image from Data to specified size and return as JPEG Data
    /// - Parameters:
    ///   - imageData: Original image data
    ///   - size: Target size (will be used for both width and height)
    ///   - compressionFactor: JPEG compression quality (0.0 to 1.0)
    /// - Returns: Resized JPEG data, or nil if resizing fails
    static func resizeImage(from imageData: Data, to size: NSSize, compressionFactor: Float = 0.8) -> Data? {
        guard let image = NSImage(data: imageData) else { return nil }
        
        guard let resized = image.resized(to: size),
              let tiffData = resized.tiffRepresentation,
              let bitmapRep = NSBitmapImageRep(data: tiffData) else { return nil }
        
        return bitmapRep.representation(using: .jpeg, properties: [.compressionFactor: compressionFactor])
    }
    
    /// Common sizes used in the app
    enum Size {
        static let small = NSSize(width: ViewDefaults.tableArtworkSize * 2, height: ViewDefaults.tableArtworkSize * 2)    // Table view (2x retina)
        static let medium = NSSize(width: ViewDefaults.listArtworkSize * 2, height: ViewDefaults.listArtworkSize * 2)     // List view (2x retina)
        static let large = NSSize(width: ViewDefaults.gridArtworkSize * 2, height: ViewDefaults.gridArtworkSize * 2)      // Grid view (2x retina)
    }
}
