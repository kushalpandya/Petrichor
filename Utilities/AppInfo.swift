import Foundation

struct AppInfo {
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
    
    // MARK: - Build Information
    
    static var isDebugBuild: Bool {
        #if DEBUG
        return true
        #else
        return false
        #endif
    }
    
    static var copyright: String {
        Bundle.main.infoDictionary?["NSHumanReadableCopyright"] as? String ?? "© 2025"
    }
}
