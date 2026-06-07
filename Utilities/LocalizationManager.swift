//
// LocalizationManager
//
// Manages the app's selected language and applies it immediately at runtime.
//
// Two mechanisms work together so that every user-facing string switches live,
// without relaunching the app:
//   1. `Bundle.setLanguage(_:)` redirects `String(localized:)` /
//      `NSLocalizedString` lookups to the chosen language bundle.
//   2. The `\.locale` environment value (see `locale`) makes SwiftUI `Text`
//      views re-resolve their localized strings for the chosen language.
//
// The selected language is persisted in UserDefaults and re-applied on launch.
//

import SwiftUI
import Combine

/// The languages the user can pick in Settings.
enum AppLanguage: String, CaseIterable, Identifiable {
    /// Follow the operating system's preferred language (default).
    case system
    case english = "en"
    case french = "fr"

    var id: String { rawValue }

    /// The `.lproj` language code, or `nil` when following the system.
    var languageCode: String? {
        switch self {
        case .system: return nil
        case .english: return "en"
        case .french: return "fr"
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

    /// UserDefaults key backing the selected language.
    static let storageKey = "appLanguage"

    /// The currently selected language. Changing it persists the choice and
    /// applies it immediately.
    @Published var currentLanguage: AppLanguage {
        didSet {
            guard oldValue != currentLanguage else { return }
            UserDefaults.standard.set(currentLanguage.rawValue, forKey: Self.storageKey)
            applyLanguage()
        }
    }

    private init() {
        let storedValue = UserDefaults.standard.string(forKey: Self.storageKey)
        currentLanguage = AppLanguage(rawValue: storedValue ?? "") ?? .system
        applyLanguage()
    }

    /// Locale to inject into the SwiftUI environment so `Text` views resolve to
    /// the selected language. Falls back to the system locale for `.system`.
    var locale: Locale {
        if let code = currentLanguage.languageCode {
            return Locale(identifier: code)
        }
        return Locale.autoupdatingCurrent
    }

    /// Redirects bundle-based localized lookups to the selected language.
    func applyLanguage() {
        Bundle.setLanguage(currentLanguage.languageCode)
    }
}
