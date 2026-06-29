//
//  ArtistBioManager.swift
//  Petrichor
//
//  Handles fetching artist images (MusicBrainz/Wikidata, TMDB) and bios (Last.fm)
//  from online sources and storing them in the database.
//

import CryptoKit
import Foundation

class ArtistBioManager {
    // MARK: - Singleton

    static let shared = ArtistBioManager()

    /// Minimum image size in bytes to filter out placeholder/silhouette images
    private static let minimumImageSize = 15_000

    // MARK: - Constants

    private enum MusicBrainz {
        static let searchURL = "https://musicbrainz.org/ws/2/artist/"
        static let rateLimitDelay: TimeInterval = 1.1 // 1 req/sec with margin
    }

    private enum Wikidata {
        static let apiURL = "https://www.wikidata.org/w/api.php"
        static let rateLimitDelay: TimeInterval = 0.5
    }

    private enum TMDB {
        static let searchURL = "https://api.themoviedb.org/3/search/person"
        static let imageBaseURL = "https://image.tmdb.org/t/p/w500"
        static let rateLimitDelay: TimeInterval = 0.3 // ~40 req / 10s
    }

    private enum LastFM {
        static let apiBaseURL = "https://ws.audioscrobbler.com/2.0/"
        static let rateLimitDelay: TimeInterval = 0.25
    }

    private enum UserDefaultsKeys {
        static let artistInfoFetchEnabled = "artistInfoFetchEnabled"
    }

    // MARK: - Properties

    private var fetchTask: Task<Void, Never>?
    private var lastMusicBrainzRequest: Date?
    private var lastWikimediaRequest: Date?
    private var lastTMDBRequest: Date?
    private var lastLastFMRequest: Date?

    private var tmdbReadAccessToken: String? {
        Bundle.main.object(forInfoDictionaryKey: "TMDB_READ_ACCESS_TOKEN") as? String
    }

    private var lastfmApiKey: String? {
        Bundle.main.object(forInfoDictionaryKey: "LASTFM_API_KEY") as? String
    }

    var isArtistInfoFetchEnabled: Bool {
        UserDefaults.standard.bool(forKey: UserDefaultsKeys.artistInfoFetchEnabled)
    }

    // MARK: - Initialization

    private init() {}

    // MARK: - Types

    struct ImageResult {
        let imageData: Data
        let imageUrl: String
        let source: String
    }

    // MARK: - Public Methods

