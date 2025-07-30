import Foundation

enum AutoScanInterval: String, CaseIterable, Codable {
    case every15Minutes
    case every30Minutes
    case every60Minutes
    case onlyOnLaunch
    case manually

    var displayName: String {
        switch self {
        case .every15Minutes:
            return "Every 15 minutes"
        case .every30Minutes:
            return "Every 30 minutes"
        case .every60Minutes:
            return "Every hour"
        case .onlyOnLaunch:
            return "Only on app launch"
        case .manually:
            return "Manually"
        }
    }

    var timeInterval: TimeInterval? {
        switch self {
        case .every15Minutes:
            return 15 * 60 // 15 minutes in seconds
        case .every30Minutes:
            return 30 * 60 // 30 minutes in seconds
        case .every60Minutes:
            return 60 * 60 // 1 hour in seconds
        case .onlyOnLaunch, .manually:
            return nil // No automatic scanning
        }
    }
}
