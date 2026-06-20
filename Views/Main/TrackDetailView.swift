import SwiftUI

struct TrackDetailView: View {
    let track: Track
    let onClose: () -> Void
    
    @State private var fullTrack: FullTrack?
    @State private var isLoading = true
    @State private var gradientColors: [Color] = []

    @AppStorage("useArtworkColors")
    private var useArtworkColors = true

    @EnvironmentObject var libraryManager: LibraryManager
    @Environment(\.colorScheme)
    var colorScheme

    var body: some View {
        ZStack {
            // Background gradient layer
            if !gradientColors.isEmpty {
                LinearGradient(
                    colors: gradientColors + [.clear],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .overlay(.ultraThinMaterial)
                .animation(
                    .easeInOut(duration: AnimationDuration.standardDuration),
                    value: gradientColors
                )
            }

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
                                metadataSection(title: String(localized: "Details"), items: items)
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
        }
        .onAppear {
            if fullTrack == nil {
                loadFullTrack()
            }
            updateGradientColors()
        }
        .onChange(of: track.id) { oldId, newId in
            if oldId != newId {
                isLoading = true
                fullTrack = nil
                loadFullTrack()
                updateGradientColors()
            }
        }
        .onChange(of: colorScheme) {
            updateGradientColors()
        }
        .onChange(of: useArtworkColors) {
            updateGradientColors()
        }
    }

    private func updateGradientColors() {
        guard useArtworkColors else {
            gradientColors = []
            return
        }
        gradientColors = track.backgroundGradientColors(isDark: colorScheme == .dark)
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

            Text(LibraryFilterType.artists.localizedDisplay(fullTrack.artist))
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
                LosslessLabel()
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
                    .fill(.thinMaterial)
            )
        }
    }

    // MARK: - Combined Metadata

    private func trackInformationItems(for fullTrack: FullTrack) -> [(label: String, value: String)] {
        var items: [(label: String, value: String)] = []

        appendBasicTrackInfo(fullTrack, to: &items)
        appendExtendedTrackInfo(fullTrack.extendedMetadata, to: &items)
        appendPlaybackTrackInfo(fullTrack, to: &items)

        return items
    }

    private func appendBasicTrackInfo(_ fullTrack: FullTrack, to items: inout [(label: String, value: String)]) {
        if !fullTrack.album.isEmpty && fullTrack.album != "Unknown Album" {
            items.append((String(localized: "Album"), fullTrack.album))
        }

        if let albumArtist = fullTrack.albumArtist, !albumArtist.isEmpty {
            items.append((String(localized: "Album Artist"), albumArtist))
        }

        items.append((String(localized: "Duration"), HelperUtils.formattedShortDuration(fullTrack.duration)))

        if let trackNumber = fullTrack.trackNumber {
            var trackStr = "\(trackNumber)"
            if let totalTracks = fullTrack.totalTracks {
                trackStr = String(localized: "\(trackNumber) of \(totalTracks)")
            }
            items.append((String(localized: "Track"), trackStr))
        }

        if let discNumber = fullTrack.discNumber {
            var discStr = "\(discNumber)"
            if let totalDiscs = fullTrack.totalDiscs {
                discStr = String(localized: "\(discNumber) of \(totalDiscs)")
            }
            items.append((String(localized: "Disc"), discStr))
        }

        if !fullTrack.genre.isEmpty && fullTrack.genre != "Unknown Genre" {
            items.append((String(localized: "Genre"), fullTrack.genre))
        }

        if !fullTrack.year.isEmpty && fullTrack.year != "Unknown Year" {
            items.append((String(localized: "Year"), fullTrack.year))
        }

        if !fullTrack.composer.isEmpty && fullTrack.composer != "Unknown Composer" {
            items.append((String(localized: "Composer"), fullTrack.composer))
        }

        if let releaseDate = fullTrack.releaseDate, !releaseDate.isEmpty {
            items.append((String(localized: "Release Date"), formatDate(releaseDate)))
        }

        if let originalDate = fullTrack.originalReleaseDate, !originalDate.isEmpty {
            items.append((String(localized: "Original Release"), formatDate(originalDate)))
        }
    }

    private func appendExtendedTrackInfo(_ extendedMetadata: ExtendedMetadata?, to items: inout [(label: String, value: String)]) {
        guard let ext = extendedMetadata else { return }

        if let conductor = ext.conductor, !conductor.isEmpty {
            items.append((String(localized: "Conductor"), conductor))
        }

        if let producer = ext.producer, !producer.isEmpty {
            items.append((String(localized: "Producer"), producer))
        }

        if let label = ext.label, !label.isEmpty {
            items.append((String(localized: "Label"), label))
        }

        if let publisher = ext.publisher, !publisher.isEmpty {
            items.append((String(localized: "Publisher"), publisher))
        }

        if let isrc = ext.isrc, !isrc.isEmpty {
            items.append((String(localized: "ISRC"), isrc))
        }
    }

    private func appendPlaybackTrackInfo(_ fullTrack: FullTrack, to items: inout [(label: String, value: String)]) {
        if let bpm = fullTrack.bpm, bpm > 0 {
            items.append((String(localized: "BPM"), "\(bpm)"))
        }

        if let rating = fullTrack.rating, rating > 0 {
            items.append((String(localized: "Rating"), String(repeating: "★", count: rating) + String(repeating: "☆", count: 5 - rating)))
        }

        if fullTrack.playCount > 0 {
            items.append((String(localized: "Play Count"), "\(fullTrack.playCount)"))
        }

        if let lastPlayed = fullTrack.lastPlayedDate {
            items.append((String(localized: "Last Played"), formatDate(lastPlayed)))
        }

        if fullTrack.isFavorite {
            items.append((String(localized: "Favorite"), String(localized: "Yes")))
        }

        if fullTrack.compilation {
            items.append((String(localized: "Compilation"), String(localized: "Yes")))
        }
    }

    // MARK: - Helper Methods

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
                withAnimation(.easeInOut(duration: AnimationDuration.mediumDuration)) {
                    isExpanded.toggle()
                }
            }, label: {
                HStack {
                    Image(systemName: Icons.chevronRight)
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                        .font(.system(size: 12))

                    Text("File Details")
                        .font(.headline)

                    Spacer()
                }
                .contentShape(Rectangle())
            })
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
                        .fill(.thinMaterial)
                )
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    private var fileDetailsItems: [(label: String, value: String)] {
        var items: [(label: String, value: String)] = []

        // File format
        items.append((String(localized: "Format"), fullTrack.format.uppercased()))

        // Audio properties
        if let codec = fullTrack.codecDisplay {
            items.append((String(localized: "Codec"), codec))
        }

        if let bitrate = fullTrack.bitrateDisplay {
            items.append((String(localized: "Bitrate"), bitrate))
        }

        if let sampleRate = fullTrack.sampleRateDisplay {
            items.append((String(localized: "Sample Rate"), sampleRate))
        }

        if let bitDepth = fullTrack.bitDepth, bitDepth > 0 {
            items.append((String(localized: "Bit Depth"), String(localized: "\(bitDepth)-bit")))
        }

        if let channels = fullTrack.channelsDisplay {
            items.append((String(localized: "Channels"), channels))
        }

        // File info
        if let fileSize = fullTrack.fileSize, fileSize > 0 {
            items.append((String(localized: "File Size"), formatFileSize(fileSize)))
        }

        // File path
        items.append((String(localized: "File Path"), fullTrack.url.path))

        // Dates
        if let dateAdded = fullTrack.dateAdded {
            items.append((String(localized: "Date Added"), formatDate(dateAdded)))
        }

        if let dateModified = fullTrack.dateModified {
            items.append((String(localized: "Date Modified"), formatDate(dateModified)))
        }

        // Media Type
        if let mediaType = fullTrack.mediaType, !mediaType.isEmpty {
            items.append((String(localized: "Media Type"), mediaType))
        }

        return items
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