    func fetchMissingArtistImages(using libraryManager: LibraryManager) {
        fetchTask?.cancel()

        let databaseManager = libraryManager.databaseManager

        fetchTask = Task.detached(priority: .utility) { [weak self] in
            guard let self else { return }
            guard self.isArtistInfoFetchEnabled else {
                Logger.info("Artist info fetching is disabled")
                return
            }

            let artists = databaseManager.getArtistsNeedingImageOrBio()
            guard !artists.isEmpty else {
                Logger.info("No artists need fetching")
                return
            }

            Logger.info("Starting fetch for \(artists.count) artists")

            var pendingUpdates: [(name: String, artworkData: Data)] = []
            var lastUIUpdate = Date.distantPast
            let uiUpdateInterval: TimeInterval = 2

            // Stop a doomed run (offline / APIs down) instead of timing out on every
            // artist. The list is popular-first, so a long run yielding neither image
            // nor bio means "offline", not "no data exists".
            let maxConsecutiveFailures = 10
            var consecutiveFailures = 0
            var stoppedEarly = false

            // Full (image+bio) misses deferred until we can tell "offline" from "no
            // data": a success or finishing the whole list stamps them; any early exit
            // (offline breaker or cancel) drops them so a later refresh retries them.
            var deferredFullMisses: [Int64] = []
            func flushDeferredFailures() {
                for artistId in deferredFullMisses {
                    databaseManager.markArtistImageFetchFailed(artistId: artistId)
                    databaseManager.markArtistBioFetchFailed(artistId: artistId)
                }
                deferredFullMisses.removeAll()
            }

            for artist in artists {
                guard !Task.isCancelled, self.isArtistInfoFetchEnabled else {
                    Logger.info("Fetch stopped")
                    stoppedEarly = true
                    break
                }

                // Fetch image and bio, then write once
                Logger.info("Fetching info for '\(artist.name)' (image: \(!artist.hasImage), bio: \(!artist.hasBio))")
                let imageResult = artist.hasImage ? nil : await self.fetchArtistImage(name: artist.name)
                let bio = artist.hasBio ? nil : await self.fetchArtistBio(name: artist.name)

                // A cancel mid-fetch surfaces as nil results; bail before treating them
                // as misses so we don't stamp an interrupted artist as failed.
                if Task.isCancelled {
                    stoppedEarly = true
                    break
                }

                if let imageResult,
                   let compressed = ImageUtils.compressImage(from: imageResult.imageData, source: "ArtistBioManager/\(imageResult.source)") {
                    let source = imageResult.source.components(separatedBy: " – ").first ?? imageResult.source
                    databaseManager.updateArtistInfo(
                        artistId: artist.id,
                        imageData: compressed,
                        imageUrl: imageResult.imageUrl,
                        imageSource: source,
                        bio: bio,
                        bioSource: bio != nil ? "last.fm" : nil
                    )
                    pendingUpdates.append((name: artist.name, artworkData: compressed))
                } else if let bio {
                    databaseManager.updateArtistInfo(artistId: artist.id, bio: bio, bioSource: "last.fm")
                }

                // A miss = an attempted fetch that got an empty remote response.
                // (A downloaded image that fails local compression is not a miss; it
                // stays unstamped so it retries rather than being skipped for 7 days.)
                let imageMiss = !artist.hasImage && imageResult == nil
                let bioMiss = !artist.hasBio && bio == nil

                if imageResult != nil || bio != nil {
                    // Got data, so we're online: flush deferred full misses (genuine),
                    // stamp this artist's own miss, reset the breaker.
                    flushDeferredFailures()
                    if imageMiss { databaseManager.markArtistImageFetchFailed(artistId: artist.id) }
                    if bioMiss { databaseManager.markArtistBioFetchFailed(artistId: artist.id) }
                    consecutiveFailures = 0
                } else if imageMiss && bioMiss {
                    // Both attempted fields came back empty: an offline candidate.
                    // Defer the stamps and count toward the breaker.
                    deferredFullMisses.append(artist.id)
                    consecutiveFailures += 1
                    if consecutiveFailures >= maxConsecutiveFailures {
                        Logger.warning("Stopping artist fetch after \(maxConsecutiveFailures) consecutive failures (likely offline)")
                        stoppedEarly = true
                        break
                    }
                } else {
                    // Only one field was attempted and authoritatively returned nothing
                    // (e.g. no Last.fm bio exists, or no Last.fm key): a genuine miss,
                    // not evidence of offline. Stamp it; leave the breaker untouched.
                    if imageMiss { databaseManager.markArtistImageFetchFailed(artistId: artist.id) }
                    if bioMiss { databaseManager.markArtistBioFetchFailed(artistId: artist.id) }
                }

                // Flush pending UI updates every 2 seconds
                if !pendingUpdates.isEmpty && Date().timeIntervalSince(lastUIUpdate) >= uiUpdateInterval {
                    await self.flushUIUpdates(pendingUpdates, using: libraryManager)
                    pendingUpdates.removeAll()
                    lastUIUpdate = Date()
                }
            }

            // Stamp trailing full misses only if we finished the whole list; any early
            // exit (offline or cancel) leaves them for a later retry.
            if !stoppedEarly { flushDeferredFailures() }

            // Flush remaining updates
            if !pendingUpdates.isEmpty {
                await self.flushUIUpdates(pendingUpdates, using: libraryManager)
            }

            Logger.info("Finished fetch")
        }
    }

