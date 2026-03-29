import Foundation

struct AppInfo {
    static let userAgent = "\(About.appTitle)/\(AppInfo.version) (\(About.appWebsite))"

    // MARK: - Version Information

    static var version: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? About.appVersion
    }
    
    static var build: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? About.appBuild
    }
    
    static var versionWithBuild: String {
        if version == build {
            return version
        } else {
            return "\(version) (\(build))"
        }
    }
    
    // MARK: - App Information
    
    static var name: String {
        Bundle.main.infoDictionary?["CFBundleName"] as? String ?? About.appTitle
    }
    
    static var displayName: String {
        Bundle.main.infoDictionary?["CFBundleDisplayName"] as? String ?? name
    }
    
    static var bundleIdentifier: String {
        Bundle.main.bundleIdentifier ?? About.bundleIdentifier
    }
    
    // MARK: - Networking

    static let urlSession: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 15
        config.timeoutIntervalForResource = 30
        return URLSession(configuration: config)
    }()

    // MARK: - Build Information
    
    static var isDebugBuild: Bool {
        #if DEBUG
        return true
        #else
        return false
        #endif
    }
}
