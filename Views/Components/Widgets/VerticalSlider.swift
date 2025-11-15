import SwiftUI
import AppKit

struct VerticalSlider: View {
    @Binding var value: Float
    let label: String
    @State private var isDragging = false

    var body: some View {
        VStack(spacing: 5) {
            SliderRepresentable(value: $value, isDragging: $isDragging)
                .frame(width: 22, height: 180)
                .overlay(alignment: .top) {
                    if isDragging {
                        Text("\(Int(value)) dB")
                            .font(.caption)
                            .foregroundColor(.primary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(
                                        Color(nsColor: .windowBackgroundColor)
                                    )
                                    .shadow(
                                        color: .black.opacity(0.2),
                                        radius: 2
                                    )
                            )
                            .fixedSize()
                            .offset(y: calculateTooltipYOffset())
                            .transition(.opacity)
                            .animation(.easeInOut(duration: 0.1), value: value)
                            .allowsHitTesting(false)
                    }
                }

            Text(label)
                .font(.caption)
                .fixedSize()
        }
    }

    private func calculateTooltipYOffset() -> CGFloat {
        let normalizedValue = (value + 12) / 24
        return -30 + (180 * CGFloat(1 - normalizedValue))
    }
}

extension VerticalSlider {
    struct SliderRepresentable: NSViewRepresentable {
        @Binding var value: Float
        @Binding var isDragging: Bool

        func makeNSView(context: Context) -> NSSlider {
            let slider = NSSlider(
                value: Double(value),
                minValue: -12,
                maxValue: 12,
                target: context.coordinator,
                action: #selector(Coordinator.changed)
            )

            slider.isVertical = true
            slider.numberOfTickMarks = 13
            slider.tickMarkPosition = .leading
            slider.allowsTickMarkValuesOnly = false

            slider.trackFillColor = NSColor(Color.accentColor)
            slider.controlSize = .small
            slider.isContinuous = true

            return slider
        }

        func updateNSView(_ slider: NSSlider, context: Context) {
            let target = Double(value)

            // Animate if in an animation transaction
            if context.transaction.animation != nil {
                let duration: TimeInterval = 0.1

                NSAnimationContext.runAnimationGroup { ctx in
                    ctx.duration = duration
                    slider.animator().doubleValue = target
                }
            } else {
                slider.doubleValue = target
            }

            context.coordinator.isDraggingBinding = $isDragging
        }

        func makeCoordinator() -> Coordinator {
            Coordinator(self)
        }

        class Coordinator: NSObject {
            var parent: SliderRepresentable
            var isDraggingBinding: Binding<Bool>?

            init(_ parent: SliderRepresentable) {
                self.parent = parent
                super.init()
            }

            @objc
            func changed(_ sender: NSSlider) {
                parent.value = Float(sender.doubleValue)

                // Set dragging to true when value changes
                isDraggingBinding?.wrappedValue = true

                // Use a timer to detect when dragging stops
                NSObject.cancelPreviousPerformRequests(
                    withTarget: self,
                    selector: #selector(stopDragging),
                    object: nil
                )
                perform(#selector(stopDragging), with: nil, afterDelay: 0.15)
            }

            @objc
            private func stopDragging() {
                isDraggingBinding?.wrappedValue = false
            }
        }
    }
}
