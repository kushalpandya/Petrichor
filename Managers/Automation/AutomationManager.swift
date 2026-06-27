//
// AutomationManager class
//
// Process-wide command facade that exposes Petrichor's playback to system
// automation (App Intents / Shortcuts / Siri). The App Intents adapters call
// into this single surface instead of touching managers directly; it resolves
// the live managers off `AppCoordinator.shared` and runs every mutation on the
// main actor. Domain logic is split across `AM*` extension files (AMTransport,
// AMContent, AMQuery), mirroring the manager-pattern layout used elsewhere.
//
// Managers are owned by `AppCoordinator` (not global singletons), so an intent's
// `perform()` cannot read them from the SwiftUI environment. The accessors below
// reach the running coordinator instead; they return nil before the app has
// finished launching, in which case commands no-op gracefully.
//

import Foundation

@MainActor
final class AutomationManager {
    static let shared = AutomationManager()

    private init() {}

    var playback: PlaybackManager? { AppCoordinator.shared?.playbackManager }
    var playlist: PlaylistManager? { AppCoordinator.shared?.playlistManager }
    var library: LibraryManager? { AppCoordinator.shared?.libraryManager }
}
