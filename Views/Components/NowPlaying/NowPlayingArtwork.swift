import SwiftUI
import AppKit

/// Shared now-playing artwork helpers used by the surfaces that render the current
/// track's art and artwork-derived colors (the main player bar, mini player, and
/// immersive mode). Centralizes the tint / image-decode / gradient logic so the
/// hosts don't each carry their own copy.
///
/// The tint and gradient honor the Appearance settings: callers resolve the relevant
/// toggles ("Tint interface with album artwork colors" plus the controls / background
/// sub-toggles) and pass the result as the `useArtworkTint` / `enabled` flag.
enum NowPlayingArtwork {
    /// Primary artwork color, used to tint controls / highlights. Falls back to the
    /// accent color when tinting is disabled or artwork colors are unavailable.
    static func tint(for track: Track?, useArtworkTint: Bool) -> Color {
        guard useArtworkTint, let dominant = track?.dominantColors.first else {
            return .accentColor
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
    static func controlColor(for track: Track?, useArtworkTint: Bool, isDarkBackground: Bool) -> Color {
        guard useArtworkTint, let dominant = track?.dominantColors.first else {
            return .accentColor
        }

        let srgb = dominant.usingColorSpace(.sRGB) ?? dominant
        var hue: CGFloat = 0, saturation: CGFloat = 0, brightness: CGFloat = 0, alpha: CGFloat = 0
        srgb.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha)

        if isDarkBackground {
            // Brighten and slightly tame saturation so it pops without glowing.
            return Color(hue: Double(hue), saturation: Double(min(saturation, 0.9)), brightness: Double(max(brightness, 0.8)))
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

    /// Decodes the track's embedded artwork into an image (nil when absent).
    static func image(for track: Track?) -> NSImage? {
        guard let data = track?.artworkData else { return nil }
        return NSImage(data: data)
    }

    /// Artwork-derived background gradient (cached per track), or empty when disabled
    /// or artwork colors are unavailable.
    static func gradient(for track: Track?, isDark: Bool, enabled: Bool) -> [Color] {
        guard enabled, let track, !track.dominantColors.isEmpty else {
            return []
        }
        return track.backgroundGradientColors(isDark: isDark)
    }
}
