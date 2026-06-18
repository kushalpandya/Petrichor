//
// MediaBackend
//
// The single source of truth for which audio engine the app uses
// (SFBAudioEngine or Crescendo). It only reports the selected engine;
// it does not build or route anything. Each seam (the PlaybackEngine facade and
// the MetadataEngine facade) reads `current` and picks its own backend, so
// removing SFBAudioEngine later is a change to those facades plus this enum.
//
// Switching engines is an in-process swap driven from Settings (PlaybackEngine
// rebuilds its backend), so `current` is read at each seam's (re)build point
// rather than cached.
//

import Foundation

enum MediaBackend {
    case sfb
    case crescendo

    /// UserDefaults key for the user-facing toggle.
    static let userDefaultsKey = "useModernPlaybackEngine"

    /// The backend selected for this session. The toggle default is registered
    /// `true` at app init, so absent an explicit user choice the app runs on
    /// Crescendo; flipping the toggle off selects SFBAudioEngine.
    static var current: MediaBackend {
        UserDefaults.standard.bool(forKey: userDefaultsKey) ? .crescendo : .sfb
    }
}
