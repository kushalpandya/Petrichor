import Foundation

enum RepeatMode {
    case off
    case one
    case all

    /// Human-readable description of the current repeat mode, used for control tooltips.
    var tooltip: String {
        switch self {
        case .off: return String(localized: "Repeat: Off")
        case .one: return String(localized: "Repeat: Current Track")
        case .all: return String(localized: "Repeat: All")
        }
    }
}