    /// Search MusicBrainz/Wikidata and TMDB for all available artist images (used by image picker sheet)
    func searchAllImages(for artistName: String) async -> [ImageResult] {
        async let mbResults = searchMusicBrainzImages(name: artistName)
        async let tmdbResults = searchTMDBImages(name: artistName)
        return await mbResults + tmdbResults
    }

    // MARK: - Private: Image Fetch

    private func fetchArtistImage(name: String) async -> ImageResult? {
        // Try MusicBrainz/Wikidata first (CC0, no cache restrictions)
        if let result = await searchMusicBrainzImages(name: name, limit: 1).first {
            return result
        }
        // Fall back to TMDB
        return await searchTMDBImages(name: name, limit: 1).first
    }

    // MARK: - MusicBrainz / Wikidata Search

    private func searchMusicBrainzImages(name: String, limit: Int = 6) async -> [ImageResult] {
        await waitForRateLimit(lastRequest: &lastMusicBrainzRequest, delay: MusicBrainz.rateLimitDelay)

        guard var components = URLComponents(string: MusicBrainz.searchURL) else { return [] }
        components.queryItems = [
            URLQueryItem(name: "query", value: "artist:\"\(name)\""),
            URLQueryItem(name: "fmt", value: "json"),
            URLQueryItem(name: "limit", value: String(limit))
        ]
        guard let url = components.url else { return [] }

        do {
            var request = URLRequest(url: url)
            request.setValue(AppInfo.userAgent, forHTTPHeaderField: "User-Agent")

            let (data, response) = try await AppInfo.urlSession.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200,
                  let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let artists = json["artists"] as? [[String: Any]] else {
                return []
            }

            var images: [ImageResult] = []
            for artist in artists.prefix(limit) {
                guard let mbid = artist["id"] as? String else { continue }

                // For auto-fetch, only accept close name matches
                if limit == 1, let resultName = artist["name"] as? String,
                   !isNameMatch(query: name, result: resultName) { continue }

                // Look up the artist's relationships to find Wikidata link
                if let imageResult = await resolveImageViaMusicBrainz(mbid: mbid, artistName: artist["name"] as? String, limit: limit) {
                    images.append(imageResult)
                }
            }
            return images
        } catch {
            if isCancellation(error) { return [] }
            Logger.error("MusicBrainz error for '\(name)': \(error.localizedDescription)")
            return []
        }
    }

    /// Fetch artist relationships from MusicBrainz to find Wikidata URL, then resolve image
    private func resolveImageViaMusicBrainz(mbid: String, artistName: String?, limit: Int) async -> ImageResult? {
        await waitForRateLimit(lastRequest: &lastMusicBrainzRequest, delay: MusicBrainz.rateLimitDelay)

        let lookupURLString = "\(MusicBrainz.searchURL)\(mbid)?inc=url-rels&fmt=json"
        guard let lookupURL = URL(string: lookupURLString) else { return nil }

        do {
            var request = URLRequest(url: lookupURL)
            request.setValue(AppInfo.userAgent, forHTTPHeaderField: "User-Agent")

            let (data, response) = try await AppInfo.urlSession.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200,
                  let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let relations = json["relations"] as? [[String: Any]] else {
                return nil
            }

            // Find Wikidata relationship
            for relation in relations {
                guard let type = relation["type"] as? String, type == "wikidata",
                      let urlInfo = relation["url"] as? [String: Any],
                      let resource = urlInfo["resource"] as? String else { continue }

                if let imageResult = await resolveWikidataImage(wikidataUrl: resource, artistName: artistName, limit: limit) {
                    return imageResult
                }
            }
            return nil
        } catch {
            if isCancellation(error) { return nil }
            Logger.error("MusicBrainz lookup error for MBID '\(mbid)': \(error.localizedDescription)")
            return nil
        }
    }

