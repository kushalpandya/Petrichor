import SwiftUI

struct ScanningAnimation: View {
    let size: CGFloat
    let lineWidth: CGFloat
    @State private var isVisible = false

    init(size: CGFloat = 80, lineWidth: CGFloat = 4) {
        self.size = size
        self.lineWidth = lineWidth
    }

    var body: some View {
        ZStack {
            // Background circle
            Circle()
                .stroke(Color.secondary.opacity(0.2), lineWidth: lineWidth)
                .frame(width: size, height: size)

            // Animated arc
            Circle()
                .trim(from: 0, to: 0.7)
                .stroke(
                    LinearGradient(
                        gradient: Gradient(colors: [
                            Color.accentColor,
                            Color.accentColor.opacity(0.5)
                        ]),
                        startPoint: .leading,
                        endPoint: .trailing
                    ),
                    style: StrokeStyle(
                        lineWidth: lineWidth,
                        lineCap: .round
                    )
                )
                .frame(width: size, height: size)
                .rotationEffect(.degrees(isVisible ? 360 : 0))
                .animation(
                    isVisible ? Animation.linear(duration: 1.5).repeatForever(autoreverses: false) : .default,
                    value: isVisible
                )

            Image(systemName: Icons.musicNote)
                .font(.system(size: size * 0.4, weight: .light))
                .foregroundColor(.accentColor)
                .scaleEffect(isVisible ? 1.1 : 0.9)
                .opacity(isVisible ? 1.0 : 0.7)
                .animation(
                    isVisible ? Animation.easeInOut(duration: 1.0).repeatForever(autoreverses: true) : .default,
                    value: isVisible
                )
        }
        .onAppear {
            isVisible = true
        }
        .onDisappear {
            isVisible = false
        }
    }
}

// MARK: - Preview

#Preview("Default Size") {
    ScanningAnimation()
        .padding()
        .background(Color.gray.opacity(0.1))
}

#Preview("Small Size") {
    ScanningAnimation(size: 40, lineWidth: 3)
        .padding()
        .background(Color.gray.opacity(0.1))
}

#Preview("Large Size") {
    ScanningAnimation(size: 120, lineWidth: 6)
        .padding()
        .background(Color.gray.opacity(0.1))
}
