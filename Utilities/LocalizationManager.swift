//
// LocalizationManager
//
// Manages the app's selected language. The language is NOT switched live: the
// running app stays in the language it launched with. Changing the selection in
// Settings only records the choice and surfaces a "restart required" prompt;
// restarting applies the selection (via `AppleLanguages`) so the app relaunches
// in the chosen language from the start.
//

import SwiftUI
import AppKit

/// The languages the user can pick in Settings.
enum AppLanguage: String, CaseIterable, Identifiable {
    /// Follow the operating system's preferred language (default).
    case system
    case english = "en"
    case french = "fr"

    var id: String { rawValue }

    /// The value to write to `AppleLanguages` so the app launches in this
    /// language, or `nil` to remove the override and follow the system.
    var appleLanguages: [String]? {
        switch self {
        case .system: return nil
        case .english: return ["en"]
        case .french: return ["fr"]
        }
    }

    /// Localized display name shown in the language picker.
    var displayNameKey: LocalizedStringKey {
        switch self {
        case .system: return "System"
        case .english: return "English"
        case .french: return "French"
        }
    }
}

final class LocalizationManager: ObservableObject {
    static let shared = LocalizationManager()

    /// The user's selected language.
    static let selectedKey = "appLanguage"
    /// The language that was actually applied (i.e. the one the app launched in).
    static let appliedKey = "appliedLanguage"

    /// The language the app launched in (the last *applied* language). Changing
    /// the selection to anything else requires a restart.
    let launchLanguage: AppLanguage

    /// The language the user has selected. Recording it does NOT change the
    /// running app's language — it only takes effect after a restart.
    @Published var selectedLanguage: AppLanguage {
        didSet {
            guard oldValue != selectedLanguage else { return }
            UserDefaults.standard.set(selectedLanguage.rawValue, forKey: Self.selectedKey)
        }
    }

    /// True when the selection differs from the language the app is running in,
    /// i.e. a restart is required for it to take effect.
    var needsRestart: Bool {
        selectedLanguage != launchLanguage
    }

    private init() {
        let selected = AppLanguage(rawValue: UserDefaults.standard.string(forKey: Self.selectedKey) ?? "") ?? .system
        // The applied language defaults to the selection (first launch keeps them
        // in sync); thereafter it only changes when the user restarts.
        let applied = AppLanguage(rawValue: UserDefaults.standard.string(forKey: Self.appliedKey) ?? "") ?? selected
        launchLanguage = applied
        selectedLanguage = selected
    }

    /// Apply the current selection and relaunch the app so it takes effect.
    func restart() {
        // Persist the applied language and the matching `AppleLanguages` override
        // so the next launch (this relaunch) starts in the selected language.
        UserDefaults.standard.set(selectedLanguage.rawValue, forKey: Self.appliedKey)
        if let codes = selectedLanguage.appleLanguages {
            UserDefaults.standard.set(codes, forKey: "AppleLanguages")
        } else {
            UserDefaults.standard.removeObject(forKey: "AppleLanguages")
        }

        let url = Bundle.main.bundleURL
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: url, configuration: configuration) { _, _ in
            DispatchQueue.main.async {
                NSApplication.shared.terminate(nil)
            }
        }
    }
}
