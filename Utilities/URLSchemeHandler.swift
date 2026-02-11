import Foundation

enum URLSchemeHandler {
    static func handle(_ url: URL) {
        Logger.info("URLSchemeHandler: Received URL - \(url.absoluteString)")
        
        guard url.scheme == "petrichor" else { return }
        
        switch url.host {
        case "lastfm-callback":
            AppCoordinator.shared?.scrobbleManager.handleAuthCallback(url)
        default:
            Logger.warning("URLSchemeHandler: Unknown callback - \(url.host ?? "nil")")
        }
    }
}
