import SwiftUI

/// The supported-formats list, shown from the library empty state and from the
/// folder controls in Settings > Library.
///
/// Rows are derived from the playback engine at runtime rather than hard-coded,
/// so the list always describes the build that is actually running.
struct SupportedFormatsPopover: View {
    private let groups = AudioFormat.supportedFormatGroups
    private let extensionCount = AudioFormat.supportedExtensions.count

    // The list is padded from the inside rather than the ScrollView being inset,
    // so the scroller rides the popover's own edge instead of floating short of it.
    private static let horizontalInset: CGFloat = 14

    // Both widths come from measuring the widest row rather than estimating it:
    // "Dolby Digital Plus (E-AC-3)" needs 157pt and the six MPEG extensions need
    // 260pt, so nothing wraps once the inset and overlay scroller are covered.
    private static let nameColumnWidth: CGFloat = 162
    private static let popoverWidth: CGFloat = 480

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
                .padding(.horizontal, Self.horizontalInset)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(groups) { group in
                        formatRow(group)
                    }
                }
                .textSelection(.enabled)
                .padding(.horizontal, Self.horizontalInset)
                .padding(.vertical, 2)
            }
            .frame(height: 260)
        }
        .padding(.vertical, 14)
        .frame(width: Self.popoverWidth)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("Supported Formats")
                .font(.headline)

            Text("Petrichor imports and plays \(extensionCount) file types")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }

    private func formatRow(_ group: SupportedAudioFormatGroup) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(group.name)
                .font(.system(size: 12, weight: .medium))
                .frame(width: Self.nameColumnWidth, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)

            Text(group.fileExtensions.map { ".\($0)" }.joined(separator: "  "))
                .font(.system(size: 12, design: .monospaced))
                .foregroundColor(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: - Preview

#Preview {
    SupportedFormatsPopover()
}
