import SwiftUI

struct EqualizerView: View {
    @EnvironmentObject var playbackManager: PlaybackManager
    
    // MARK: - State

    @State private var isEnabled = false
    @State private var stereoWideningEnabled = false
    @State private var selectedPreset: EqualizerPreset = .flat
    @State private var isCustomMode = false
    @State private var customGains: [Float] = Array(repeating: 0.0, count: 10)
    @State private var preampGain: Float = 0.0

    // MARK: - Constants

    private let frequencies = EqualizerFrequency.allCases

    var body: some View {
        VStack(spacing: 20) {
            topControlsRow
            
            eqSlidersSection
                .disabled(!isEnabled)
                .opacity(isEnabled ? 1.0 : 0.5)
        }
        .padding(20)
        .frame(width: 500, height: 300)
        .onAppear {
            loadCurrentSettings()
        }
        .configureEqualizerWindow()
    }

    // MARK: - Top Controls Row

    private var topControlsRow: some View {
        HStack {
            Toggle("On", isOn: $isEnabled)
                .toggleStyle(.checkbox)
                .onChange(of: isEnabled) {
                    playbackManager.setEQEnabled(isEnabled)
                }
            
            Spacer()

            Toggle("Stereo Widening", isOn: $stereoWideningEnabled)
                .toggleStyle(.checkbox)
                .disabled(!isEnabled)
                .onChange(of: stereoWideningEnabled) {
                    playbackManager.setStereoWidening(
                        enabled: stereoWideningEnabled
                    )
                }

            presetPicker
                .disabled(!isEnabled)
        }
    }

    // MARK: - Preset Picker

    private var presetPicker: some View {
        Picker("", selection: Binding(
            get: { isCustomMode ? nil : selectedPreset },
            set: { newValue in
                if let preset = newValue {
                    isCustomMode = false
                    selectedPreset = preset
                    applyPreset(preset)
                } else {
                    isCustomMode = true
                    customGains = loadSavedCustomGains()
                    playbackManager.applyEQCustom(gains: customGains)
                }
            }
        )) {
            Text("Custom").tag(Optional<EqualizerPreset>.none)
            
            Divider()
            
            ForEach(EqualizerPreset.allCases, id: \.self) { preset in
                Text(preset.displayName).tag(Optional(preset))
            }
        }
        .pickerStyle(.menu)
        .labelsHidden()
        .frame(width: 140)
        .disabled(!isEnabled)
    }

    // MARK: - EQ Sliders Section

    private var eqSlidersSection: some View {
        HStack(alignment: .top, spacing: 16) {
            preampSlider
            
            VStack(spacing: 0) {
                Text("+12 dB")
                    .font(.caption)
                    .lineLimit(1)
                Spacer()
                Text("0 dB")
                    .font(.caption)
                    .lineLimit(1)
                Spacer()
                Text("-12 dB")
                    .font(.caption)
                    .lineLimit(1)
            }
            .padding(.top, 1)
            .padding(.bottom, 20)
            .fixedSize(horizontal: true, vertical: false)

            ForEach(Array(frequencies.enumerated()), id: \.offset) {
                index,
                frequency in
                bandSlider(index: index, frequency: frequency)
            }
        }
        .padding(.top, 8)
    }

    // MARK: - Preamp Slider

    private var preampSlider: some View {
        VerticalSlider(
            value: Binding(
                get: { preampGain },
                set: { newValue in
                    preampGain = newValue.rounded(.toNearestOrAwayFromZero)
                    playbackManager.setPreamp(newValue)
                }
            ),
            label: "Preamp"
        )
    }

    // MARK: - Band Slider

    private func bandSlider(index: Int, frequency: EqualizerFrequency) -> some View {
        VerticalSlider(
            value: Binding(
                get: { customGains[index] },
                set: { newValue in
                    customGains[index] = newValue.rounded(.toNearestOrAwayFromZero)
                    handleGainChange()
                }
            ),
            label: frequency.label
        )
    }

    // MARK: - Helper Methods
    
    private func loadSavedCustomGains() -> [Float] {
        if let gains = UserDefaults.standard.array(forKey: "customEQGains") as? [Float],
           gains.count == 10 {
            return gains
        }
        return Array(repeating: 0.0, count: 10)
    }

    private func loadCurrentSettings() {
        isEnabled = playbackManager.isEQEnabled()
        stereoWideningEnabled = playbackManager.isStereoWideningEnabled()
        preampGain = playbackManager.getPreamp()

        if let presetRawValue = UserDefaults.standard.string(forKey: "eqPreset") {
            if presetRawValue == "custom" {
                isCustomMode = true
                customGains = loadSavedCustomGains()
            } else if let preset = EqualizerPreset(rawValue: presetRawValue) {
                isCustomMode = false
                selectedPreset = preset
                customGains = preset.gains
            }
        } else {
            isCustomMode = false
            selectedPreset = .flat
            customGains = EqualizerPreset.flat.gains
        }
    }

    private func applyPreset(_ preset: EqualizerPreset) {
        withAnimation(.easeInOut(duration: 0.25)) {
            customGains = preset.gains
        }
        playbackManager.applyEQPreset(preset)
    }

    private func handleGainChange() {
        isCustomMode = true
        UserDefaults.standard.set(customGains, forKey: "customEQGains")
        playbackManager.applyEQCustom(gains: customGains)
    }
}

// MARK: - Vertical Slider Component

private struct VerticalSlider: View {
    @Binding var value: Float
    let label: String
    
    var body: some View {
        VStack(spacing: 8) {
            GeometryReader { geometry in
                ZStack(alignment: .topLeading) {
                    // Stepper Indicators
                    VStack(spacing: 0) {
                        ForEach(0..<12, id: \.self) { _ in
                            Rectangle()
                                .fill(Color.secondary.opacity(0.3))
                                .frame(width: 2, height: 2)
                                .frame(maxHeight: .infinity)
                        }
                    }
                    .frame(width: 1)
                    .offset(x: 18)
                    
                    Slider(value: $value, in: -12...12)
                        .rotationEffect(.degrees(-90.0), anchor: .topLeading)
                        .frame(width: geometry.size.height)
                        .controlSize(.small)
                        .offset(y: geometry.size.height)
                }
            }
            
            Text(label)
                .font(.caption)
                .fixedSize()
        }
        .help("\(label): \(String(format: "%.0f", value)) dB")
    }
}

extension View {
    func configureEqualizerWindow() -> some View {
        self.background(EqualizerWindowConfigurator())
    }
}

private struct EqualizerWindowConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        
        DispatchQueue.main.async {
            if let window = view.window {
                window.styleMask.insert(.utilityWindow)
                window.standardWindowButton(.miniaturizeButton)?.isEnabled = false
                window.isMovable = true
            }
        }
        
        return view
    }
    
    func updateNSView(_ nsView: NSView, context: Context) {}
}


#Preview {
    EqualizerView()
        .environmentObject({
            let libraryManager = LibraryManager()
            let playlistManager = PlaylistManager()
            return PlaybackManager(
                libraryManager: libraryManager,
                playlistManager: playlistManager
            )
        }())
        .frame(width: 500, height: 300)
}
