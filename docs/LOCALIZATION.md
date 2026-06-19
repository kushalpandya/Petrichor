# Localization

Petrichor uses Apple's **String Catalog** (`Resources/Localizable.xcstrings`) for
localization. The app ships in English and automatically follows the user's macOS
system language when a matching localization is available, falling back to English
otherwise. Adding a new language requires **no Swift code changes**.

## Adding a translation

1. Open `Petrichor.xcodeproj` in Xcode and select
   `Resources/Localizable.xcstrings` in the navigator.
2. Click the **+** button at the bottom of the language list and pick your
   language. Xcode adds it to the project's known regions automatically.
3. Translate each string in the editor. The **State** column tracks progress:
   - _New / Needs review_ — not yet translated (shows a yellow/blank marker).
   - _Translated_ — green checkmark.
     You don't have to finish everything at once; untranslated strings fall back to
     English at runtime.
4. **Plurals:** some strings (e.g. `%lld songs`) have per-plural rows (`one`,
   `other`, and more depending on the language). Fill in each plural form your
   language needs — Xcode shows the categories that apply.
5. **Don't translate** brand names and proper nouns (e.g. `Last.fm`,
   `MusicBrainz`, `Petrichor`). Right-click such a string and choose
   _Mark as "Don't Translate"_ if it isn't already.
6. Build and run with your language selected (see below) to sanity-check layout
   and truncation, then open a pull request.

> Tip: most user-facing strings are SwiftUI `Text("…")` literals that Xcode
> extracts into the catalog automatically the first time you build after editing
> source. If a newly added English string isn't in the catalog yet, build the app
> in Xcode once and it will appear.

## Testing a locale without changing your Mac's language

You do **not** need to switch your system language. In Xcode:

**Product > Scheme > Edit Scheme... > Run > Options**

- **App Language** — pick a real language, or one of the built-in pseudolanguages:
  - _Accented Pseudolanguage_ — accents every localized string (`Pláy`), making it
    easy to spot any string that was missed (it stays plain English).
  - _Double-Length Pseudolanguage_ — doubles string length to reveal truncation
    and layout problems.
  - _Right-to-Left Pseudolanguage_ — mirrors the UI for RTL checking.
- **App Region** — override the formatting region (dates, numbers).

Equivalent launch arguments (Run > Arguments) for quick toggling:

```
-AppleLanguages "(fr)"
-AppleLocale "fr_FR"
-NSShowNonLocalizedStrings YES   # logs strings with no localization
-NSDoubleLocalizedStrings YES    # doubles lengths at runtime
```

In SwiftUI previews you can also set `.environment(\.locale, Locale(identifier: "fr"))`.

## For contributors

- All user-facing strings must be localizable:
  - SwiftUI: a string **literal** in `Text`, `Button`, `Label`,
    `.navigationTitle`, `.help`, alerts, etc. is already a `LocalizedStringKey`
    and is extracted automatically.
  - **Gotcha:** `Text(flag ? "A" : "B")` and other _ternaries of literals_ resolve
    to the verbatim `String` overload and are **not** localized. Use a ternary of
    `Text(...)` values, or wrap each branch in `String(localized:)`.
  - Plain `String` values (AppKit `NSMenuItem`/`NSAlert`/`NSOpenPanel` titles,
    toast messages passed to `NotificationManager`, computed subtitles) must be
    wrapped in `String(localized:)`.
  - Don't localize dynamic data (track/artist/album names, file paths) — pass the
    `String` variable through verbatim.
- **Pluralization:** never build plurals with inline `count == 1 ? … : …`. Write a
  single interpolated string (`"\(count) songs"`) and add the plural variations in
  the catalog. For counts embedded in longer sentences with another argument,
  prefer explicit singular/plural `String(localized:)` branches.
- Locale-aware formatters are preferred over hand-rolled strings:
  `RelativeDateTimeFormatter` for "x minutes ago", `ListFormatter` for grammatical
  lists, `ByteCountFormatter` for sizes.
