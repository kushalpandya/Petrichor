import AppKit
import CoreText

// Split out of `ImageUtils`, which is at SwiftLint's type-length limit.

private final class CategoryArtworkOperation: Operation, @unchecked Sendable {
    private let continuation: CheckedContinuation<Data?, Never>
    private let work: (@escaping () -> Bool) -> Data?

    init(
        continuation: CheckedContinuation<Data?, Never>,
        work: @escaping (@escaping () -> Bool) -> Data?
    ) {
        self.continuation = continuation
        self.work = work
        super.init()
    }

    override func main() {
        continuation.resume(returning: isCancelled ? nil : work { self.isCancelled })
    }
}

// MARK: - Procedural Artwork Style

/// Visual family for generated artwork: a hue band plus a background figure, one per type.
enum CategoryArtworkStyle: String {
    case genre
    case year
    case decade
    case folder
    /// Pre-1.7 look. Radio stations bake artwork at creation, so this must not change.
    case plain

    /// Narrow hue range per type, except genres, which take the whole wheel.
    private var hueBand: (start: CGFloat, span: CGFloat) {
        switch self {
        case .genre: return (0, 1)         // full wheel
        case .year: return (0.45, 0.17)    // teal → blue
        case .decade: return (0.03, 0.11)  // amber → peach
        case .folder: return (0.25, 0.13)  // sage → green
        case .plain: return (0, 1)
        }
    }

    /// Hue distance between a tile's two stops, capped so one tile never reads as a duotone.
    private var gradientSpread: CGFloat {
        min(hueBand.span * 0.45, 0.1)
    }

    /// Bucketed so two entities either share a hue or differ visibly, never collide invisibly.
    private var hueBucketCount: Int {
        max(6, Int((hueBand.span * 24).rounded()))
    }

    private static let goldenRatio: CGFloat = 0.618033988749895

    /// Only years and decades: short fixed-width values that won't truncate at tile size.
    var drawsLabel: Bool {
        self == .year || self == .decade
    }

    func palette(hue hueHash: Int, isDark: Bool) -> CategoryArtworkPalette {
        let band = hueBand

        if self == .plain {
            // Preserved verbatim: golden-ratio hue spacing across the full wheel.
            let goldenRatio = Self.goldenRatio
            let hue = CGFloat(hueHash % 997) / 997.0
            let secondHue = (hue + goldenRatio).truncatingRemainder(dividingBy: 1.0)
            let thirdHue = (hue + goldenRatio * 2).truncatingRemainder(dividingBy: 1.0)
            return CategoryArtworkPalette(
                start: NSColor(hue: hue, saturation: 0.55, brightness: 0.85, alpha: 1),
                end: NSColor(hue: secondHue, saturation: 0.5, brightness: 0.8, alpha: 1),
                accent: NSColor(hue: thirdHue, saturation: 0.5, brightness: 0.9, alpha: 1),
                accentAlpha: 0.2,
                label: .white
            )
        }

        // Golden-ratio stepping, so consecutive buckets land far apart on the band.
        let bucket = hueHash % hueBucketCount
        let position = (CGFloat(bucket) * Self.goldenRatio).truncatingRemainder(dividingBy: 1.0)
        let hue = (band.start + position * band.span).truncatingRemainder(dividingBy: 1.0)
        let secondHue = (hue + gradientSpread).truncatingRemainder(dividingBy: 1.0)

        // Tone varies within a bucket, so a hue collision still reads as a different shade.
        let tone = CGFloat(ImageUtils.mix(hueHash, 11) % 101) / 100.0 - 0.5

        func tint(_ hue: CGFloat, saturation: CGFloat, brightness: CGFloat) -> NSColor {
            NSColor(
                hue: hue,
                saturation: min(max(saturation + tone * 0.14, 0.15), 0.7),
                brightness: min(max(brightness - tone * 0.05, 0.22), 0.98),
                alpha: 1
            )
        }

        // Pastel in light mode, pulled down in dark so a wall of tiles doesn't glare.
        return CategoryArtworkPalette(
            start: tint(hue, saturation: isDark ? 0.42 : 0.34, brightness: isDark ? 0.42 : 0.94),
            end: tint(secondHue, saturation: isDark ? 0.5 : 0.46, brightness: isDark ? 0.30 : 0.86),
            accent: NSColor(hue: secondHue, saturation: isDark ? 0.35 : 0.30, brightness: isDark ? 0.62 : 1.0, alpha: 1),
            accentAlpha: isDark ? 0.14 : 0.32,
            // Stepped away from the backdrop's brightness, or the number is as faint as the lines.
            label: isDark
                ? NSColor(hue: secondHue, saturation: 0.22, brightness: 0.95, alpha: 0.42)
                : NSColor(hue: secondHue, saturation: 0.38, brightness: 0.58, alpha: 0.5)
        )
    }
}

