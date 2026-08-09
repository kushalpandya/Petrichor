import SwiftUI
import AppKit

struct ArtworkColorSnapshot: Codable {
    struct Components: Codable {
        let red: Double
        let green: Double
        let blue: Double
        let alpha: Double
    }

    let colors: [Components]

    init?(colors: [NSColor]) {
        let components = colors.compactMap { color -> Components? in
            guard let rgb = color.usingColorSpace(.sRGB) else { return nil }
            return Components(
                red: Double(rgb.redComponent),
                green: Double(rgb.greenComponent),
                blue: Double(rgb.blueComponent),
                alpha: Double(rgb.alphaComponent)
            )
        }
        guard !components.isEmpty else { return nil }
        self.colors = components
    }

    var nsColors: [NSColor] {
        colors.map {
            NSColor(
                srgbRed: CGFloat($0.red),
                green: CGFloat($0.green),
                blue: CGFloat($0.blue),
                alpha: CGFloat($0.alpha)
            )
        }
    }
}

/// A track or a station, so the now-playing surfaces don't each branch on which.
struct NowPlayingSource {
    /// Identity for the artwork colour caches; a track's UUID or a station's derived one.
    let id: UUID
    let title: String
    let subtitle: String
    let artworkData: Data?

    var dominantColors: [NSColor] {
        guard let artworkData else { return [] }
        return ImageUtils.cachedDominantColors(id: id, imageData: artworkData)
    }

    func backgroundGradientColors(isDark: Bool) -> [Color] {
        guard let artworkData else { return [] }
        return ImageUtils.cachedBackgroundGradientColors(id: id, imageData: artworkData, isDark: isDark)
    }
}

/// Shared now-playing artwork helpers used by the surfaces that render the current
/// source's art and artwork-derived colors (the main player bar, mini player, and
/// immersive mode). Centralizes the tint / image-decode / gradient logic so the
/// hosts don't each carry their own copy.
///
/// The tint and gradient honor the Appearance settings: callers resolve the relevant
/// toggles ("Tint interface with album artwork colors" plus the controls / background
/// sub-toggles) and pass the result as the `useArtworkTint` / `enabled` flag.
enum NowPlayingArtwork {
    /// Primary artwork color, used to tint controls / highlights. Falls back to the
    /// accent color when tinting is disabled or artwork colors are unavailable.
    static func tint(for source: NowPlayingSource?, useArtworkTint: Bool) -> Color {
        guard useArtworkTint, let dominant = source?.dominantColors.first else {
            // Use the system accent (the empty AccentColor asset means Color.accentColor won't track it).
            return Color(nsColor: .controlAccentColor)
        }
        return Color(nsColor: dominant)
    }

    /// A luminance-adjusted dominant color for the secondary transport controls
    /// (shuffle/repeat, prev/next, progress, volume), kept legible against the host
    /// surface. Falls back to the accent color when tinting is disabled or artwork
    /// colors are unavailable.
    ///
    /// - Parameter isDarkBackground: when `true` the color is brightened so it reads
    ///   on dark surfaces (the mini player / immersive scrim, or the player bar in
    ///   dark mode); when `false` it is deepened for light surfaces (the player bar
    ///   in light mode).
    static func controlColor(for source: NowPlayingSource?, useArtworkTint: Bool, isDarkBackground: Bool) -> Color {
        // Tinting off: use the system accent (the empty AccentColor asset means Color.accentColor won't track it).
        guard useArtworkTint else { return Color(nsColor: .controlAccentColor) }
        // Tinting on but nothing playing: transport controls use the primary label color.
        guard let dominant = source?.dominantColors.first else { return .primary }

        let srgb = dominant.usingColorSpace(.sRGB) ?? dominant
        var hue: CGFloat = 0, saturation: CGFloat = 0, brightness: CGFloat = 0, alpha: CGFloat = 0
        srgb.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha)

        if isDarkBackground {
            // Push saturation up and ease the brightness floor down so the color
            // reads rich rather than pale, while staying bright enough for dark
            // surfaces. The multiplicative saturation bump leaves grays gray.
            return Color(hue: Double(hue), saturation: Double(min(1, saturation * 1.25)), brightness: Double(max(brightness, 0.74)))
        } else {
            // Deepen so it contrasts against light surfaces; the multiplicative
            // saturation bump keeps color identity while leaving grays gray.
            return Color(hue: Double(hue), saturation: Double(min(1, saturation * 1.15)), brightness: Double(min(brightness, 0.5)))
        }
    }

    /// Rec. 601 relative luminance (0...1) of a color, evaluated in sRGB. Used by the
    /// now-playing surfaces to decide whether light or dark foreground reads better.
    static func luminance(of color: Color) -> CGFloat {
        let ns = NSColor(color).usingColorSpace(.sRGB) ?? NSColor(color)
        return 0.299 * ns.redComponent + 0.587 * ns.greenComponent + 0.114 * ns.blueComponent
    }

    static func image(for source: NowPlayingSource?) -> NSImage? {
        guard let data = source?.artworkData else { return nil }
        return NSImage(data: data)
    }

    /// Artwork-derived background gradient (cached per source), or empty when disabled
    /// or artwork colors are unavailable.
    static func gradient(for source: NowPlayingSource?, isDark: Bool, enabled: Bool) -> [Color] {
        guard enabled, let source, !source.dominantColors.isEmpty else {
            return []
        }
        return source.backgroundGradientColors(isDark: isDark)
    }
}
