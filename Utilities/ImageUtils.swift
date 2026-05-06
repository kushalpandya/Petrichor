import AppKit
import CoreImage
import SwiftUI
import UniformTypeIdentifiers

enum ImageUtils {
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
        #if arch(x86_64)
        return compressImageIntel(from: imageData, maxDimension: maxDimension, quality: quality, source: source)
        #else
        guard let imageSource = CGImageSourceCreateWithData(imageData as CFData, nil),
              let cgImage = CGImageSourceCreateImageAtIndex(imageSource, 0, nil) else {
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
            bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
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
        #endif
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

    /// Encode a CGImage as JPEG data.
    static func encodeJPEG(_ cgImage: CGImage, quality: CGFloat = 0.8) -> Data? {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            data as CFMutableData,
            UTType.jpeg.identifier as CFString,
            1,
            nil
        ) else { return nil }
        CGImageDestinationAddImage(destination, cgImage, [
            kCGImageDestinationLossyCompressionQuality: quality
        ] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else {
            Logger.warning("Failed to encode image as JPEG")
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
        guard let imageSource = CGImageSourceCreateWithData(imageData as CFData, nil),
              let cgImage = CGImageSourceCreateImageAtIndex(imageSource, 0, [
                kCGImageSourceShouldCacheImmediately: true
              ] as CFDictionary) else {
            return nil
        }

        let width = Int(size.width)
        let height = Int(size.height)

        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        ) else { return nil }

        context.interpolationQuality = .high
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))

        guard let resizedCG = context.makeImage() else { return nil }