struct CategoryArtworkPalette {
    let start: NSColor
    let end: NSColor
    let accent: NSColor
    let accentAlpha: CGFloat
    let label: NSColor
}

extension ImageUtils {
    private static let generationQueue: OperationQueue = {
        let queue = OperationQueue()
        queue.maxConcurrentOperationCount = max(2, ProcessInfo.processInfo.activeProcessorCount / 2)
        queue.qualityOfService = .utility
        return queue
    }()

    private static let generatedArtworkCache: NSCache<NSString, NSData> = {
        let cache = NSCache<NSString, NSData>()
        // The key carries the colour scheme, so both appearances would otherwise be retained.
        cache.countLimit = 1_000
        cache.totalCostLimit = 24 * 1024 * 1024
        return cache
    }()

    /// Scheme is in the key: each style renders a light and a dark variant off the same seed.
    private static func artworkCacheKey(seed: String, style: CategoryArtworkStyle, isDark: Bool) -> NSString {
        "\(seed)-\(style.rawValue)-\(isDark ? "d" : "l")" as NSString
    }

    /// Cache lookup only, so it is safe in a view body; nil if nothing has rendered yet.
    static func generatedCategoryArtwork(seed: String, style: CategoryArtworkStyle, isDark: Bool) -> Data? {
        generatedArtworkCache.object(forKey: artworkCacheKey(seed: seed, style: style, isDark: isDark)) as Data?
    }

