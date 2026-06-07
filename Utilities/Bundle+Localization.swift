//
// Bundle+Localization
//
// Enables switching the app's localization at runtime (without a relaunch) by
// redirecting `Bundle.main`'s localized-string lookups to a specific language
// bundle. This covers `String(localized:)` and `NSLocalizedString(...)`.
// SwiftUI `Text` views are handled separately through the `\.locale`
// environment value (see LocalizationManager).
//

import Foundation

private var bundleLanguageKey: UInt8 = 0

/// A `Bundle` subclass that redirects localized string lookups to an associated
/// language bundle when one is set.
private final class LanguageBundle: Bundle, @unchecked Sendable {
    override func localizedString(forKey key: String, value: String?, table tableName: String?) -> String {
        if let bundle = objc_getAssociatedObject(self, &bundleLanguageKey) as? Bundle {
            return bundle.localizedString(forKey: key, value: value, table: tableName)
        }
        return super.localizedString(forKey: key, value: value, table: tableName)
    }
}

extension Bundle {
    /// Overrides the language `Bundle.main` uses for localized string lookups.
    ///
    /// - Parameter languageCode: The `.lproj` language code (e.g. `"fr"`), or
    ///   `nil` to fall back to the system-preferred language.
    static func setLanguage(_ languageCode: String?) {
        // Promote Bundle.main to our subclass once so the override takes effect.
        // object_setClass is idempotent when the class is already correct.
        object_setClass(Bundle.main, LanguageBundle.self)

        let languageBundle: Bundle?
        if let languageCode,
           let path = Bundle.main.path(forResource: languageCode, ofType: "lproj"),
           let bundle = Bundle(path: path) {
            languageBundle = bundle
        } else {
            languageBundle = nil
        }

        objc_setAssociatedObject(
            Bundle.main,
            &bundleLanguageKey,
            languageBundle,
            .OBJC_ASSOCIATION_RETAIN_NONATOMIC
        )
    }
}
