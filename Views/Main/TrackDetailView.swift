import SwiftUI

struct TrackDetailView: View {
    let track: Track
    let onClose: () -> Void
    
    @State private var fullTrack: FullTrack?
    @State private var isLoading = true
    @EnvironmentObject var libraryManager: LibraryManager

    var body: some View {
        VStack(spacing: 0) {
            // Header with close button
            headerSection

            Divider()

            // Show loading or content based on state
            if isLoading && fullTrack == nil {
                // Loading state
                VStack {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .scaleEffect(0.8)
                    Text("Loading track details...")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.top, 8)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let fullTrack = fullTrack {
                ScrollView {
                    VStack(spacing: 24) {
                        // Album artwork
                        artworkSection(for: fullTrack)

                        // Track info
                        trackInfoSection(for: fullTrack)

                        // Combined Track Information section
                        let items = trackInformationItems(for: fullTrack)
                        if !items.isEmpty {
                            metadataSection(title: "Details", items: items)
                        }

                        // Collapsible File Details section
                        FileDetailsSection(fullTrack: fullTrack)
                    }
                    .padding(20)
                }
            } else {
                VStack(spacing: 16) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 48))
                        .foregroundColor(.secondary)
                    Text("Unable to load track details")
                        .font(.headline)
                    Text("The track information could not be retrieved.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .onAppear {
            if fullTrack == nil {
                loadFullTrack()
            }
        }
        .onChange(of: track.id) { oldId, newId in
            if oldId != newId {
                isLoading = true
                fullTrack = nil
                loadFullTrack()
            }
        }
    }
    
    // MARK: - Load Full Track
    
    private func loadFullTrack() {
        Task {
            do {
                if var loaded = try await track.fullTrack(using: libraryManager.databaseManager.dbQueue) {
                    libraryManager.databaseManager.populateAlbumArtworkForFullTrack(&loaded)
                    
                    await MainActor.run {
                        self.fullTrack = loaded
                        self.isLoading = false
                    }
                } else {
                    await MainActor.run {
                        self.isLoading = false
                    }
                }
            } catch {
                Logger.error("Failed to load full track: \(error)")
                await MainActor.run {
                    self.isLoading = false
                }
            }
        }
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

    private func artworkSection(for fullTrack: FullTrack) -> some View {
        ZStack {
            if let artworkData = fullTrack.artworkData,
               let nsImage = NSImage(data: artworkData) {
                Image(nsImage: nsImage)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 250, height: 250)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .shadow(color: .black.opacity(0.2), radius: 10, x: 0, y: 5)
                    .id(fullTrack.id)
            } else {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.gray.opacity(0.2))
                    .frame(width: 250, height: 250)
                    .overlay(
                        Image(systemName: Icons.musicNote)
                            .font(.system(size: 60))
                            .foregroundColor(.secondary)
                    )
                    .id("placeholder-\(fullTrack.id)")
            }
        }
        .padding(.top, 10)
    }

    // MARK: - Track Info Section

