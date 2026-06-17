//
// MediaBackend
//
// The single source of truth for which audio engine the app runs this session
// (SFBAudioEngine today, Crescendo later). It only reports the selected engine;
// it does not build or route anything. Each seam (the PlaybackEngine facade and
// the MetadataEngine facade) reads `current` and picks its own backend, so
// removing SFBAudioEngine later is a change to those facades plus this enum.
//
// Switching engines requires an app relaunch (the toggle and relaunch UI arrive
// in a later phase), so reading this per call is safe - the value cannot change
// while the app is running.
//

import Foundation

enum MediaBackend {
    case sfb
    case crescendo

    /// UserDefaults key for the user-facing toggle.
    static let userDefaultsKey = "useModernPlaybackEngine"

    /// The backend selected for this session. The toggle default is registered
    /// at app init; when the key is absent this reads false, so the app stays on
    /// SFBAudioEngine. No facade reads the Crescendo branch into a real backend
    /// yet, so runtime playback and metadata are still SFB only.
    static var current: MediaBackend {
        UserDefaults.standard.bool(forKey: userDefaultsKey) ? .crescendo : .sfb
    }
}
