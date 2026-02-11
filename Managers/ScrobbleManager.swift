import Foundation
import CryptoKit

class ScrobbleManager: ObservableObject {
    // MARK: - Constants
    
    private enum LastFM {
        // swiftlint:disable:next space_after_comment
        static let apiBaseURL = "https://ws.audioscrobbler.com/2.0/"
        // swiftlint:disable:next space_after_comment
        static let authURL = "https://www.last.fm/api/auth/"
        static let minimumTrackDuration: Double = 30
        static let scrobbleThresholdPercentage: Double = 0.5
        // 4 minutes
        static let scrobbleThresholdSeconds: Double = 240
    }
    
    // MARK: - Properties
    
    private var apiKey: String? {
        Bundle.main.object(forInfoDictionaryKey: "LASTFM_API_KEY") as? String
    }
    
    private var sharedSecret: String? {
        Bundle.main.object(forInfoDictionaryKey: "LASTFM_SHARED_SECRET") as? String
    }
    
    private var sessionKey: String? {
        KeychainManager.retrieve(key: KeychainManager.Keys.lastfmSessionKey)
    }
    
    private var isConnected: Bool {
        sessionKey != nil
    }
    
    private var isScrobblingEnabled: Bool {
        UserDefaults.standard.bool(forKey: "scrobblingEnabled")
    }
    
    private var isLoveSyncEnabled: Bool {
        UserDefaults.standard.bool(forKey: "loveSyncEnabled")
    }
    
    // MARK: - Initialization
    
