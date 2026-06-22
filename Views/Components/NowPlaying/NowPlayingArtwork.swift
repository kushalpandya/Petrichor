import SwiftUI
import AppKit

/// Shared now-playing artwork helpers used by the immersive-style surfaces that
/// render the current track's art and artwork-derived colors (the mini player and
/// immersive mode). Centralizes the tint / image-decode / gradient logic so the
/// hosts don't each carry their own copy.
///
/// Unlike the main-window backgrounds, these surfaces always use the artwork colors
/// and intentionally ignore the "Use album artwork colors" setting.
enum NowPlayingArtwork {
    /// Primary artwork color, used to tint controls / highlights. Falls back to the
    /// accent color when artwork colors are unavailable.
    static func tint(for track: Track?) -> Color {
        guard let dominant = track?.dominantColors.first else {
            return .accentColor
        }
        return Color(nsColor: dominant)
    }

    /// Decodes the track's embedded artwork into an image (nil when absent).
    static func image(for track: Track?) -> NSImage? {
        guard let data = track?.artworkData else { return nil }
        return NSImage(data: data)
    }

    /// Artwork-derived background gradient (cached per track), or empty when artwork
    /// colors are unavailable.
    static func gradient(for track: Track?, isDark: Bool) -> [Color] {
        guard let track, !track.dominantColors.isEmpty else {
            return []
        }
        return track.backgroundGradientColors(isDark: isDark)
    }
}
