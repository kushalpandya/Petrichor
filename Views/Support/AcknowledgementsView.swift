import SwiftUI

/// Contents of the dedicated "Acknowledgements" window, opened from the License
/// link in Settings > About and the Help menu. Renders the bundled
/// `Acknowledgements.md` as lightly-styled markdown.
///
/// SwiftUI's `Text` only renders *inline* markdown (bold/italic/code/links);
/// headings, lists, and dividers are not supported by a single `Text`. So we
/// parse the document into blocks ourselves (`MarkdownBlock`) and render each
/// block as its own view, letting `Text(.init(...))` handle the inline markup
/// within each line.
struct AcknowledgementsView: View {
    private let blocks: [MarkdownBlock] = MarkdownBlock.load(resource: "Acknowledgements")

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                    block.view
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(
            minWidth: 480,
            idealWidth: 640,
            maxWidth: 820,
            minHeight: 520,
            idealHeight: 720,
            maxHeight: 1000
        )
    }
}

/// A single renderable block parsed from a simple markdown document.
enum MarkdownBlock {
    case title(String)        // #
    case heading(String)      // ##
    case subheading(String)   // ###
    case minorHeading(String) // ####
    case bullet(String)       // -
    case paragraph(String)
    case divider              // ---
    case spacer               // blank line

    @ViewBuilder var view: some View {
        switch self {
        case .title(let text):
            Text(inline(text))
                .font(.title.bold())
        case .heading(let text):
            Text(inline(text))
                .font(.title2.bold())
                .padding(.top, 6)
        case .subheading(let text):
            Text(inline(text))
                .font(.headline)
                .padding(.top, 4)
        case .minorHeading(let text):
            Text(inline(text))
                .font(.subheadline.bold())
                .foregroundColor(.secondary)
                .padding(.top, 2)
        case .bullet(let text):
            HStack(alignment: .top, spacing: 8) {
                Text("•")
                Text(inline(text))
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .padding(.leading, 8)
        case .paragraph(let text):
            Text(inline(text))
                .fixedSize(horizontal: false, vertical: true)
        case .divider:
            Divider()
                .padding(.vertical, 6)
        case .spacer:
            Spacer(minLength: 2)
        }
    }

    /// Parses a string as inline markdown, falling back to the raw string if it
    /// can't be interpreted.
    private func inline(_ text: String) -> AttributedString {
        (try? AttributedString(markdown: text)) ?? AttributedString(text)
    }

    /// Loads a bundled markdown resource and parses it into blocks. Returns a
    /// single fallback paragraph if the resource is missing or unreadable.
    static func load(resource: String) -> [MarkdownBlock] {
        guard
            let url = Bundle.main.url(forResource: resource, withExtension: "md"),
            let contents = try? String(contentsOf: url, encoding: .utf8)
        else {
            return [.paragraph(String(localized: "Acknowledgements are unavailable."))]
        }
        return parse(contents)
    }

    /// Splits the document line-by-line into blocks. Paragraphs in the source are
    /// expected to be single (unwrapped) lines.
    static func parse(_ markdown: String) -> [MarkdownBlock] {
        markdown.components(separatedBy: .newlines).map { rawLine in
            let line = rawLine.trimmingCharacters(in: .whitespaces)

            if line.isEmpty {
                return .spacer
            } else if line == "---" {
                return .divider
            } else if let rest = line.dropPrefix("#### ") {
                return .minorHeading(rest)
            } else if let rest = line.dropPrefix("### ") {
                return .subheading(rest)
            } else if let rest = line.dropPrefix("## ") {
                return .heading(rest)
            } else if let rest = line.dropPrefix("# ") {
                return .title(rest)
            } else if let rest = line.dropPrefix("- ") {
                return .bullet(rest)
            } else {
                return .paragraph(line)
            }
        }
    }
}

private extension String {
    /// Returns the substring after `prefix`, or `nil` if the string doesn't start
    /// with it.
    func dropPrefix(_ prefix: String) -> String? {
        guard hasPrefix(prefix) else { return nil }
        return String(dropFirst(prefix.count))
    }
}

#Preview {
    AcknowledgementsView()
}