    init() {
        if UserDefaults.standard.object(forKey: "scrobblingEnabled") == nil {
            UserDefaults.standard.set(true, forKey: "scrobblingEnabled")
        }
        if UserDefaults.standard.object(forKey: "loveSyncEnabled") == nil {
            UserDefaults.standard.set(true, forKey: "loveSyncEnabled")
        }
        
        // Observe favorite status changes
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleFavoriteStatusChanged(_:)),
            name: .trackFavoriteStatusChanged,
            object: nil
        )
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
    
    // MARK: - Public Methods
    
    /// Build the Last.fm authentication URL
    func authenticationURL() -> URL? {
        guard let apiKey = apiKey, !apiKey.isEmpty else {
            Logger.error("Last.fm API key not configured")
            NotificationManager.shared.addMessage(.error, "Last.fm API key not configured")
            return nil
        }
        
        // swiftlint:disable:next space_after_comment
        let callbackURL = "petrichor://lastfm-callback"
        // Build authorization URL with API key and callback
        let authURLString = "\(LastFM.authURL)?api_key=\(apiKey)&cb=\(callbackURL)"
        
        guard let authURL = URL(string: authURLString) else {
            Logger.error("Failed to create auth URL")
            return nil
        }
        
        return authURL
    }
    
    /// Called when a track starts playing - sends "Now Playing" to Last.fm
    func trackStarted(_ track: Track) {
        guard isConnected, isScrobblingEnabled else { return }
        guard track.duration >= LastFM.minimumTrackDuration else {
            Logger.info("Track too short to scrobble (\(track.duration)s)")
            return
        }
        
        Task {
            await sendNowPlaying(track)
        }
    }
    
    /// Scrobble track on playback completion if it meets duration threshold
    func trackFinished(_ track: Track) {
        guard isConnected, isScrobblingEnabled else { return }
        guard track.duration >= LastFM.minimumTrackDuration else {
            Logger.warning("Track too short to scrobble (\(track.duration)s is less than \(LastFM.minimumTrackDuration)s)")
            return
        }
        
        Task {
            await scrobble(track)
        }
    }
    
    /// Called when user favorites/unfavorites a track - syncs love status to Last.fm
    func trackLoveStatusChanged(_ track: Track, isLoved: Bool) {
        guard isConnected, isLoveSyncEnabled else { return }
        
        Task {
            await setLoveStatus(track, loved: isLoved)
        }
    }
    
    /// Handle OAuth callback from Last.fm
    func handleAuthCallback(_ url: URL) {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let token = components.queryItems?.first(where: { $0.name == "token" })?.value else {
            Logger.error("Auth callback missing token")
            NotificationManager.shared.addMessage(.error, "Last.fm authorization failed: missing token")
            return
        }
        
        Logger.info("Received token, exchanging for session key...")
        
        Task {
            await exchangeToken(token)
        }
    }

    // MARK: - Authentication

    private func exchangeToken(_ token: String) async {
        guard let apiKey = apiKey,
              let sharedSecret = sharedSecret else {
            Logger.error("API credentials not configured")
            await MainActor.run {
                NotificationManager.shared.addMessage(.error, "Last.fm API credentials not configured")
            }
            return
        }
        
        var params: [String: String] = [
            "method": "auth.getSession",
            "api_key": apiKey,
            "token": token
        ]
        
        params["api_sig"] = generateSignature(params: params, secret: sharedSecret)
        params["format"] = "json"
        
        guard var components = URLComponents(string: LastFM.apiBaseURL) else {
            Logger.error("Failed to create URL components")
            return
        }
        components.queryItems = params.map { URLQueryItem(name: $0.key, value: $0.value) }
        
        guard let url = components.url else {
            Logger.error("Failed to build session URL")
            return
        }
        
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            
            if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
               let session = json["session"] as? [String: Any],
               let sessionKey = session["key"] as? String,
               let username = session["name"] as? String {
                KeychainManager.save(key: KeychainManager.Keys.lastfmSessionKey, value: sessionKey)
                
                await MainActor.run {
                    UserDefaults.standard.set(username, forKey: "lastfmUsername")
                    NotificationManager.shared.addMessage(.info, "Connected to Last.fm as \(username)")
                }
                
                Logger.info("Authenticated as \(username)")
                await fetchLastFMUserAvatar(username: username, apiKey: apiKey)
            } else if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let error = json["error"] as? Int,
                      let message = json["message"] as? String {
                Logger.error("API error \(error): \(message)")
                await MainActor.run {
                    NotificationManager.shared.addMessage(.error, "Last.fm error: \(message)")
                }
            }
        } catch {
            Logger.error("Session request failed - \(error.localizedDescription)")
            await MainActor.run {
                NotificationManager.shared.addMessage(.error, "Failed to connect to Last.fm")
            }
        }
    }
    
    private func fetchLastFMUserAvatar(username: String, apiKey: String) async {
        guard var components = URLComponents(string: LastFM.apiBaseURL) else { return }
        components.queryItems = [
            URLQueryItem(name: "method", value: "user.getInfo"),
            URLQueryItem(name: "user", value: username),
            URLQueryItem(name: "api_key", value: apiKey),
            URLQueryItem(name: "format", value: "json")
        ]
        
        guard let url = components.url else { return }
        
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            
            if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
               let user = json["user"] as? [String: Any],
               let images = user["image"] as? [[String: Any]] {
                // Get the largest image (last in array is usually "extralarge")
                if let largeImage = images.last,
                   let urlString = largeImage["#text"] as? String,
                   !urlString.isEmpty,
                   let avatarURL = URL(string: urlString) {
                    let (imageData, _) = try await URLSession.shared.data(from: avatarURL)
                    await MainActor.run {
                        UserDefaults.standard.set(imageData, forKey: "lastfmAvatarData")
                    }
                    Logger.info("Cached user avatar")
                }
            }
        } catch {
            Logger.error("Failed to fetch user avatar - \(error.localizedDescription)")
        }
    }
    
    // MARK: - Last.fm API Calls
    
    private func sendNowPlaying(_ track: Track) async {
        guard let apiKey = apiKey,
              let sharedSecret = sharedSecret,
              let sessionKey = sessionKey else { return }
        
        var params: [String: String] = [
            "method": "track.updateNowPlaying",
            "api_key": apiKey,
            "sk": sessionKey,
            "artist": track.artist,
            "track": track.title
        ]
        
        if track.album != "Unknown Album" {
            params["album"] = track.album
        }
        if let albumArtist = track.albumArtist {
            params["albumArtist"] = albumArtist
        }
        if let trackNumber = track.trackNumber {
            params["trackNumber"] = String(trackNumber)
        }
        if track.duration > 0 {
            params["duration"] = String(Int(track.duration))
        }
        
        params["api_sig"] = generateSignature(params: params, secret: sharedSecret)
        params["format"] = "json"
        
        do {
            let response = try await makePostRequest(params: params)
            if response["nowplaying"] != nil {
                Logger.info("ScrobbleManager: Now playing sent - \(track.artist) - \(track.title)")
            } else if let error = response["error"] as? Int,
                      let message = response["message"] as? String {
                Logger.error("ScrobbleManager: Now playing failed - Error \(error): \(message)")
            }
        } catch {
            Logger.error("Now playing request failed - \(error.localizedDescription)")
        }
    }
    
    private func scrobble(_ track: Track) async {
        guard let apiKey = apiKey,
              let sharedSecret = sharedSecret,
              let sessionKey = sessionKey else { return }
        
        let timestamp = String(Int(Date().timeIntervalSince1970))
        
        var params: [String: String] = [
            "method": "track.scrobble",
            "api_key": apiKey,
            "sk": sessionKey,
            "artist": track.artist,
            "track": track.title,
            "timestamp": timestamp
        ]
        
        // Add optional parameters
        if track.album != "Unknown Album" {
            params["album"] = track.album
        }
        if let albumArtist = track.albumArtist {
            params["albumArtist"] = albumArtist
        }
        if let trackNumber = track.trackNumber {
            params["trackNumber"] = String(trackNumber)
        }
        if track.duration > 0 {
            params["duration"] = String(Int(track.duration))
        }
        
        params["api_sig"] = generateSignature(params: params, secret: sharedSecret)
        params["format"] = "json"
        
        do {
            let response = try await makePostRequest(params: params)
            if let scrobbles = response["scrobbles"] as? [String: Any],
               let attr = scrobbles["@attr"] as? [String: Any],
               let accepted = attr["accepted"] as? Int,
               accepted > 0 {
                Logger.info("Scrobbled - \(track.artist) - \(track.title)")
            } else if let error = response["error"] as? Int,
                      let message = response["message"] as? String {
                Logger.error("Scrobble failed - Error \(error): \(message)")
            }
        } catch {
            Logger.error("Scrobble request failed - \(error.localizedDescription)")
        }
    }
    
    private func setLoveStatus(_ track: Track, loved: Bool) async {
        guard let apiKey = apiKey,
              let sharedSecret = sharedSecret,
              let sessionKey = sessionKey else { return }
        
        let method = loved ? "track.love" : "track.unlove"
        
        var params: [String: String] = [
            "method": method,
            "api_key": apiKey,
            "sk": sessionKey,
            "artist": track.artist,
            "track": track.title
        ]
        
        params["api_sig"] = generateSignature(params: params, secret: sharedSecret)
        params["format"] = "json"
        
        do {
            _ = try await makePostRequest(params: params)
            Logger.info("\(loved ? "Loved" : "Unloved") - \(track.artist) - \(track.title)")
        } catch {
            Logger.error("Love status update failed - \(error.localizedDescription)")
        }
    }
    
    // MARK: - Helpers
    
    private func generateSignature(params: [String: String], secret: String) -> String {
        let filteredParams = params.filter { $0.key != "format" }
        let sortedParams = filteredParams.sorted { $0.key < $1.key }
        let signatureBase = sortedParams.map { "\($0.key)\($0.value)" }.joined() + secret
        return md5Hash(signatureBase)
    }
    
    private func md5Hash(_ string: String) -> String {
        let data = Data(string.utf8)
        let digest = Insecure.MD5.hash(data: data)
        return digest.map { String(format: "%02hhx", $0) }.joined()
    }
    
    private func makePostRequest(params: [String: String]) async throws -> [String: Any] {
        guard let url = URL(string: LastFM.apiBaseURL) else {
            throw URLError(.badURL)
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        
        // Build the body with proper URL encoding
        var components = URLComponents()
        components.queryItems = params.map { URLQueryItem(name: $0.key, value: $0.value) }
        
        // Get the percent-encoded query string
        let bodyString = components.percentEncodedQuery ?? ""
        request.httpBody = bodyString.data(using: .utf8)
        
        let (data, _) = try await URLSession.shared.data(for: request)
        
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw URLError(.cannotParseResponse)
        }
        
        return json
    }
    
    // MARK: - Notification Handlers

    @objc
    private func handleFavoriteStatusChanged(_ notification: Notification) {
        guard let track = notification.userInfo?["track"] as? Track else { return }
        trackLoveStatusChanged(track, isLoved: track.isFavorite)
    }
}
