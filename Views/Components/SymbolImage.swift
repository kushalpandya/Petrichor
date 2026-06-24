import SwiftUI

/// Renders an SF Symbol by name, transparently handling both system symbols and custom
/// symbols imported into the asset catalog (names prefixed with `custom.`). Use this
/// anywhere an icon string may be either kind. `Image(systemName:)` only resolves system
/// symbols and logs a "No symbol named ... found in system symbol set" error for custom ones.
struct SymbolImage: View {
    let name: String

    init(_ name: String) {
        self.name = name
    }

    var body: some View {
        if name.hasPrefix("custom.") {
            Image(name)
        } else {
            Image(systemName: name)
        }
    }
}
