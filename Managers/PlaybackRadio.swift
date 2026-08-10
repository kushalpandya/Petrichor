//
// PlaybackManager class extension
//
// This extension contains internet radio playback and the derived player state.
//

import Combine
import Foundation

extension PlaybackManager {
    var streamNowPlayingTitle: String? {
        if let icy = streamMetadata["StreamTitle"]?.trimmingCharacters(in: .whitespaces), !icy.isEmpty {
            return Self.icyDisplayTitle(icy)
        }
        // A finite remote file reports container tags in lowercase keys instead.
        guard let title = streamMetadata["title"], !title.isEmpty else { return nil }
        if let artist = streamMetadata["artist"], !artist.isEmpty {
            return "\(artist) - \(title)"
        }
        return title
    }

    /// Picks out the named fields rather than parsing the string as a whole
    private static let icyFieldPattern = try? NSRegularExpression(
        pattern: "([A-Za-z_][A-Za-z0-9_]*)=\"([^\"]*)\""
    )

    /// Parser for ICY titles which can contain a mix of plain text and key-value pairs
    static func icyDisplayTitle(_ raw: String) -> String {
        guard raw.contains("=\""), let pattern = icyFieldPattern else { return raw }

        var fields: [String: String] = [:]
        for match in pattern.matches(in: raw, range: NSRange(raw.startIndex..., in: raw)) {
            guard let key = Range(match.range(at: 1), in: raw),
                  let value = Range(match.range(at: 2), in: raw) else { continue }
            // First occurrence wins: the trailing junk after `url=` can repeat a key.
            let name = String(raw[key]).lowercased()
            if fields[name] == nil {
                fields[name] = String(raw[value]).trimmingCharacters(in: .whitespaces)
            }
        }

        if let title = fields["title"], !title.isEmpty {
            guard let artist = fields["artist"], !artist.isEmpty else { return title }
            return "\(artist) - \(title)"
        }
        // Ad-break and station markers arrive as `text=`.
        if let text = fields["text"], !text.isEmpty { return text }

        return raw
    }

    /// Occupancy, not playback: gating UI on `isStreamActive` makes it flip on stop.
    var hasStation: Bool {
        currentStation != nil
    }

    var hasPlayableContent: Bool {
        currentTrack != nil || currentStation != nil
    }

    var isStreamActive: Bool {
        currentStation != nil && (isPlaying || isBuffering)
    }

    /// A stream is not a queue member, so the skips have nothing to act on.
    var isTransportDisabled: Bool {
        isStreamActive || currentTrack == nil
    }

    var playPauseActionTitle: String {
        // A stopped station's button restarts the stream, so the label follows the stream,
        // not the station.
        if hasStation { return isStreamActive ? String(localized: "Stop") : String(localized: "Play") }
        return isPlaying ? String(localized: "Pause") : String(localized: "Play")
    }

    func refreshStreamFormat() {
        let latest = currentStation != nil ? audioPlayer.currentStreamFormat : nil
        guard latest?.codec != streamFormat?.codec
            || latest?.bitrate != streamFormat?.bitrate
            || latest?.sampleRate != streamFormat?.sampleRate
            || latest?.channelCount != streamFormat?.channelCount else { return }
        streamFormat = latest
    }

    var nowPlayingSource: NowPlayingSource? {
        if let station = currentStation {
            return NowPlayingSource(
                id: station.artworkCacheID,
                title: station.name,
                subtitle: streamNowPlayingTitle ?? station.description ?? "",
                artworkData: station.artworkData
            )
        }
        guard let track = currentTrack else { return nil }
        return NowPlayingSource(
            id: track.id,
            title: track.title,
            subtitle: track.displayArtist,
            artworkData: track.artworkData
        )
    }

    /// The play queue is deliberately left intact: a stream is not a queue member.
    func playStation(_ station: RadioStation) {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { [weak self] in self?.playStation(station) }
            return
        }

        guard let url = station.playableURL else {
            Logger.error("Station '\(station.name)' has an unplayable stream URL")
            NotificationManager.shared.addMessage(.error, String(localized: "This station's stream address isn't valid"))
            return
        }

        beginSourceGeneration()

        // Forget the track session without touching playlistManager.currentQueue.
        currentTrack = nil
        currentFullTrack = nil
        currentEntryId = nil
        mirror = []
        unmirroredTracks = [:]
        injectedNext = nil
        pendingRestoreResume = nil
        pendingPlayOnRestore = false
        restoredPosition = 0
        currentTime = 0

        // The queue itself is kept, but nothing in it is playing any more: a positive
        // cursor would keep a row marked current and make Play Next and shuffle behave as
        // though local playback were still active.
        playlistManager.currentQueueIndex = -1

        currentStation = station
        streamMetadata = [:]
        streamFormat = nil
        stationListenSeconds = 0
        stationPlayCredited = false

