import SwiftUI

/// Neutral placeholder block for loading states, gently pulsing so a slow load reads as
/// "working" rather than "broken".
struct SkeletonBlock: View {
    var cornerRadius: CGFloat = 4

    @State private var isPulsing = false

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius)
            .fill(Color.gray.opacity(isPulsing ? 0.22 : 0.11))
            .animation(
                .easeInOut(duration: 0.9).repeatForever(autoreverses: true),
                value: isPulsing
            )
            .onAppear { isPulsing = true }
    }
}