    /// Fetch P18 (image) property from Wikidata, then get a direct thumb URL from Commons API
    private func resolveWikidataImage(wikidataUrl: String, artistName: String?, limit: Int) async -> ImageResult? {
        // Extract QID from URL like "https://www.wikidata.org/wiki/Q2831"
        guard let qid = wikidataUrl.split(separator: "/").last.map(String.init) else { return nil }

        await waitForRateLimit(lastRequest: &lastWikimediaRequest, delay: Wikidata.rateLimitDelay)

        guard var components = URLComponents(string: Wikidata.apiURL) else { return nil }
        components.queryItems = [
            URLQueryItem(name: "action", value: "wbgetclaims"),
            URLQueryItem(name: "entity", value: qid),
            URLQueryItem(name: "property", value: "P18"),
            URLQueryItem(name: "format", value: "json")
        ]
        guard let url = components.url else { return nil }

        do {
            var request = URLRequest(url: url)
            request.setValue(AppInfo.userAgent, forHTTPHeaderField: "User-Agent")

            let (data, response) = try await AppInfo.urlSession.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200,
                  let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let claims = json["claims"] as? [String: Any],
                  let p18Claims = claims["P18"] as? [[String: Any]],
                  let firstClaim = p18Claims.first,
                  let mainsnak = firstClaim["mainsnak"] as? [String: Any],
                  let datavalue = mainsnak["datavalue"] as? [String: Any],
                  let filename = datavalue["value"] as? String else {
                return nil
            }

            // Construct Wikimedia Commons thumb URL directly from filename MD5
            let imageUrl = commonsThumbUrl(filename: filename, width: 500)

            if let imageData = await downloadImageData(from: imageUrl) {
                let label = limit == 1 ? "musicbrainz" : artistName.map { "musicbrainz – \($0)" } ?? "musicbrainz"
                return ImageResult(imageData: imageData, imageUrl: imageUrl, source: label)
            }
            return nil
        } catch {
            if isCancellation(error) { return nil }
            Logger.error("Wikidata error for '\(qid)': \(error.localizedDescription)")
            return nil
        }
    }

    /// Construct a direct Wikimedia Commons thumbnail URL from a filename.
    /// Uses the MD5-based path scheme: upload.wikimedia.org/wikipedia/commons/thumb/{a}/{ab}/{filename}/{width}px-{filename}
    private func commonsThumbUrl(filename: String, width: Int) -> String {
        let normalized = filename.replacingOccurrences(of: " ", with: "_")
        let md5 = md5Hash(normalized)
        let a = String(md5.prefix(1))
        let ab = String(md5.prefix(2))
        let encoded = normalized.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? normalized
        return "https://upload.wikimedia.org/wikipedia/commons/thumb/\(a)/\(ab)/\(encoded)/\(width)px-\(encoded)"
    }