        publishStationNowPlaying(station)
        audioPlayer.playStream(url: url)
        isPlaying = true
        startConnectWatchdog(for: station)
        Logger.info("Started radio station: \(station.name)")
    }

    /// Gives up on a stream that never finishes connecting.
    private func startConnectWatchdog(for station: RadioStation) {
        streamConnectWatchdog?.cancel()

        let work = DispatchWorkItem { [weak self] in
            guard let self, self.isBuffering, self.currentStation?.id == station.id else { return }
            Logger.warning("Stream '\(station.name)' never finished connecting; stopping")
            self.stopStation()
            NotificationManager.shared.addMessage(
                .warning,
                String(localized: "Couldn't connect to '\(station.name)'")
            )
        }
        streamConnectWatchdog = work
        DispatchQueue.main.asyncAfter(deadline: .now() + PlaybackManager.streamConnectTimeout, execute: work)
    }

    func cancelConnectWatchdog() {
        streamConnectWatchdog?.cancel()
        streamConnectWatchdog = nil
    }

    func observeStationEdits() {
        InternetRadioManager.shared.$stations
            .receive(on: DispatchQueue.main)
            .sink { [weak self] stations in
                self?.syncCurrentStation(with: stations)
            }
            .store(in: &radioObservers)
    }

    /// Title left nil so the stream's live ICY line drives it: consumer fields win.
    func publishStationNowPlaying(_ station: RadioStation) {
        audioPlayer.setNowPlayingMetadata(
            NowPlayingMetadata(
                title: nil,
                artist: station.name,
                albumTitle: station.description,
                artworkData: station.artworkData
            )
        )
    }

    /// `currentStation` is a value snapshot, so edits only surface through this.
    func syncCurrentStation(with stations: [RadioStation]) {
        guard let current = currentStation, let stationId = current.id else { return }

        // Absence is not deletion: a failed read also yields an empty list.
        // Deletion comes through `stationWasDeleted`.
        guard var updated = stations.first(where: { $0.id == stationId }) else { return }

        // Launch first publishes lightweight station rows without artwork. Never let one
        // temporarily downgrade the fully restored player source while the full read runs.
        if updated.artworkData == nil, current.artworkData != nil {
            updated.artworkData = current.artworkData
        }
        guard updated != current else { return }

        let addressChanged = updated.streamURL != current.streamURL
        let wasStreaming = isStreamActive
        currentStation = updated
        publishStationNowPlaying(updated)

        // The engine is still on the old address, so what's audible no longer matches the
        // player. Stop rather than reconnect behind the user's back.
        if addressChanged, wasStreaming {
            Logger.info("Stream address changed while playing; stopping '\(updated.name)'")
            stopStation()
            NotificationManager.shared.addMessage(
                .info, String(localized: "Stream address changed. Press play to reconnect.")
            )
        }
    }

    func stationWasDeleted(_ stationId: Int64) {
        guard currentStation?.id == stationId else { return }

        audioPlayer.stop()
        audioPlayer.setNowPlayingMetadata(nil)
        clearStation()
        isPlaying = false
        currentTime = 0
        Logger.info("Station deleted while showing in the player; stopped and cleared it")
    }

    /// Launch-time restoration: shown but not connected.
    func restoreStation(_ station: RadioStation, colorSnapshot: ArtworkColorSnapshot?) {
        beginSourceGeneration()
        if let artworkData = station.artworkData, let colorSnapshot {
            ImageUtils.seedDominantColors(
                colorSnapshot.nsColors,
                id: station.artworkCacheID,
                imageData: artworkData
            )
        }
        currentStation = station
        streamMetadata = [:]
        streamFormat = nil
        isBuffering = false
        isPlaying = false
        currentTime = 0
        stationListenSeconds = 0
        stationPlayCredited = false
    }

    /// Streams stop rather than pause: Crescendo disconnects a live stream on pause.
    func toggleStationPlayback() {
        guard let station = currentStation else { return }
        if isPlaying || isBuffering {
            stopStation()
        } else {
            playStation(station)
        }
    }

    /// Keeps the station in the player, so Play restarts the same stream.
    func stopStation() {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { [weak self] in self?.stopStation() }
            return
        }

        cancelConnectWatchdog()
        audioPlayer.stop()
        isBuffering = false
        stationListenSeconds = 0
        stationPlayCredited = false
        currentTime = 0
        isPlaying = false
        Logger.info("Radio playback stopped")
    }

    /// Only clears our own state; callers quieten the engine themselves.
    func clearStation() {
        guard currentStation != nil else { return }
        beginSourceGeneration()
        cancelConnectWatchdog()
        currentStation = nil
        streamMetadata = [:]
        streamFormat = nil
        isBuffering = false
        stationListenSeconds = 0
        stationPlayCredited = false
    }

    func accumulateStationListen(_ elapsed: TimeInterval) {
        guard !stationPlayCredited, let station = currentStation else { return }
        stationListenSeconds += elapsed
        guard stationListenSeconds >= Self.stationPlayThreshold else { return }

        stationPlayCredited = true
        InternetRadioManager.shared.creditPlay(station)
        Logger.info("Credited a play for radio station: \(station.name)")
    }
}
