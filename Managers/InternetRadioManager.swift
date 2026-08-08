//
// InternetRadioManager class
//
// Owns the internet radio station list and the radio-browser starter-set download.
//

import Foundation
import Network

class InternetRadioManager: ObservableObject {
    static let shared = InternetRadioManager()

    @Published var stations: [RadioStation] = []
    @Published var isFetchingDefaults = false

    // Presented from `ContentView` so any tab can open it.
    @Published var showingStationEditor = false
    @Published var stationToEdit: RadioStation?

    /// Starter-set source. Overridable via `RADIO_BROWSER_ENDPOINT_URL` in
    /// `Secrets.xcconfig` (not a secret), so swapping directories needs no code change.
    private enum RadioBrowser {
        /// `all.api` is round-robin DNS over the mirrors, so no single host goes stale.
        static let defaultEndpoint = "https://all.api.radio-browser.info/json/stations/topclick/25?hidebroken=true"

        static var endpoint: URL? {
            let configured = (Bundle.main.object(forInfoDictionaryKey: "RADIO_BROWSER_ENDPOINT_URL") as? String)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !configured.isEmpty else { return URL(string: defaultEndpoint) }

            // https only: the directory decides which URLs the app will later stream, and
            // ATS is off process-wide, so nothing else would catch a plain-http endpoint.
            guard let url = URL(string: configured), url.scheme?.lowercased() == "https" else {
                Logger.warning("RADIO_BROWSER_ENDPOINT_URL must be an https URL, using the default directory")
                return URL(string: defaultEndpoint)
            }
            return url
        }
    }

    private static let artworkFetchWindow = 8
    private static let artworkPublishBatch = 5
    /// Generous for a favicon; the point is a ceiling, not a tight fit.
    private static let maxArtworkBytes = 5 * 1024 * 1024
    /// Ample for the station list, whose size follows a configurable station count.
    private static let maxDirectoryBytes = 16 * 1024 * 1024

    private var databaseManager: DatabaseManager? {
        AppCoordinator.shared?.libraryManager.databaseManager
    }

    private init() {}

    /// Crescendo has no validator; it routes only http/https to its streaming path.
    static func validate(streamURL: String) -> URL? {
        let trimmed = streamURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              url.host != nil else {
            return nil
        }
        return url
    }

    func showAddStation() {
        stationToEdit = nil
        showingStationEditor = true
    }

    func showEditStation(_ station: RadioStation) {
        stationToEdit = station
        showingStationEditor = true
    }

    // MARK: - Library

    /// Off the main thread: every row carries its artwork blob, and `dbQueue` is
    /// serialized, so a main-thread read blocks behind any in-flight write.
    func loadStations() {
        guard let databaseManager else { return }
        Task.detached(priority: .userInitiated) {
            let loaded = databaseManager.loadAllStations()
            await MainActor.run { self.stations = loaded }
        }
    }

    @discardableResult
    func save(_ station: RadioStation) async -> RadioStation? {
        guard let databaseManager else { return nil }
        do {
            let saved = try await databaseManager.saveStation(station)
            loadStations()
            return saved
        } catch {
            Logger.error("Failed to save radio station '\(station.name)': \(error)")
            NotificationManager.shared.addMessage(.error, String(localized: "Couldn't save the station"))
            return nil
        }
    }

    /// Writes only what the editor owns, so a play credited or a favicon backfilled while
    /// it was open survives the save. `artwork == nil` leaves the column untouched.
    func update(
        _ station: RadioStation,
        artwork: Data??
    ) async -> Bool {
        guard let databaseManager, let stationId = station.id else { return false }
        do {
            try await databaseManager.updateStationDetails(
                id: stationId,
                name: station.name,
                streamURL: station.streamURL,
                description: station.description,
                artwork: artwork
            )
            loadStations()
            return true
        } catch {
            Logger.error("Failed to update radio station '\(station.name)': \(error)")
            NotificationManager.shared.addMessage(.error, String(localized: "Couldn't save the station"))
            return false
        }
    }

