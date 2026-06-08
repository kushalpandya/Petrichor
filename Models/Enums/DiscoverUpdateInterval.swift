import Foundation

enum DiscoverUpdateInterval: String, CaseIterable, Codable {
    case daily = "Daily"
    case weekly = "Every week"
    case biweekly = "Every 2 weeks"
    case monthly = "Every month"
    
    var displayName: String {
        // Localize for display only; the rawValue is persisted (@AppStorage /
        // Codable) and must stay stable, so it is not changed.
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
}
