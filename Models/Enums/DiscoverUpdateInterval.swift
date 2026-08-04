import Foundation

enum DiscoverUpdateInterval: String, CaseIterable, Codable {
    case daily
    case weekly
    case biweekly
    case monthly

    var displayName: String {
        switch self {
        case .daily: return String(localized: "Daily")
        case .weekly: return String(localized: "Every week")
        case .biweekly: return String(localized: "Every 2 weeks")
        case .monthly: return String(localized: "Every month")
        }
    }

    var timeInterval: TimeInterval {
        switch self {
        case .daily: return 86400 // 1 day
        case .weekly: return 604800 // 7 days
        case .biweekly: return 1209600 // 14 days
        case .monthly: return 2592000 // 30 days
        }
    }

    /// Parses either the current bare-case rawValue or the English display strings
    /// that used to be the rawValues. Persisting a display string was a localization
    /// hazard, so stored values are normalized on launch; this keeps existing
    /// preferences readable in the meantime.
    init?(persistedValue: String) {
        if let interval = DiscoverUpdateInterval(rawValue: persistedValue) {
            self = interval
            return
        }

        switch persistedValue {
        case "Daily": self = .daily
        case "Every week": self = .weekly
        case "Every 2 weeks": self = .biweekly
        case "Every month": self = .monthly
        default: return nil
        }
    }
}