    /// One reload for the batch: rows carry their artwork blobs, so a reload per station
    /// re-reads the whole table.
    func delete(_ stations: [RadioStation]) async {
        guard let databaseManager else { return }
        let ids = Set(stations.compactMap(\.id))
        guard !ids.isEmpty else { return }

        let deleted: Set<Int64>
        do {
            deleted = try await databaseManager.deleteStations(ids: ids)
        } catch {
            Logger.error("Failed to delete \(ids.count) radio station(s): \(error)")
            return
        }

        guard !deleted.isEmpty else { return }
        await MainActor.run {
            for stationId in deleted {
                AppCoordinator.shared?.playbackManager.stationWasDeleted(stationId)
            }
        }
        loadStations()
        // The cascade already emptied `playlist_stations`; this is the in-memory catch-up.
        await AppCoordinator.shared?.playlistManager.refreshAllStationCollectionCounts()
    }

    func creditPlay(_ station: RadioStation) {
        guard let databaseManager, let stationId = station.id else { return }
        Task {
            do {
                try await databaseManager.incrementStationPlayCount(id: stationId)
                loadStations()
            } catch {
                Logger.error("Failed to credit play for station '\(station.name)': \(error)")
            }
        }
    }

    // MARK: - radio-browser

    @discardableResult
    func downloadTopStations() async -> Int {
        guard let databaseManager else { return 0 }

        // The dedupe snapshot is per run: two concurrent runs would each insert the lot.
        guard await claimDownloadSlot() else { return 0 }
        defer { Task { @MainActor in self.isFetchingDefaults = false } }

        guard let payload = await fetchTopStationPayload() else { return 0 }

        let (knownUUIDs, knownURLs) = databaseManager.existingStationIdentities()
        var seenURLs = knownURLs

        let candidates = payload.compactMap { entry -> RadioStation? in
            guard let station = Self.makeStation(from: entry) else { return nil }
            if let uuid = station.stationUUID, knownUUIDs.contains(uuid) { return nil }
            guard seenURLs.insert(station.streamURL).inserted else { return nil }
            return station
        }

        // Store artwork-less first: waiting on every favicon keeps the empty state up.
        var saved: [RadioStation] = []
        for candidate in candidates {
            do {
                saved.append(try await databaseManager.saveStation(candidate))
            } catch {
                Logger.error("Failed to store downloaded station '\(candidate.name)': \(error)")
            }
        }
        loadStations()

        await backfillArtwork(for: saved)

        Logger.info("Downloaded \(saved.count) radio stations from radio-browser")
        return saved.count
    }

    /// Batched: each publish re-sorts the whole list in the views watching it.
    private func backfillArtwork(for stations: [RadioStation]) async {
        guard let databaseManager else { return }

        var pending: [Int64: Data] = [:]
        var faviconFailures = 0

        await withTaskGroup(of: (Int64, Data?, Bool).self) { group in
            var next = stations.makeIterator()
            var inFlight = 0

            func addTask(for station: RadioStation) -> Bool {
                guard let stationId = station.id else { return false }
                let faviconURL = station.faviconURL
                let name = station.name
                group.addTask {
                    let result = await Self.fetchArtwork(faviconURL: faviconURL, name: name)
                    return (stationId, result.artwork, result.faviconFailed)
                }
                return true
            }

            // The endpoint is configurable, so the station count isn't ours to bound.
            while inFlight < Self.artworkFetchWindow, let station = next.next() {
                if addTask(for: station) { inFlight += 1 }
            }

            for await (stationId, artwork, faviconFailed) in group {
                inFlight -= 1
                while inFlight < Self.artworkFetchWindow, let station = next.next() {
                    if addTask(for: station) { inFlight += 1 }
                }

                if faviconFailed { faviconFailures += 1 }

                guard let artwork else { continue }
                do {
                    guard try await databaseManager.updateStationArtwork(id: stationId, artwork: artwork) else {
                        continue
                    }
                    pending[stationId] = artwork
                    if pending.count >= Self.artworkPublishBatch {
                        await applyArtwork(pending)
                        pending.removeAll()
                    }
                } catch {
                    Logger.error("Failed to store artwork for station \(stationId): \(error)")
                }
            }
        }

        await applyArtwork(pending)

        // Info, not an error: a station without a usable favicon still gets artwork.
        if faviconFailures > 0 {
            Logger.info("Generated artwork for \(faviconFailures) of \(stations.count) stations: favicon unavailable")
        }
    }

