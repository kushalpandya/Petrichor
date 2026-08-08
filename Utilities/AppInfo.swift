import Foundation

enum AppInfo {
    // The contact URL stays the repository: it's where a service operator who
    // takes issue with our requests would come to reach us.
    static let userAgent = "\(About.appTitle)/\(AppInfo.version) (\(About.appRepository))"

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

    /// The app's registered URL scheme from Info.plist
    /// "petrichor-debug" for dev build and "petrichor" for prod
    static var urlScheme: String {
        let types = Bundle.main.infoDictionary?["CFBundleURLTypes"] as? [[String: Any]]
        let scheme = types?
            .compactMap { ($0["CFBundleURLSchemes"] as? [String])?.first }
            .first
        return scheme ?? "petrichor"
    }
    
    // MARK: - Networking

    /// Refuses https->http redirects for everything sent through it. ATS used to guarantee
    /// that until the radio feature turned it off process-wide, and credential-bearing
    /// requests (Last.fm session key, TMDB bearer) go this way. A per-task delegate
    /// overrides it where a caller needs something stricter or different.
    static let urlSession: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 15
        config.timeoutIntervalForResource = 30
        return URLSession(configuration: config, delegate: RedirectPolicy.httpsOnly, delegateQueue: nil)
    }()

    /// Applies a destination test to each redirect hop. A per-task delegate, so the shared
    /// session keeps its behaviour for every request that doesn't ask for this.
    final class RedirectPolicy: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
        /// Refuses any hop that would leave TLS.
        static let httpsOnly = RedirectPolicy { $0.scheme?.lowercased() == "https" }

        /// Refuses every redirect. For a request whose body is private, staying on TLS is
        /// not enough: a 307/308 to another https origin would replay it, headers included.
        static let none = RedirectPolicy { _ in false }

        private let allows: @Sendable (URL) -> Bool

        init(allows: @escaping @Sendable (URL) -> Bool) {
            self.allows = allows
        }

        func urlSession(
            _ session: URLSession,
            task: URLSessionTask,
            willPerformHTTPRedirection response: HTTPURLResponse,
            newRequest request: URLRequest,
            completionHandler: @escaping (URLRequest?) -> Void
        ) {
            guard let url = request.url, allows(url) else {
                completionHandler(nil)
                return
            }
            completionHandler(request)
        }
    }

    // MARK: - Build Information
    
    static var isDebugBuild: Bool {
        #if DEBUG
        true
        #else
        false
        #endif
    }

    /// Whether this is the real shipping app, as opposed to a dev build running
    /// under `org.Petrichor.debug`. Unlike `isDebugBuild` this isn't compile-time:
    /// `build-installer.sh --dev` produces an optimized Release build that still
    /// uses the dev bundle identifier, and therefore its own library data.
    static var isProductionBuild: Bool {
        bundleIdentifier == About.bundleIdentifier
    }
}
