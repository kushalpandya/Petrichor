import SwiftUI

struct DetailHeaderControls<Trailing: View>: View {
    let isPinned: Bool
    let isPlaybackDisabled: Bool
    let showsPlaybackControls: Bool
    let onTogglePin: () -> Void
    let onPlay: () -> Void
    let onShuffle: () -> Void
    @ViewBuilder let trailing: () -> Trailing

    init(
        isPinned: Bool,
        isPlaybackDisabled: Bool,
        showsPlaybackControls: Bool = true,
        onTogglePin: @escaping () -> Void,
        onPlay: @escaping () -> Void,
        onShuffle: @escaping () -> Void,
        @ViewBuilder trailing: @escaping () -> Trailing
    ) {
        self.isPinned = isPinned
        self.isPlaybackDisabled = isPlaybackDisabled
        self.showsPlaybackControls = showsPlaybackControls
        self.onTogglePin = onTogglePin
        self.onPlay = onPlay
        self.onShuffle = onShuffle
        self.trailing = trailing
    }

    var body: some View {
        HStack(spacing: 10) {
            Button(action: onTogglePin) {
                Image(systemName: isPinned ? "pin.slash.fill" : "pin.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .frame(width: 27, height: 27)
            }
            .adaptiveCircularButtonStyle()
            .help(isPinned ? String(localized: "Remove from Home") : String(localized: "Pin to Home"))

            if showsPlaybackControls {
                controlButton(title: "Play", icon: Icons.playFill, action: onPlay)
                    .adaptiveButtonStyle(prominent: true)
                    .disabled(isPlaybackDisabled)

                controlButton(title: "Shuffle", icon: Icons.shuffleFill, action: onShuffle)
                    .adaptiveButtonStyle()
                    .disabled(isPlaybackDisabled)
            }

            trailing()
        }
    }

    private func controlButton(title: LocalizedStringKey, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 12))
                Text(title)
                    .font(.system(size: 13, weight: .medium))
            }
            .frame(width: 90)
            .padding(.vertical, 6)
        }
    }
}

extension DetailHeaderControls where Trailing == EmptyView {
    init(
        isPinned: Bool,
        isPlaybackDisabled: Bool,
        showsPlaybackControls: Bool = true,
        onTogglePin: @escaping () -> Void,
        onPlay: @escaping () -> Void,
        onShuffle: @escaping () -> Void
    ) {
        self.isPinned = isPinned
        self.isPlaybackDisabled = isPlaybackDisabled
        self.showsPlaybackControls = showsPlaybackControls
        self.onTogglePin = onTogglePin
        self.onPlay = onPlay
        self.onShuffle = onShuffle
        self.trailing = { EmptyView() }
    }
}