    /// Patches artwork in place; re-reading the table per image would reload every blob.
    @MainActor
    private func applyArtwork(_ artwork: [Int64: Data]) {
        guard !artwork.isEmpty else { return }
        var updated = stations
        var changed = false
        let now = Date()

        for (stationId, data) in artwork {
            // Same condition the database write used: an edit between the write and this
            // batch would otherwise be undone in the published list only.
            guard let index = updated.firstIndex(where: { $0.id == stationId }),
                  updated[index].artworkData == nil else { continue }
            updated[index].artworkData = data
            // `artworkVersion` reads `dateModified`, and the row's was just stamped by the
            // write; without this the patched value still compares equal and nothing redraws.
            updated[index].dateModified = now
            changed = true
        }

        if changed { stations = updated }
    }

    @MainActor
    private func claimDownloadSlot() -> Bool {
        guard !isFetchingDefaults else { return false }
        isFetchingDefaults = true
        return true
    }

    private func fetchTopStationPayload() async -> [[String: Any]]? {
        guard let url = RadioBrowser.endpoint else {
            NotificationManager.shared.addMessage(.error, String(localized: "Couldn't reach the station directory"))
            return nil
        }

        let directoryFetch = await Self.fetch(url, maxBytes: Self.maxDirectoryBytes) {
            $0.scheme?.lowercased() == "https"
        }

        switch directoryFetch {
        case .success(let data):
            return (try? JSONSerialization.jsonObject(with: data) as? [[String: Any]]) ?? []
        case .failure(let failure):
            Logger.error("radio-browser request failed: \(failure.description)")
            NotificationManager.shared.addMessage(.error, String(localized: "Couldn't reach the station directory"))
            return nil
        }
    }

    private enum FetchFailure: Error {
        case status(Int)
        case transport(String)

        var description: String {
            switch self {
            case .status(let code): return "status \(code)"
            case .transport(let message): return message
            }
        }
    }

    /// radio-browser requires a descriptive User-Agent. Logging is the caller's: this serves
    /// both the directory, where a failure is an error, and favicons, where one is routine.
    ///
    /// `allows` gates the first request *and every redirect hop*, and the body is streamed
    /// so an oversized response is abandoned rather than buffered whole. Both matter
    /// because the URLs come from the directory, which is untrusted input.
    private static func fetch(
        _ url: URL,
        maxBytes: Int,
        allows: @escaping @Sendable (URL) -> Bool
    ) async -> Result<Data, FetchFailure> {
        guard allows(url) else { return .failure(.transport("blocked destination")) }

        var request = URLRequest(url: url)
        request.setValue(AppInfo.userAgent, forHTTPHeaderField: "User-Agent")

        do {
            let (stream, response) = try await AppInfo.urlSession.bytes(
                for: request,
                delegate: AppInfo.RedirectPolicy(allows: allows)
            )
            guard let http = response as? HTTPURLResponse else {
                stream.task.cancel()
                return .failure(.transport("no response"))
            }
            guard http.statusCode == 200 else {
                stream.task.cancel()
                return .failure(.status(http.statusCode))
            }
            guard http.expectedContentLength <= Int64(maxBytes) else {
                stream.task.cancel()
                return .failure(.transport("response too large"))
            }

            var data = Data()
            if http.expectedContentLength > 0 {
                data.reserveCapacity(Int(http.expectedContentLength))
            }
            for try await byte in stream {
                data.append(byte)
                if data.count > maxBytes {
                    stream.task.cancel()
                    return .failure(.transport("response too large"))
                }
            }
            return .success(data)
        } catch {
            return .failure(.transport(error.localizedDescription))
        }
    }

