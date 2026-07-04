import Foundation

enum AppInfo {
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

    /// Full OS version including the build number, e.g. "macOS 14.5.1 (23F79)".
    static var osVersion: String {
        let v = ProcessInfo.processInfo.operatingSystemVersion
        var version = "\(v.majorVersion).\(v.minorVersion)"
        if v.patchVersion > 0 { version += ".\(v.patchVersion)" }
        if let build = sysctlString("kern.osversion"), !build.isEmpty {
            return "macOS \(version) (\(build))"
        }
        return "macOS \(version)"
    }

    /// Reads a string-valued `sysctl` (e.g. "hw.model", "kern.osversion").
    static func sysctlString(_ name: String) -> String? {
        var size = 0
        guard sysctlbyname(name, nil, &size, nil, 0) == 0, size > 0 else { return nil }
        var buffer = [CChar](repeating: 0, count: size)
        guard sysctlbyname(name, &buffer, &size, nil, 0) == 0 else { return nil }
        return String(cString: buffer)
    }

    // MARK: - App Information
    
    static var name: String {
        Bundle.main.infoDictionary?["CFBundleName"] as? String ?? About.appTitle
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
        true
        #else
        false
        #endif
    }
}
