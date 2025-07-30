import SwiftUI

struct MarqueeText: View {
    let text: String
    let font: Font
    let color: Color

    @State private var textSize: CGSize = .zero
    @State private var containerWidth: CGFloat = 0

    private var shouldAnimate: Bool {
        textSize.width > containerWidth
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Text(text)
                    .font(font)
                    .foregroundColor(.clear)
                    .lineLimit(1)
                    .fixedSize()
                    .background(
                        GeometryReader { textGeometry in
                            Color.clear
                                .onAppear {
                                    textSize = textGeometry.size
                                    containerWidth = geometry.size.width
                                }
                                .onChange(of: text) { _, _ in
                                    textSize = textGeometry.size
                                }
                        }
                    )

                if shouldAnimate {
                    MarqueeAnimatedText(
                        text: text,
                        font: font,
                        color: color,
                        textWidth: textSize.width,
                        containerWidth: containerWidth
                    )
                } else {
                    Text(text)
                        .font(font)
                        .foregroundColor(color)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }
            .frame(width: geometry.size.width, alignment: .leading)
            .clipped()
            .onChange(of: geometry.size.width) { _, newWidth in
                containerWidth = newWidth
            }
        }
    }
}

private struct MarqueeAnimatedText: View {
    let text: String
    let font: Font
    let color: Color
    let textWidth: CGFloat
    let containerWidth: CGFloat

    @State private var offset: CGFloat = 0
    @State private var animationWorkItem: DispatchWorkItem?
    @State private var direction: AnimationDirection = .forward
    
    private enum AnimationDirection {
        case forward, backward
    }

    private var maxOffset: CGFloat {
        max(0, textWidth - containerWidth + 10)
    }
    
    private var animationDuration: Double {
        let baseSpeed = 15.0
        return Double(maxOffset) / baseSpeed
    }

    var body: some View {
        Text(text)
            .font(font)
            .foregroundColor(color)
            .lineLimit(1)
            .fixedSize()
            .offset(x: offset)
            .onAppear {
                startAnimation()
            }
            .onDisappear {
                stopAnimation()
            }
            .onChange(of: text) { _, _ in
                stopAnimation()
                offset = 0
                direction = .forward
                startAnimation()
            }
    }

    private func startAnimation() {
        animationWorkItem?.cancel()
        
        guard maxOffset > 0 else { return }
        
        animationWorkItem = DispatchWorkItem { [self] in
            animateBackAndForth()
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0, execute: animationWorkItem!)
    }
    
    private func animateBackAndForth() {
        let targetOffset = direction == .forward ? -maxOffset : 0
        let duration = direction == .forward ? animationDuration : animationDuration
        
        withAnimation(.linear(duration: duration)) {
            offset = targetOffset
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + duration + 0.5) {
            direction = direction == .forward ? .backward : .forward
            
            if animationWorkItem != nil {
                animateBackAndForth()
            }
        }
    }
    
    private func stopAnimation() {
        animationWorkItem?.cancel()
        animationWorkItem = nil
        withAnimation(.none) {
            offset = 0
        }
        direction = .forward
    }
}