        return encodeJPEG(resizedCG, quality: CGFloat(compressionFactor))
    }
    
    /// Extract dominant colors from image data using grid-based sampling with diversity selection.
    /// Samples a 4x4 grid via CIAreaAverage, then greedily picks the most distinct colors.
    /// - Parameters:
    ///   - imageData: Image data in any supported format
    ///   - colorCount: Number of dominant colors to return (default: 6)
    /// - Returns: Array of NSColor with maximum color diversity, or empty array if extraction fails
    static func extractDominantColors(
        from imageData: Data,
        colorCount: Int = 6
    ) -> [NSColor] {
        guard let ciImage = CIImage(data: imageData) else { return [] }

        let extent = ciImage.extent
        let gridSize = 4
        let cellW = extent.width / CGFloat(gridSize)
        let cellH = extent.height / CGFloat(gridSize)
        let ctx = CIContext(options: [.workingColorSpace: NSNull()])

        // Sample each grid cell to build candidate colors
        var candidates: [(h: CGFloat, s: CGFloat, b: CGFloat)] = []
        var pixel = [UInt8](repeating: 0, count: 4)

        for row in 0..<gridSize {
            for col in 0..<gridSize {
                let rect = CGRect(
                    x: extent.origin.x + cellW * CGFloat(col),
                    y: extent.origin.y + cellH * CGFloat(row),
                    width: cellW,
                    height: cellH
                )

                guard let filter = CIFilter(
                    name: "CIAreaAverage",
                    parameters: [
                        kCIInputImageKey: ciImage.cropped(to: rect),
                        kCIInputExtentKey: CIVector(cgRect: rect)
                    ]
                ), let output = filter.outputImage else { continue }

                ctx.render(
                    output,
                    toBitmap: &pixel,
                    rowBytes: 4,
                    bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
                    format: .RGBA8,
                    colorSpace: CGColorSpaceCreateDeviceRGB()
                )

                let r = CGFloat(pixel[0]) / 255.0
                let g = CGFloat(pixel[1]) / 255.0
                let b = CGFloat(pixel[2]) / 255.0

                // Clamp near-black to dark grey and near-white to light grey
                let cR = min(max(r, 0.05), 0.9)
                let cG = min(max(g, 0.05), 0.9)
                let cB = min(max(b, 0.05), 0.9)

                var h: CGFloat = 0, s: CGFloat = 0, br: CGFloat = 0
                NSColor(red: cR, green: cG, blue: cB, alpha: 1).getHue(&h, saturation: &s, brightness: &br, alpha: nil)
                candidates.append((h, s, br))
            }
        }

        guard !candidates.isEmpty else { return [] }

        // Greedy farthest-point selection for maximum diversity
        var selected = [candidates.max { $0.s < $1.s }!]

        while selected.count < min(colorCount, candidates.count) {
            var bestIdx = 0
            var bestDist: CGFloat = -1

            for (i, c) in candidates.enumerated() {
                let minDist = selected.map { s -> CGFloat in
                    let hd = min(abs(c.h - s.h), 1 - abs(c.h - s.h))
                    return hd * hd * 4 + (c.s - s.s) * (c.s - s.s) + (c.b - s.b) * (c.b - s.b)
                }.min() ?? 0

                if minDist > bestDist {
                    bestDist = minDist
                    bestIdx = i
                }
            }

            selected.append(candidates[bestIdx])
        }

        return selected.map { NSColor(hue: $0.h, saturation: $0.s, brightness: $0.b, alpha: 1) }
    }

    /// Adjust dominant colors for use as background gradients based on color scheme.
    /// - Parameters:
    ///   - colors: Raw dominant colors from extractDominantColors
    ///   - isDark: Whether the current color scheme is dark mode
    /// - Returns: Array of SwiftUI Colors adjusted for background use
    static func backgroundGradientColors(
        from colors: [NSColor],
        isDark: Bool
    ) -> [Color] {
        colors.map { color -> Color in
            guard let rgb = color.usingColorSpace(.deviceRGB) else { return Color(nsColor: color) }

            var hue: CGFloat = 0
            var saturation: CGFloat = 0
            var brightness: CGFloat = 0
            var alpha: CGFloat = 0
            rgb.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha)

            if isDark {
                brightness = min(brightness, 0.55)
                saturation = min(saturation, 0.8)
            } else {
                brightness = max(brightness, 0.6)
                saturation = min(saturation, 0.7)
            }

            return Color(nsColor: NSColor(
                hue: hue,
                saturation: saturation,
                brightness: brightness,
                alpha: alpha
            ))
        }
    }

    // MARK: - Cached Color Lookups

    private static var colorCache = NSCache<NSString, CachedNSColors>()

    /// Returns cached dominant colors for the given ID, extracting from imageData on cache miss.
    static func cachedDominantColors(
        id: UUID,
        imageData: Data
    ) -> [NSColor] {
        let cacheKey = "\(id.uuidString)-dominantColors" as NSString
        if let cached = colorCache.object(forKey: cacheKey) {
            return cached.colors
        }

        let colors = extractDominantColors(from: imageData)
        colorCache.setObject(CachedNSColors(colors: colors), forKey: cacheKey)
        return colors
    }

    /// Returns cached background gradient colors for the given ID and color scheme.
    static func cachedBackgroundGradientColors(
        id: UUID,
        imageData: Data,
        isDark: Bool
    ) -> [Color] {
        let suffix = isDark ? "dark" : "light"
        let cacheKey = "\(id.uuidString)-gradient-\(suffix)" as NSString
        if let cached = colorCache.object(forKey: cacheKey) {
            return cached.colors.map { Color(nsColor: $0) }
        }

        let dominant = cachedDominantColors(id: id, imageData: imageData)
        let adjusted = backgroundGradientColors(from: dominant, isDark: isDark)
        let nsColors = adjusted.map { NSColor($0) }
        colorCache.setObject(CachedNSColors(colors: nsColors), forKey: cacheKey)
        return adjusted
    }

    // MARK: - Procedural Artwork

    /// Generate deterministic procedural artwork for category entities (Genre, Decade, Year).
    /// Uses the seed string to produce consistent colors and geometric shapes.
    /// - Parameters:
    ///   - text: Display text to render on the artwork
    ///   - seed: Seed string for deterministic randomization
    /// - Returns: JPEG image data, or nil if generation fails
    /// Mix two integers into a new pseudo-random value (xorshift-style)
    private static func mix(_ a: Int, _ b: Int) -> Int {
        var x = a &+ b &* 2654435761
        x ^= (x >> 16)
        x &*= 0x45d9f3b
        x ^= (x >> 16)
        return x & Int.max
    }

    static func generateCategoryArtwork(text: String, seed: String) -> Data? {
        let size = 240
        let h = seed.deterministicHash
        let colorSpace = CGColorSpaceCreateDeviceRGB()

        guard let ctx = CGContext(
            data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        ) else { return nil }

        // Independent hashes for color, layout, and gradient angle
        let hColor = mix(h, 1)
        let hLayout = mix(h, 2)
        let hAngle = mix(h, 3)

        // Golden-ratio hue spacing for maximum visual separation across seeds
        let goldenRatio = 0.618033988749895
        let hue1 = CGFloat(hColor % 997) / 997.0
        let hue2 = (hue1 + goldenRatio).truncatingRemainder(dividingBy: 1.0)
        let hue3 = (hue1 + goldenRatio * 2).truncatingRemainder(dividingBy: 1.0)

        let c1 = NSColor(hue: hue1, saturation: 0.55, brightness: 0.85, alpha: 1)
        let c2 = NSColor(hue: hue2, saturation: 0.5, brightness: 0.8, alpha: 1)
        let c3 = NSColor(hue: hue3, saturation: 0.5, brightness: 0.9, alpha: 1)

        // Gradient angle varies per seed
        let angle = CGFloat(hAngle % 628) / 100.0  // 0 to ~2π
        let endX = CGFloat(size) * (0.5 + 0.5 * cos(angle))
        let endY = CGFloat(size) * (0.5 + 0.5 * sin(angle))
        let startX = CGFloat(size) - endX
        let startY = CGFloat(size) - endY

        let gradient = CGGradient(colorsSpace: colorSpace, colors: [c1.cgColor, c2.cgColor] as CFArray, locations: [0, 1])!
        ctx.drawLinearGradient(gradient, start: CGPoint(x: startX, y: startY), end: CGPoint(x: endX, y: endY),
                               options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])

        // Large geometric shapes — each shape uses an independent seed via mix()
        for i in 0..<(3 + hLayout % 3) {
            let s = mix(hLayout, i &* 31)
            let x = CGFloat(s % (size + 80)) - 40
            let y = CGFloat(mix(s, 7) % (size + 80)) - 40
            let d = CGFloat(100 + mix(s, 13) % 120)
            ctx.setFillColor((i % 2 == 0 ? c3 : c1).withAlphaComponent(0.2 + CGFloat(mix(s, 19) % 15) / 100).cgColor)

            switch mix(s, 37) % 3 {
            case 0:
                ctx.fillEllipse(in: CGRect(x: x - d / 2, y: y - d / 2, width: d, height: d))
            case 1:
                ctx.addPath(CGPath(roundedRect: CGRect(x: x - d / 2, y: y - d / 2, width: d, height: d * 0.75),
                                   cornerWidth: 16, cornerHeight: 16, transform: nil))
                ctx.fillPath()
            default:
                ctx.saveGState()
                ctx.translateBy(x: x, y: y)
                ctx.rotate(by: .pi / 4)
                let r = d * 0.4
                ctx.fill(CGRect(x: -r, y: -r, width: r * 2, height: r * 2))
                ctx.restoreGState()
            }
        }

        // Centered text overlay
        ctx.saveGState()
        ctx.textMatrix = .identity
        ctx.translateBy(x: 0, y: CGFloat(size))
        ctx.scaleBy(x: 1, y: -1)

        let fontSize: CGFloat = text.count <= 5 ? 48 : (text.count <= 12 ? 28 : 20)
        let style = NSMutableParagraphStyle()
        style.alignment = .center
        style.lineBreakMode = .byTruncatingTail
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: fontSize, weight: .bold),
            .foregroundColor: NSColor.white.withAlphaComponent(0.9),
            .paragraphStyle: style
        ]
        let bound = (text as NSString).boundingRect(
            with: CGSize(width: CGFloat(size - 32), height: CGFloat(size)),
            options: .usesLineFragmentOrigin, attributes: attrs
        )
        (text as NSString).draw(
            in: CGRect(x: 16, y: (CGFloat(size) - bound.height) / 2, width: CGFloat(size - 32), height: bound.height + 4),
            withAttributes: attrs
        )
        ctx.restoreGState()

        guard let cgImage = ctx.makeImage() else { return nil }
        return NSBitmapImageRep(cgImage: cgImage).representation(using: .jpeg, properties: [.compressionFactor: 0.85])
    }

    // MARK: - Intel x86_64 fallback
    // Software HEVC encode (VCPHEVC) on Intel deadlocks under concurrent scans (issue #265).
    // Resize-and-JPEG bypasses the encoder entirely. Remove this block when Intel support is dropped.

    #if arch(x86_64)
    private static func compressImageIntel(
        from imageData: Data,
        maxDimension: CGFloat,
        quality: CGFloat,
        source: String?
    ) -> Data? {
        guard let imageSource = CGImageSourceCreateWithData(imageData as CFData, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(imageSource, 0, nil) as? [CFString: Any],
              let width = props[kCGImagePropertyPixelWidth] as? CGFloat,
              let height = props[kCGImagePropertyPixelHeight] as? CGFloat else {
            let context = source.map { " from \($0)" } ?? ""
            Logger.warning("Failed to read image properties\(context) (\(imageData.count) bytes)")
            return nil
        }

        var destWidth = width
        var destHeight = height
        if width > maxDimension || height > maxDimension {
            let scale = min(maxDimension / width, maxDimension / height)
            destWidth = (width * scale).rounded(.down)
            destHeight = (height * scale).rounded(.down)
        }

        return resizeImage(
            from: imageData,
            to: NSSize(width: destWidth, height: destHeight),
            compressionFactor: Float(quality)
        )
    }
    #endif
}

// MARK: - Color Cache Object

private class CachedNSColors: NSObject {
    let colors: [NSColor]
    init(colors: [NSColor]) { self.colors = colors }
}

// MARK: - Deterministic Hash

extension String {
    /// A deterministic hash for seed-based generation (unlike `hashValue` which is randomized per process).
    var deterministicHash: Int {
        var hash = 5381
        for char in utf8 {
            hash = ((hash << 5) &+ hash) &+ Int(char)
        }
        return hash
    }
}
