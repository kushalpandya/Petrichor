import SwiftUI

struct PlayerStationArtView: View, Equatable {
    /// Changes when the artwork does, so editing a playing station's image re-renders.
    let artworkID: UUID
    let artworkData: Data?

    static func == (lhs: PlayerStationArtView, rhs: PlayerStationArtView) -> Bool {
        lhs.artworkID == rhs.artworkID
    }

    var body: some View {
        AlbumArtworkImage(artworkData: artworkData, placeholderIcon: Icons.radioFill, interactive: false)
    }
}

struct PlayerStationDetailsView: View, Equatable {
    let stationName: String
    let nowPlaying: String?
    let description: String?
    let format: StreamFormat?
    let showTechnicalInfo: Bool

    static func == (lhs: PlayerStationDetailsView, rhs: PlayerStationDetailsView) -> Bool {
        lhs.stationName == rhs.stationName &&
        lhs.nowPlaying == rhs.nowPlaying &&
        lhs.description == rhs.description &&
        lhs.showTechnicalInfo == rhs.showTechnicalInfo &&
        lhs.format == rhs.format
    }

    // Matches PlayerTrackDetailsView's metrics so the block doesn't shift.
    private var titleFontSize: CGFloat { showTechnicalInfo ? 14 : 16 }
    private var nowPlayingFontSize: CGFloat { showTechnicalInfo ? 12 : 14 }
    private var descriptionFontSize: CGFloat { showTechnicalInfo ? 11 : 13 }
    private var rowSpacing: CGFloat { showTechnicalInfo ? 4 : 10 }
    private var titleRowHeight: CGFloat { showTechnicalInfo ? 16 : 20 }
    private var textRowHeight: CGFloat { showTechnicalInfo ? 15 : 18 }

    var body: some View {
        VStack(alignment: .leading, spacing: rowSpacing) {
            Text(stationName)
                .font(.system(size: titleFontSize, weight: .medium))
                .lineLimit(1)
                .truncationMode(.tail)
                .help(stationName)
                .frame(height: titleRowHeight)
                .frame(maxWidth: .infinity, alignment: .leading)

            // Only the live line scrolls; a second permanent marquee would burn CPU.
            MarqueeText(
                text: nowPlaying ?? "",
                font: .system(size: nowPlayingFontSize),
                color: .secondary
            )
            .frame(height: textRowHeight)
            .frame(maxWidth: .infinity, alignment: .leading)

            Text(description ?? "")
                .font(.system(size: descriptionFontSize))
                .foregroundColor(.secondary)
                .lineLimit(1)
                .truncationMode(.tail)
                .help(description ?? "")
                .frame(height: textRowHeight)
                .frame(maxWidth: .infinity, alignment: .leading)

            if showTechnicalInfo {
                formatBadgeRow
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var formatBadgeRow: some View {
        HStack(spacing: 4) {
            if let format {
                if let codec = format.codec, !codec.isEmpty {
                    FormatBadge(text: codec.uppercased())
                }
                // The engine reports bits per second; the rest of the UI shows kbps.
                if let bitrate = format.bitrate, bitrate > 0 {
                    FormatBadge(text: "\(bitrate / 1000) kbps")
                }
                if format.sampleRate > 0 {
                    FormatBadge(text: String(format: "%.1f kHz", format.sampleRate / 1000))
                }
                if format.channelCount > 0 {
                    FormatBadge(text: format.channelCount == 1
                        ? String(localized: "Mono")
                        : String(localized: "Stereo"))
                }
            }
        }
        .frame(height: 15)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
