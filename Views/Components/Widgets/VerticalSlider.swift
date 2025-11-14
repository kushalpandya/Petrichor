import SwiftUI
import AppKit

struct VerticalSlider: View {
    @Binding var value: Float
    let label: String

    var body: some View {
        VStack(spacing: 5) {
            SliderRepresentable(value: $value)
                .frame(width: 22, height: 180)

            Text(label)
                .font(.caption)
                .fixedSize()
        }
        .help("\(label): \(Int(value)) dB")
    }
}

extension VerticalSlider {
    struct SliderRepresentable: NSViewRepresentable {
        @Binding var value: Float

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
        }

        func makeCoordinator() -> Coordinator {
            Coordinator(self)
        }

        class Coordinator: NSObject {
            var parent: SliderRepresentable

            init(_ parent: SliderRepresentable) {
                self.parent = parent
            }

            @objc
            func changed(_ sender: NSSlider) {
                parent.value = Float(sender.doubleValue)
            }
        }
    }
}