    private func trackInfoSection(for fullTrack: FullTrack) -> some View {
        VStack(spacing: 8) {
            Text(fullTrack.title)
                .font(.title2)
                .fontWeight(.semibold)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .textSelection(.enabled)

            Text(fullTrack.artist)
                .font(.title3)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .textSelection(.enabled)

            if !fullTrack.album.isEmpty && fullTrack.album != "Unknown Album" {
                Text(fullTrack.album)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .textSelection(.enabled)
            }
            
            if fullTrack.isLossless {
                HStack(spacing: 5) {
                    Image(Icons.customLossless)
                        .renderingMode(.template)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 14, height: 14)
                        .foregroundColor(.secondary)

                    Text("Lossless")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
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

    private func trackInformationItems(for fullTrack: FullTrack) -> [(label: String, value: String)] {
        var items: [(label: String, value: String)] = []

        // Album (added as requested)
        if !fullTrack.album.isEmpty && fullTrack.album != "Unknown Album" {
            items.append(("Album", fullTrack.album))
        }

        // Album Artist
        if let albumArtist = fullTrack.albumArtist, !albumArtist.isEmpty {
            items.append(("Album Artist", albumArtist))
        }

        // Duration
        items.append(("Duration", formatDuration(fullTrack.duration)))

        // Track Number
        if let trackNumber = fullTrack.trackNumber {
            var trackStr = "\(trackNumber)"
            if let totalTracks = fullTrack.totalTracks {
                trackStr += " of \(totalTracks)"
            }
            items.append(("Track", trackStr))
        }

        // Disc Number
        if let discNumber = fullTrack.discNumber {
            var discStr = "\(discNumber)"
            if let totalDiscs = fullTrack.totalDiscs {
                discStr += " of \(totalDiscs)"
            }
            items.append(("Disc", discStr))
        }

        // Genre
        if !fullTrack.genre.isEmpty && fullTrack.genre != "Unknown Genre" {
            items.append(("Genre", fullTrack.genre))
        }

        // Year
        if !fullTrack.year.isEmpty && fullTrack.year != "Unknown Year" {
            items.append(("Year", fullTrack.year))
        }

        // Composer
        if !fullTrack.composer.isEmpty && fullTrack.composer != "Unknown Composer" {
            items.append(("Composer", fullTrack.composer))
        }

        // Release Dates
        if let releaseDate = fullTrack.releaseDate, !releaseDate.isEmpty {
            items.append(("Release Date", formatDate(releaseDate)))
        }

        if let originalDate = fullTrack.originalReleaseDate, !originalDate.isEmpty {
            items.append(("Original Release", formatDate(originalDate)))
        }

        // Additional metadata from extended
        if let ext = fullTrack.extendedMetadata {
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
        if let bpm = fullTrack.bpm, bpm > 0 {
            items.append(("BPM", "\(bpm)"))
        }

        // Rating
        if let rating = fullTrack.rating, rating > 0 {
            items.append(("Rating", String(repeating: "★", count: rating) + String(repeating: "☆", count: 5 - rating)))
        }

        // Play Count
        if fullTrack.playCount > 0 {
            items.append(("Play Count", "\(fullTrack.playCount)"))
        }

        // Last Played
        if let lastPlayed = fullTrack.lastPlayedDate {
            items.append(("Last Played", formatDate(lastPlayed)))
        }

        // Favorite
        if fullTrack.isFavorite {
            items.append(("Favorite", "Yes"))
        }

        // Compilation
        if fullTrack.compilation {
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

    private func formatDate(_ dateString: String) -> String {
        if let date = parseDateString(dateString) {
            let formatter = DateFormatter()
            formatter.dateStyle = .medium
            formatter.timeStyle = .short
            return formatter.string(from: date)
        }
        
        return dateString
    }

    private func parseDateString(_ dateString: String) -> Date? {
        let iso8601Formatter = ISO8601DateFormatter()
        if let date = iso8601Formatter.date(from: dateString) {
            return date
        }
        
        let dateFormatter = DateFormatter()
        
        let formats = ["yyyy-MM-dd", "yyyy-MM", "yyyy"]
        for format in formats {
            dateFormatter.dateFormat = format
            if let date = dateFormatter.date(from: dateString) {
                return date
            }
        }
        
        return nil
    }
}

// MARK: - File Details Section View

private struct FileDetailsSection: View {
    let fullTrack: FullTrack
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
        items.append(("Format", fullTrack.format.uppercased()))

        // Audio properties
        if let codec = fullTrack.codec, !codec.isEmpty {
            items.append(("Codec", codec))
        }

        if let bitrate = fullTrack.bitrate, bitrate > 0 {
            items.append(("Bitrate", "\(bitrate) kbps"))
        }

        if let sampleRate = fullTrack.sampleRate, sampleRate > 0 {
            let formatted = formatSampleRate(sampleRate)
            items.append(("Sample Rate", formatted))
        }

        if let bitDepth = fullTrack.bitDepth, bitDepth > 0 {
            items.append(("Bit Depth", "\(bitDepth)-bit"))
        }

        if let channels = fullTrack.channels, channels > 0 {
            items.append(("Channels", formatChannels(channels)))
        }

        // File info
        if let fileSize = fullTrack.fileSize, fileSize > 0 {
            items.append(("File Size", formatFileSize(fileSize)))
        }

        // File path
        items.append(("File Path", fullTrack.url.path))

        // Dates
        if let dateAdded = fullTrack.dateAdded {
            items.append(("Date Added", formatDate(dateAdded)))
        }

        if let dateModified = fullTrack.dateModified {
            items.append(("Date Modified", formatDate(dateModified)))
        }

        // Media Type
        if let mediaType = fullTrack.mediaType, !mediaType.isEmpty {
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
        return track
    }()

    TrackDetailView(track: sampleTrack) {}
        .frame(width: 350, height: 700)
        .environmentObject(LibraryManager())
}
