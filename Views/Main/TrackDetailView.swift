import SwiftUI

struct TrackDetailView: View {
    let track: Track
    let onClose: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            // Header with close button
            headerSection

            Divider()

            // Scrollable content
            ScrollView {
                VStack(spacing: 24) {
                    // Album artwork
                    artworkSection

                    // Track info
                    trackInfoSection

                    // Combined Track Information section
                    if !trackInformationItems.isEmpty {
                        metadataSection(title: "Details", items: trackInformationItems)
                    }

                    // Collapsible File Details section
                    FileDetailsSection(track: track)
                }
                .padding(20)
            }
        }
        .background(Color(NSColor.windowBackgroundColor))
    }

    // MARK: - Header Section

    private var headerSection: some View {
        ListHeader {
            HStack(spacing: 12) {
                Button(action: onClose) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                
                Text("Track Info")
                    .headerTitleStyle()
            }

            Spacer()
        }
    }

    // MARK: - Artwork Section

    private var artworkSection: some View {
        ZStack {
            if let artworkData = track.artworkData,
               let nsImage = NSImage(data: artworkData) {
                Image(nsImage: nsImage)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 250, height: 250)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .shadow(color: .black.opacity(0.2), radius: 10, x: 0, y: 5)
                    .id(track.id) // Add stable identity
            } else {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.gray.opacity(0.2))
                    .frame(width: 250, height: 250)
                    .overlay(
                        Image(systemName: Icons.musicNote)
                            .font(.system(size: 60))
                            .foregroundColor(.secondary)
                    )
                    .id("placeholder-\(track.id)")
            }
        }
        .padding(.top, 10)
    }

    // MARK: - Track Info Section

    private var trackInfoSection: some View {
        VStack(spacing: 8) {
            Text(track.title)
                .font(.title2)
                .fontWeight(.semibold)
                .multilineTextAlignment(.center)
                .lineLimit(2)

            Text(track.artist)
                .font(.title3)
                .foregroundColor(.secondary)
                .lineLimit(1)

            if !track.album.isEmpty && track.album != "Unknown Album" {
                Text(track.album)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
        }
    }

    // MARK: - Metadata Section Builder

    private func metadataSection(title: String, items: [(label: String, value: String)]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.headline)
                .foregroundColor(.primary)

            VStack(spacing: 8) {
                ForEach(items, id: \.label) { item in
                    HStack(alignment: .top, spacing: 12) {
                        Text(item.label)
                            .font(.system(size: 13))
                            .foregroundColor(.secondary)
                            .frame(width: 120, alignment: .trailing)

                        Text(item.value)
                            .font(.system(size: 13))
                            .foregroundColor(.primary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                    }
                }
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(NSColor.controlBackgroundColor))
            )
        }
    }

    // MARK: - Combined Metadata

    private var trackInformationItems: [(label: String, value: String)] {
        var items: [(label: String, value: String)] = []

        // Album (added as requested)
        if !track.album.isEmpty && track.album != "Unknown Album" {
            items.append(("Album", track.album))
        }

        // Album Artist
        if let albumArtist = track.albumArtist, !albumArtist.isEmpty {
            items.append(("Album Artist", albumArtist))
        }

        // Duration
        items.append(("Duration", formatDuration(track.duration)))

        // Track Number
        if let trackNumber = track.trackNumber {
            var trackStr = "\(trackNumber)"
            if let totalTracks = track.totalTracks {
                trackStr += " of \(totalTracks)"
            }
            items.append(("Track", trackStr))
        }

        // Disc Number
        if let discNumber = track.discNumber {
            var discStr = "\(discNumber)"
            if let totalDiscs = track.totalDiscs {
                discStr += " of \(totalDiscs)"
            }
            items.append(("Disc", discStr))
        }

        // Genre
        if !track.genre.isEmpty && track.genre != "Unknown Genre" {
            items.append(("Genre", track.genre))
        }

        // Year
        if !track.year.isEmpty && track.year != "Unknown Year" {
            items.append(("Year", track.year))
        }

        // Composer
        if !track.composer.isEmpty && track.composer != "Unknown Composer" {
            items.append(("Composer", track.composer))
        }

        // Release Dates
        if let releaseDate = track.releaseDate, !releaseDate.isEmpty {
            items.append(("Release Date", releaseDate))
        }

        if let originalDate = track.originalReleaseDate, !originalDate.isEmpty {
            items.append(("Original Release", originalDate))
        }

        // Additional metadata from extended
        if let ext = track.extendedMetadata {
            if let conductor = ext.conductor, !conductor.isEmpty {
                items.append(("Conductor", conductor))
            }

            if let producer = ext.producer, !producer.isEmpty {
                items.append(("Producer", producer))
            }

            if let label = ext.label, !label.isEmpty {
                items.append(("Label", label))
            }

            if let publisher = ext.publisher, !publisher.isEmpty {
                items.append(("Publisher", publisher))
            }

            if let isrc = ext.isrc, !isrc.isEmpty {
                items.append(("ISRC", isrc))
            }
        }

        // BPM
        if let bpm = track.bpm, bpm > 0 {
            items.append(("BPM", "\(bpm)"))
        }

        // Rating
        if let rating = track.rating, rating > 0 {
            items.append(("Rating", String(repeating: "★", count: rating) + String(repeating: "☆", count: 5 - rating)))
        }

        // Play Count
        if track.playCount > 0 {
            items.append(("Play Count", "\(track.playCount)"))
        }

        // Last Played
        if let lastPlayed = track.lastPlayedDate {
            items.append(("Last Played", formatDate(lastPlayed)))
        }

        // Favorite
        if track.isFavorite {
            items.append(("Favorite", "Yes"))
        }

        // Compilation
        if track.compilation {
            items.append(("Compilation", "Yes"))
        }

        return items
    }

    // MARK: - Helper Methods

    private func formatDuration(_ seconds: Double) -> String {
        let totalSeconds = Int(max(0, seconds))
        let minutes = totalSeconds / 60
        let remainingSeconds = totalSeconds % 60
        return String(format: StringFormat.mmss, minutes, remainingSeconds)
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

// MARK: - File Details Section View

private struct FileDetailsSection: View {
    let track: Track
    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Collapsible header
            Button(action: {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isExpanded.toggle()
                }
            }) {
                HStack {
                    Image(systemName: Icons.chevronRight)
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                        .font(.system(size: 12))

                    Text("File Details")
                        .font(.headline)

                    Spacer()
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            // Expandable content
            if isExpanded {
                VStack(spacing: 8) {
                    ForEach(fileDetailsItems, id: \.label) { item in
                        HStack(alignment: .top, spacing: 12) {
                            Text(item.label)
                                .font(.system(size: 13))
                                .foregroundColor(.secondary)
                                .frame(width: 120, alignment: .trailing)

                            Text(item.value)
                                .font(.system(size: 13))
                                .foregroundColor(.primary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .textSelection(.enabled)
                        }
                    }
                }
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color(NSColor.controlBackgroundColor))
                )
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    private var fileDetailsItems: [(label: String, value: String)] {
        var items: [(label: String, value: String)] = []

        // File format
        items.append(("Format", track.format.uppercased()))

        // Audio properties
        if let codec = track.codec, !codec.isEmpty {
            items.append(("Codec", codec))
        }

        if let bitrate = track.bitrate, bitrate > 0 {
            items.append(("Bitrate", "\(bitrate) kbps"))
        }

        if let sampleRate = track.sampleRate, sampleRate > 0 {
            let formatted = formatSampleRate(sampleRate)
            items.append(("Sample Rate", formatted))
        }

        if let bitDepth = track.bitDepth, bitDepth > 0 {
            items.append(("Bit Depth", "\(bitDepth)-bit"))
        }

        if let channels = track.channels, channels > 0 {
            items.append(("Channels", formatChannels(channels)))
        }

        // File info
        if let fileSize = track.fileSize, fileSize > 0 {
            items.append(("File Size", formatFileSize(fileSize)))
        }

        // File path
        items.append(("File Path", track.url.path))

        // Dates
        if let dateAdded = track.dateAdded {
            items.append(("Date Added", formatDate(dateAdded)))
        }

        if let dateModified = track.dateModified {
            items.append(("Date Modified", formatDate(dateModified)))
        }

        // Media Type
        if let mediaType = track.mediaType, !mediaType.isEmpty {
            items.append(("Media Type", mediaType))
        }

        return items
    }

    private func formatSampleRate(_ sampleRate: Int) -> String {
        if sampleRate >= 1000 {
            let khz = Double(sampleRate) / 1000.0
            return String(format: "%.1f kHz", khz)
        }
        return "\(sampleRate) Hz"
    }

    private func formatChannels(_ channels: Int) -> String {
        switch channels {
        case 1: return "Mono"
        case 2: return "Stereo"
        case 4: return "Quadraphonic"
        case 6: return "5.1 Surround"
        case 8: return "7.1 Surround"
        default: return "\(channels) channels"
        }
    }

    private func formatFileSize(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

#Preview {
    let sampleTrack = {
        var track = Track(url: URL(fileURLWithPath: "/sample.mp3"))
        track.title = "Sample Song"
        track.artist = "Sample Artist"
        track.album = "Sample Album"
        track.duration = 245.0
        track.genre = "Electronic"
        track.year = "2024"
        track.trackNumber = 5
        track.totalTracks = 12
        return track
    }()

    TrackDetailView(track: sampleTrack) {}
        .frame(width: 350, height: 700)
}