    /// The off-main hop every procedural entity takes to render its artwork.
    static func proceduralArtwork(
        seed: String,
        style: CategoryArtworkStyle,
        isDark: Bool,
        label: String? = nil
    ) async -> Data? {
        final class Holder: @unchecked Sendable {
            var operation: CategoryArtworkOperation?
        }
        let holder = Holder()

        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                let operation = CategoryArtworkOperation(continuation: continuation) { isCancelled in
                    cachedCategoryArtwork(
                        seed: seed,
                        style: style,
                        isDark: isDark,
                        label: label,
                        isCancelled: isCancelled
                    )
                }
                holder.operation = operation
                generationQueue.addOperation(operation)
            }
        } onCancel: {
            holder.operation?.cancel()
        }
    }

    static func cachedCategoryArtwork(
        seed: String,
        style: CategoryArtworkStyle,
        isDark: Bool,
        label: String? = nil,
        isCancelled: () -> Bool = { false }
    ) -> Data? {
        let cacheKey = artworkCacheKey(seed: seed, style: style, isDark: isDark)
        if let cached = generatedArtworkCache.object(forKey: cacheKey) {
            return cached as Data
        }

        guard !isCancelled() else { return nil }
        let generated = generateCategoryArtwork(
            seed: seed,
            style: style,
            isDark: isDark,
            label: label,
            isCancelled: isCancelled
        )
        if let generated {
            generatedArtworkCache.setObject(generated as NSData, forKey: cacheKey, cost: generated.count)
        }
        return generated
    }

    // MARK: - Procedural Artwork

    /// Mix two integers into a new pseudo-random value (xorshift-style)
    fileprivate static func mix(_ a: Int, _ b: Int) -> Int {
        var x = a &+ b &* 2654435761
        x ^= (x >> 16)
        x &*= 0x45d9f3b
        x ^= (x >> 16)
        return x & Int.max
    }

    /// Deterministic: the same seed and style always produce the same image.
    static func generateCategoryArtwork(
        seed: String,
        style: CategoryArtworkStyle,
        isDark: Bool,
        label: String? = nil,
        isCancelled: () -> Bool = { false }
    ) -> Data? {
        guard !isCancelled() else { return nil }
        let size = 240
        let hash = seed.deterministicHash
        let colorSpace = CGColorSpaceCreateDeviceRGB()

        guard let ctx = CGContext(
            data: nil,
            width: size,
            height: size,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        ) else { return nil }

        let hColor = mix(hash, 1)
        let hLayout = mix(hash, 2)
        let hAngle = mix(hash, 3)

        let palette = style.palette(hue: hColor, isDark: isDark)

        let angle = CGFloat(hAngle % 628) / 100.0  // 0 to ~2π
        let endX = CGFloat(size) * (0.5 + 0.5 * cos(angle))
        let endY = CGFloat(size) * (0.5 + 0.5 * sin(angle))

        guard let gradient = CGGradient(
            colorsSpace: colorSpace,
            colors: [palette.start.cgColor, palette.end.cgColor] as CFArray,
            locations: [0, 1]
        ) else { return nil }

        ctx.drawLinearGradient(
            gradient,
            start: CGPoint(x: CGFloat(size) - endX, y: CGFloat(size) - endY),
            end: CGPoint(x: endX, y: endY),
            options: [.drawsBeforeStartLocation, .drawsAfterEndLocation]
        )

        guard !isCancelled() else { return nil }
        drawGeometry(in: ctx, size: size, style: style, palette: palette, layoutHash: hLayout)

        guard !isCancelled() else { return nil }
        if style.drawsLabel, let label, !label.isEmpty {
            drawCornerLabel(label, in: ctx, size: size, color: palette.label)
        }

        guard !isCancelled() else { return nil }
        guard let cgImage = ctx.makeImage() else { return nil }
        return encodeJPEG(cgImage, quality: 0.85)
    }

    /// Background figure under the label; each style draws a different one.
    private static func drawGeometry(
        in ctx: CGContext,
        size: Int,
        style: CategoryArtworkStyle,
        palette: CategoryArtworkPalette,
        layoutHash: Int
    ) {
        let side = CGFloat(size)

        switch style {
        case .plain, .genre:
            // Scattered organic shapes, the look Petrichor has shipped since 1.6.
            for index in 0..<(3 + layoutHash % 3) {
                let shapeHash = mix(layoutHash, index &* 31)
                let x = CGFloat(shapeHash % (size + 80)) - 40
                let y = CGFloat(mix(shapeHash, 7) % (size + 80)) - 40
                let diameter = CGFloat(100 + mix(shapeHash, 13) % 120)
                ctx.setFillColor(
                    (index.isMultiple(of: 2) ? palette.accent : palette.start)
                        .withAlphaComponent(palette.accentAlpha + CGFloat(mix(shapeHash, 19) % 15) / 100)
                        .cgColor
                )

                switch mix(shapeHash, 37) % 3 {
                case 0:
                    ctx.fillEllipse(in: CGRect(x: x - diameter / 2, y: y - diameter / 2, width: diameter, height: diameter))
                case 1:
                    ctx.addPath(CGPath(
                        roundedRect: CGRect(x: x - diameter / 2, y: y - diameter / 2, width: diameter, height: diameter * 0.75),
                        cornerWidth: 16,
                        cornerHeight: 16,
                        transform: nil
                    ))
                    ctx.fillPath()
                default:
                    ctx.saveGState()
                    ctx.translateBy(x: x, y: y)
                    ctx.rotate(by: .pi / 4)
                    let radius = diameter * 0.4
                    ctx.fill(CGRect(x: -radius, y: -radius, width: radius * 2, height: radius * 2))
                    ctx.restoreGState()
                }
            }

        case .year:
            // Vertical bars, reading as measured rather than organic.
            let barCount = 11
            let barWidth = side / CGFloat(barCount * 2 - 1)
            ctx.setFillColor(palette.accent.withAlphaComponent(palette.accentAlpha).cgColor)
            for index in 0..<barCount {
                let height = side * (0.25 + CGFloat(mix(layoutHash, index &* 17) % 60) / 100)
                ctx.fill(CGRect(x: CGFloat(index * 2) * barWidth, y: 0, width: barWidth, height: height))
            }

        case .decade:
            let corner = mix(layoutHash, 5) % 4
            let origin = CGPoint(
                x: corner == 1 || corner == 2 ? side : 0,
                y: corner >= 2 ? side : 0
            )
            ctx.setFillColor(palette.accent.withAlphaComponent(palette.accentAlpha).cgColor)
            let rayCount = 9
            for index in stride(from: 0, to: rayCount, by: 2) {
                let start = (.pi / 2) * CGFloat(index) / CGFloat(rayCount) + CGFloat(corner) * (.pi / 2)
                let end = (.pi / 2) * CGFloat(index + 1) / CGFloat(rayCount) + CGFloat(corner) * (.pi / 2)
                let reach = side * 1.6
                ctx.beginPath()
                ctx.move(to: origin)
                ctx.addLine(to: CGPoint(x: origin.x + cos(start) * reach, y: origin.y + sin(start) * reach))
                ctx.addLine(to: CGPoint(x: origin.x + cos(end) * reach, y: origin.y + sin(end) * reach))
                ctx.closePath()
                ctx.fillPath()
            }

        case .folder:
            // Stacked sheets, echoing the folder metaphor.
            ctx.setFillColor(palette.accent.withAlphaComponent(palette.accentAlpha).cgColor)
            for index in 0..<3 {
                let inset = side * (0.12 + CGFloat(index) * 0.09)
                let offset = side * 0.05 * CGFloat(index)
                ctx.addPath(CGPath(
                    roundedRect: CGRect(x: inset + offset, y: inset - offset, width: side - inset * 2, height: side - inset * 2),
                    cornerWidth: 18,
                    cornerHeight: 18,
                    transform: nil
                ))
                ctx.fillPath()
            }
        }
    }

    /// Core Text, not `NSString.draw`: no `NSGraphicsContext` here, so that would draw nothing.
    private static func drawCornerLabel(_ text: String, in ctx: CGContext, size: Int, color: NSColor) {
        let side = CGFloat(size)
        let inset = side * 0.045
        let available = side - inset * 2

        // Optical bounds, not typographic: ascent overshoots digits and unbalances the top margin.
        func line(at fontSize: CGFloat) -> (line: CTLine, ink: CGRect) {
            let attributed = NSAttributedString(string: text, attributes: [
                .font: NSFont.systemFont(ofSize: fontSize, weight: .bold),
                .foregroundColor: color
            ])
            let line = CTLineCreateWithAttributedString(attributed)
            return (line, CTLineGetBoundsWithOptions(line, .useOpticalBounds))
        }

        var measured = line(at: side * 0.25)

        // Shrink to fit rather than truncate; below the floor it's unreadable, so drop it.
        if measured.ink.width > available {
            let fitted = side * 0.25 * (available / measured.ink.width)
            guard fitted >= side * 0.08 else { return }
            measured = line(at: fitted)
        }

        ctx.saveGState()
        ctx.textMatrix = .identity
        // `maxX`/`maxY`: the ink rect is relative to the text origin.
        ctx.textPosition = CGPoint(
            x: side - inset - measured.ink.maxX,
            y: side - inset - measured.ink.maxY
        )
        CTLineDraw(measured.line, ctx)
        ctx.restoreGState()
    }

    /// Baked in rather than overlaid by the view, so rows and the player bar get it too.
    static func generateStationArtwork(name: String) -> Data? {
        let size = 240
        guard let backgroundData = generateCategoryArtwork(seed: "station-\(name)", style: .plain, isDark: false),
              let backgroundSource = CGImageSourceCreateWithData(backgroundData as CFData, nil),
              let background = CGImageSourceCreateImageAtIndex(backgroundSource, 0, nil) else { return nil }

        guard let ctx = CGContext(
            data: nil,
            width: size,
            height: size,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        ) else { return nil }

        let full = CGRect(x: 0, y: 0, width: size, height: size)
        ctx.draw(background, in: full)

        // Near-black rather than gray: the generated gradients sit at high brightness,
        // so a mid-gray glyph washes out against them.
        let symbolConfig = NSImage.SymbolConfiguration(pointSize: 128, weight: .semibold)
            .applying(NSImage.SymbolConfiguration(paletteColors: [NSColor(white: 0.11, alpha: 1)]))
        guard let symbol = NSImage(systemSymbolName: Icons.antennaRadiowaves, accessibilityDescription: nil)?
            .withSymbolConfiguration(symbolConfig),
            let symbolImage = symbol.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            // Without the glyph the gradient alone is still usable artwork.
            return backgroundData
        }

        let glyphHeight = CGFloat(size) * 0.52
        let glyphWidth = glyphHeight * CGFloat(symbolImage.width) / CGFloat(symbolImage.height)
        let glyphRect = CGRect(
            x: (CGFloat(size) - glyphWidth) / 2,
            y: (CGFloat(size) - glyphHeight) / 2,
            width: glyphWidth,
            height: glyphHeight
        )

        // No flip: `CGContext.draw` already lands the image upright in a bottom-left
        // origin context. Getting this wrong renders it upside down.
        ctx.saveGState()
        // A light halo, not a dark shadow: it separates a dark glyph from dark gradient.
        ctx.setShadow(offset: .zero, blur: 12, color: NSColor.white.withAlphaComponent(0.65).cgColor)
        ctx.draw(symbolImage, in: glyphRect)
        ctx.restoreGState()

        guard let cgImage = ctx.makeImage() else { return backgroundData }
        return encodeJPEG(cgImage, quality: 0.85)
    }
}