    private func md5Hash(_ string: String) -> String {
        let digest = Insecure.MD5.hash(data: Data(string.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    // MARK: - TMDB Search

    private func searchTMDBImages(name: String, limit: Int = 6) async -> [ImageResult] {
        guard let token = tmdbReadAccessToken, !token.isEmpty else { return [] }

        if limit == 1 {
            await waitForRateLimit(lastRequest: &lastTMDBRequest, delay: TMDB.rateLimitDelay)
        }

        guard var components = URLComponents(string: TMDB.searchURL) else { return [] }
        components.queryItems = [URLQueryItem(name: "query", value: name)]
        guard let url = components.url else { return [] }

        do {
            var request = URLRequest(url: url)
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            request.setValue(AppInfo.userAgent, forHTTPHeaderField: "User-Agent")

            let (data, response) = try await AppInfo.urlSession.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200,
                  let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let results = json["results"] as? [[String: Any]] else {
                return []
            }

            var images: [ImageResult] = []
            for result in results.prefix(limit) {
                guard let profilePath = result["profile_path"] as? String else { continue }

                // For auto-fetch, only accept close name matches
                if limit == 1, let resultName = result["name"] as? String,
                   !isNameMatch(query: name, result: resultName) { continue }

                let imageUrlString = TMDB.imageBaseURL + profilePath

                if let imageData = await downloadImageData(from: imageUrlString) {
                    let label = limit == 1 ? "tmdb" : (result["name"] as? String).map { "tmdb – \($0)" } ?? "tmdb"
                    images.append(ImageResult(imageData: imageData, imageUrl: imageUrlString, source: label))
                }
            }
            return images
        } catch {
            if isCancellation(error) { return [] }
            Logger.error("TMDB error for '\(name)': \(error.localizedDescription)")
            return []
        }
    }

    // MARK: - Last.fm Bio

    private func fetchArtistBio(name: String) async -> String? {
        guard let apiKey = lastfmApiKey, !apiKey.isEmpty else { return nil }

        await waitForRateLimit(lastRequest: &lastLastFMRequest, delay: LastFM.rateLimitDelay)

        guard var components = URLComponents(string: LastFM.apiBaseURL) else { return nil }
        components.queryItems = [
            URLQueryItem(name: "method", value: "artist.getinfo"),
            URLQueryItem(name: "artist", value: name),
            URLQueryItem(name: "api_key", value: apiKey),
            URLQueryItem(name: "format", value: "json")
        ]

        guard let url = components.url else { return nil }

        do {
            var request = URLRequest(url: url)
            request.setValue(AppInfo.userAgent, forHTTPHeaderField: "User-Agent")

            let (data, response) = try await AppInfo.urlSession.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else {
                return nil
            }

            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let artist = json["artist"] as? [String: Any],
                  let bio = artist["bio"] as? [String: Any],
                  let content = bio["summary"] as? String else {
                return nil
            }

            // Last.fm appends a "Read more" link in HTML
            let cleaned = content
                .replacingOccurrences(of: "<a href=\".*?\">.*?</a>", with: "", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines)

            return cleaned.isEmpty ? nil : cleaned
        } catch {
            if isCancellation(error) { return nil }
            Logger.error("Last.fm bio error for '\(name)': \(error.localizedDescription)")
            return nil
        }
    }

    // MARK: - UI Updates

    private func flushUIUpdates(
        _ updates: [(name: String, artworkData: Data)],
        using libraryManager: LibraryManager
    ) async {
        await MainActor.run {
            for update in updates {
                libraryManager.updateArtistEntityArtwork(name: update.name, artworkData: update.artworkData)
            }
        }
    }

    // MARK: - Helpers

    /// A cancelled URLSession request throws `URLError.cancelled`, not `CancellationError`,
    /// so the fetch task being restarted/cancelled would otherwise log as an error.
    private func isCancellation(_ error: Error) -> Bool {
        if error is CancellationError { return true }
        if let urlError = error as? URLError, urlError.code == .cancelled { return true }
        return false
    }

    private func downloadImageData(from urlString: String) async -> Data? {
        guard let url = URL(string: urlString) else { return nil }
        guard let (data, response) = try? await AppInfo.urlSession.data(from: url),
              let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200,
              data.count >= Self.minimumImageSize else {
            return nil
        }
        return data
    }

    /// Check if the API result name is a close match to the search query.
    /// Accepts exact matches (case-insensitive) or when one name contains the other.
    private func isNameMatch(query: String, result: String) -> Bool {
        let q = query.lowercased()
        let r = result.lowercased()
        return q == r || q.contains(r) || r.contains(q)
    }

    // MARK: - Rate Limiting

    private func waitForRateLimit(lastRequest: inout Date?, delay: TimeInterval) async {
        if let last = lastRequest {
            let elapsed = Date().timeIntervalSince(last)
            let waitTime = delay - elapsed
            if waitTime > 0 {
                try? await Task.sleep(nanoseconds: UInt64(waitTime * 1_000_000_000))
            }
        }
        lastRequest = Date()
    }
}
