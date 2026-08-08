//
// PlayPauseIcon
//
// Shared play/pause glyph with a cross-fade + rotation transition between the
// two states. Used by both the main PlayerView and the mini player controls.
//

import SwiftUI

struct PlayPauseIcon: View {
    let isPlaying: Bool
    var size: CGFloat = 20
    /// Radio streams stop rather than pause, so the "playing" glyph becomes a stop square.
    var stopInsteadOfPause: Bool = false

    var body: some View {
        ZStack {
            Image(systemName: Icons.playFill)
                .font(.system(size: size, weight: .medium))
                .foregroundColor(.white)
                .opacity(isPlaying ? 0 : 1)
                .scaleEffect(isPlaying ? 0.8 : 1)
                .rotationEffect(.degrees(isPlaying ? -90 : 0))

            Image(systemName: stopInsteadOfPause ? Icons.stopFill : Icons.pauseFill)
                .font(.system(size: size, weight: .medium))
                .foregroundColor(.white)
                .opacity(isPlaying ? 1 : 0)
                .scaleEffect(isPlaying ? 1 : 0.8)
                .rotationEffect(.degrees(isPlaying ? 0 : 90))
        }
        .animation(.easeInOut(duration: 0.2), value: isPlaying)
    }
}