    private static func makeStation(from entry: [String: Any]) -> RadioStation? {
        let name = (entry["name"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        // `url_resolved` is the directory's followed-redirect URL, which is what plays;
        // `url` may still be a playlist file or a stale redirect.
        let rawURL = (entry["url_resolved"] as? String).flatMap { $0.isEmpty ? nil : $0 }
            ?? (entry["url"] as? String ?? "")

        // Stricter than the editor's validator: a hand-entered LAN stream is a deliberate
        // choice, a directory entry pointing inward is not. Redirects after this are the
        // engine's to police (Crescendo #22).
        guard !name.isEmpty,
              let resolved = validate(streamURL: rawURL),
              isPubliclyRoutable(resolved) else { return nil }

        var station = RadioStation(name: name, streamURL: resolved.absoluteString)
        station.stationUUID = entry["stationuuid"] as? String
        station.homepageURL = entry["homepage"] as? String
        station.faviconURL = (entry["favicon"] as? String).flatMap { $0.isEmpty ? nil : $0 }
        station.tags = entry["tags"] as? String
        station.country = entry["country"] as? String
        station.countryCode = entry["countrycode"] as? String
        station.language = entry["language"] as? String
        station.codec = entry["codec"] as? String
        station.bitrate = entry["bitrate"] as? Int
        station.votes = entry["votes"] as? Int
        // The directory has no description field; its tag list is the closest thing.
        station.description = station.tags.flatMap { tags in
            tags.isEmpty
                ? nil
                : tags.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.joined(separator: ", ")
        }
        return station
    }

    private static func fetchArtwork(faviconURL: String?, name: String) async -> (artwork: Data?, faviconFailed: Bool) {
        var downloaded: Data?
        var faviconFailed = false

        // The favicon field is user-submitted; same http(s) guard as the stream URL.
        if let faviconURL, let url = validate(streamURL: faviconURL) {
            if let data = await fetchFavicon(url), !data.isEmpty {
                downloaded = data
            } else {
                faviconFailed = true
            }
        }

        let artwork = await Task.detached(priority: .utility) { () -> Data? in
            if let downloaded, let compressed = ImageUtils.compressStationArtwork(from: downloaded) {
                return compressed
            }
            return ImageUtils.generateStationArtwork(name: name)
        }.value

        return (artwork, faviconFailed)
    }

    /// Prefers https: stations often publish an http favicon a TLS-capable host also serves.
    private static func fetchFavicon(_ url: URL) async -> Data? {
        let secure = httpsUpgraded(url)
        if case .success(let data) = await fetch(secure, maxBytes: maxArtworkBytes, allows: isPubliclyRoutable) {
            return data
        }
        guard secure != url else { return nil }
        if case .success(let data) = await fetch(url, maxBytes: maxArtworkBytes, allows: isPubliclyRoutable) {
            return data
        }
        return nil
    }

    /// Keeps a directory entry from aiming the app at a loopback or private-network address.
    /// Literals are classified from their bytes; a hostname is only screened for the obvious
    /// local names, so a *public* name resolving inward still gets through.
    private static let isPubliclyRoutable: @Sendable (URL) -> Bool = { url in
        guard let host = url.host?.lowercased(), !host.isEmpty else { return false }

        if let address = IPv4Address(host) { return isPublic(address) }
        if let address = IPv6Address(host) { return isPublic(address) }

        // Only digits and dots, yet not parseable above: an alternate spelling of an IPv4
        // literal (127.1, 0177.0.0.1, 2130706433) rather than a hostname. Same for hex.
        if host.allSatisfy({ $0.isNumber || $0 == "." }) { return false }
        if host.hasPrefix("0x") { return false }

        return host != "localhost" && !host.hasSuffix(".localhost") && !host.hasSuffix(".local")
    }

    private static func isPublic(_ address: IPv4Address) -> Bool {
        let bytes = [UInt8](address.rawValue)
        guard bytes.count == 4 else { return false }

        switch (bytes[0], bytes[1]) {
        case (0, _), (10, _), (127, _), (169, 254), (192, 168):
            return false
        case (172, 16...31):      // RFC 1918
            return false
        case (100, 64...127):     // RFC 6598 carrier-grade NAT
            return false
        case (198, 18...19):      // RFC 2544 benchmarking
            return false
        default:
            // 224.0.0.0 and up is multicast/reserved, never a host to fetch from.
            return bytes[0] < 224
        }
    }

    private static func isPublic(_ address: IPv6Address) -> Bool {
        let bytes = [UInt8](address.rawValue)
        guard bytes.count == 16 else { return false }

        // :: and ::1
        if bytes.dropLast().allSatisfy({ $0 == 0 }), bytes[15] <= 1 { return false }
        // fe80::/10 link-local
        if bytes[0] == 0xFE, bytes[1] & 0xC0 == 0x80 { return false }
        // fc00::/7 unique local
        if bytes[0] & 0xFE == 0xFC { return false }
        // ::ffff:a.b.c.d - judge the address it embeds
        if bytes.prefix(10).allSatisfy({ $0 == 0 }), bytes[10] == 0xFF, bytes[11] == 0xFF,
           let mapped = IPv4Address(Data(bytes[12...])) {
            return isPublic(mapped)
        }
        return true
    }

    private static func httpsUpgraded(_ url: URL) -> URL {
        guard url.scheme?.lowercased() == "http",
              var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return url }
        components.scheme = "https"
        return components.url ?? url
    }
}
