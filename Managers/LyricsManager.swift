//
//  LyricsManager.swift
//  Petrichor
//
//  Handles fetching lyrics from online sources (LRCLIB) and coordinating
//  with database storage for caching.
//

import Foundation

class LyricsManager {
    // MARK: - Singleton
    
    static let shared = LyricsManager()
    
    // MARK: - Constants
    
    private enum LRCLIB {
        static let baseURL = "https://lrclib.net/api"
        static let getEndpoint = "/get"
    }
    
    private enum UserDefaultsKeys {
        static let onlineLyricsEnabled = "onlineLyricsEnabled"
    }
    
    // MARK: - Properties
    
    private let urlSession: URLSession
    
    /// Whether online lyrics fetching is enabled (user preference)
    var isOnlineLyricsEnabled: Bool {
        UserDefaults.standard.bool(forKey: UserDefaultsKeys.onlineLyricsEnabled)
    }
    
    // MARK: - Initialization
    
    private init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 15
        config.timeoutIntervalForResource = 30
        self.urlSession = URLSession(configuration: config)
    }
    
    // MARK: - Public Methods
    
    /// Fetch lyrics for a track from online sources
    /// - Parameters:
    ///   - fullTrack: The full track to fetch lyrics for
    ///   - databaseManager: Database manager for storing fetched lyrics
    /// - Returns: Lyrics text if found, nil otherwise
    func fetchLyrics(for fullTrack: FullTrack, using databaseManager: DatabaseManager) async -> String? {
        guard isOnlineLyricsEnabled else {
            Logger.info("LyricsManager: Online lyrics fetching is disabled")
            return nil
        }
        
        // Skip tracks with unknown/missing metadata
        guard isValidForLyricsFetch(fullTrack) else {
            Logger.info("LyricsManager: Track metadata insufficient for lyrics search")
            return nil
        }
        
        Logger.info("LyricsManager: Fetching lyrics for '\(fullTrack.title)' by '\(fullTrack.artist)'")
        
        // Try LRCLIB API
        if let lyrics = await fetchFromLRCLIB(fullTrack: fullTrack) {
            // Store in database for future use
            await storeLyrics(lyrics, for: fullTrack, using: databaseManager)
            return lyrics
        }
        
        Logger.info("LyricsManager: No lyrics found online for '\(fullTrack.title)'")
        return nil
    }
    
    // MARK: - Private Methods
    
    /// Check if track has sufficient metadata for lyrics search
    private func isValidForLyricsFetch(_ fullTrack: FullTrack) -> Bool {
        let hasValidTitle = !fullTrack.title.isEmpty
        let hasValidArtist = !fullTrack.artist.isEmpty && fullTrack.artist != "Unknown Artist"
        
        return hasValidTitle && hasValidArtist
    }
    
    /// Fetch lyrics from LRCLIB API
    private func fetchFromLRCLIB(fullTrack: FullTrack) async -> String? {
        // Try with album first if available
        if !fullTrack.album.isEmpty && fullTrack.album != "Unknown Album" {
            if let lyrics = await requestLRCLIB(fullTrack: fullTrack, includeAlbum: true) {
                return lyrics
            }
            // Retry without album
            Logger.info("LyricsManager: Retrying without album name")
        }
        
        return await requestLRCLIB(fullTrack: fullTrack, includeAlbum: false)
    }
            
    /// Make a request to LRCLIB API
    private func requestLRCLIB(fullTrack: FullTrack, includeAlbum: Bool) async -> String? {
        guard var components = URLComponents(string: LRCLIB.baseURL + LRCLIB.getEndpoint) else {
            Logger.error("LyricsManager: Failed to create URL components")
            return nil
        }
        
        // Build query parameters
        var queryItems: [URLQueryItem] = [
            URLQueryItem(name: "track_name", value: fullTrack.title),
            URLQueryItem(name: "artist_name", value: fullTrack.artist)
        ]
        
        // Add album if requested and available
        if includeAlbum && !fullTrack.album.isEmpty && fullTrack.album != "Unknown Album" {
            queryItems.append(URLQueryItem(name: "album_name", value: fullTrack.album))
        }
        
        // Add duration if available (crucial for accurate matching)
        if fullTrack.duration > 0 {
            queryItems.append(URLQueryItem(name: "duration", value: String(Int(fullTrack.duration))))
        }
        
        components.queryItems = queryItems
        
        guard let url = components.url else {
            Logger.error("LyricsManager: Failed to build LRCLIB URL")
            return nil
        }
        
        do {
            var request = URLRequest(url: url)
            request.setValue(
                "\(About.appTitle)/\(AppInfo.version) (\(About.appWebsite))",
                forHTTPHeaderField: "User-Agent"
            )
            
            let (data, response) = try await urlSession.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                Logger.error("LyricsManager: Invalid response type")
                return nil
            }
            
            switch httpResponse.statusCode {
            case 200:
                return parseLRCLIBResponse(data)
            case 404:
                Logger.info("LyricsManager: No lyrics found on LRCLIB (includeAlbum: \(includeAlbum))")
                return nil
            default:
                Logger.error("LyricsManager: LRCLIB API returned status \(httpResponse.statusCode)")
                return nil
            }
        } catch {
            Logger.error("LyricsManager: Network error - \(error.localizedDescription)")
            return nil
        }
    }
    
    /// Parse LRCLIB API response
    private func parseLRCLIBResponse(_ data: Data) -> String? {
        do {
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                Logger.error("LyricsManager: Failed to parse LRCLIB response as JSON")
                return nil
            }
            
            // LRCLIB returns both synced (syncedLyrics) and plain lyrics (plainLyrics)
            // Prefer synced lyrics as they contain timestamps
            if let syncedLyrics = json["syncedLyrics"] as? String, !syncedLyrics.isEmpty {
                Logger.info("LyricsManager: Found synced lyrics from LRCLIB")
                return syncedLyrics
            }
            
            if let plainLyrics = json["plainLyrics"] as? String, !plainLyrics.isEmpty {
                Logger.info("LyricsManager: Found plain lyrics from LRCLIB")
                return plainLyrics
            }
            
            Logger.info("LyricsManager: LRCLIB response contained no lyrics")
            return nil
        } catch {
            Logger.error("LyricsManager: JSON parsing error - \(error.localizedDescription)")
            return nil
        }
    }
    
    /// Store fetched lyrics in the database
    private func storeLyrics(_ lyrics: String, for fullTrack: FullTrack, using databaseManager: DatabaseManager) async {
        guard fullTrack.trackId != nil else {
            Logger.error("LyricsManager: Cannot store lyrics - track has no database ID")
            return
        }
        
        do {
            try await databaseManager.updateTrackLyrics(for: fullTrack, lyrics: lyrics)
            Logger.info("LyricsManager: Stored lyrics in database for '\(fullTrack.title)'")
        } catch {
            Logger.error("LyricsManager: Failed to store lyrics - \(error.localizedDescription)")
        }
    }
}
