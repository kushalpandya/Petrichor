import Foundation

/// Which tagged gain the engine applies when normalizing loudness. Mirrors the
/// engine's own mode; `off` is what the settings toggle switches to, so it is not
/// offered as a gain source.
public enum ReplayGainMode: String, CaseIterable, Codable {
    case off
    case track
    case album
    case auto

    /// The sources the picker offers. `off` is expressed by the toggle above,
    /// which is why the last real choice has to survive being switched off.
    static let selectableCases: [ReplayGainMode] = [.auto, .album, .track]

    var displayName: String {
        switch self {
        case .off:
            return String(localized: "Off")
        case .track:
            return String(localized: "Track")
        case .album:
            return String(localized: "Album")
        case .auto:
            return String(localized: "Automatic")
        }
    }
}
