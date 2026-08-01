import SwiftUI
import Sparkle

struct GeneralTabView: View {
    @EnvironmentObject var libraryManager: LibraryManager
    @EnvironmentObject var playbackManager: PlaybackManager

    @State private var crossfadeEnabled = false
    @State private var crossfadeDuration: TimeInterval = 3.0
    @State private var replayGainEnabled = false
    @State private var replayGainMode: ReplayGainMode = .auto
    @State private var replayGainPreamp: Float = 0

    /// Leading inset used to nest the options that depend on the toggle above them.
    private let dependentIndent: CGFloat = 20

    /// Fixed label and value columns so the crossfade and preamp sliders start and
    /// end at the same place despite different labels and value formats. Sized off
    /// the widest of each ("Gain preamp" at 77pt, "-20 dB" at 48pt).
    private let sliderLabelWidth: CGFloat = 90
    private let sliderValueWidth: CGFloat = 54

    @AppStorage("startAtLogin")
    private var startAtLogin = false

    @AppStorage("closeToMenubar")
    private var closeToMenubar = true
    
    @AppStorage("hideDuplicateTracks")
    private var hideDuplicateTracks: Bool = true
    
    @AppStorage("automaticUpdatesEnabled")
    private var automaticUpdatesEnabled = true

    var body: some View {
        Form {
            Section("Behavior") {
                Toggle("Start at login", isOn: $startAtLogin)
                    .help("Starts app on login")
                Toggle("Keep running in menubar on close", isOn: $closeToMenubar)
                    .help("Keeps the app running in the menubar even after closing")
                Toggle("Hide duplicate songs", isOn: $hideDuplicateTracks)
                    .help("Shows only the highest quality version when multiple copies exist")
                    .onChange(of: hideDuplicateTracks) {
                        // Filter is applied at query time; invalidate the load-once caches
                        // and reload affected state so it takes effect without a relaunch.
                        Logger.info("Hide duplicate songs setting changed to \(hideDuplicateTracks), refreshing library")
                        UserDefaults.standard.synchronize()
                        libraryManager.reloadForDuplicateVisibilityChange()
                    }
                Toggle("Check for updates automatically", isOn: automaticUpdatesBinding)
                    // Dev builds don't run the updater, so leave the toggle visible but inert
                    .disabled(!AppInfo.isProductionBuild)
                    .help(
                        AppInfo.isProductionBuild
                            ? "Automatically download and install updates when available"
                            : "Updates aren't available in development builds"
                    )
                    .onChange(of: automaticUpdatesEnabled) { _, newValue in
                        if let appDelegate = NSApp.delegate as? AppDelegate,
                           let updater = appDelegate.updaterController?.updater {
                            updater.automaticallyChecksForUpdates = newValue
                        }
                    }
            }

            Section("Playback") {
                Toggle("Crossfade tracks", isOn: $crossfadeEnabled)
                    .help("Fades one track out as the next fades in")
                    .onChange(of: crossfadeEnabled) { _, newValue in
                        playbackManager.setCrossfadeEnabled(newValue)
                    }

                crossfadeDurationRow
                    .disabled(!crossfadeEnabled)
                    .padding(.leading, dependentIndent)

                Toggle("Normalize volume (ReplayGain)", isOn: $replayGainEnabled)
                    .help("Evens out loudness differences using the gain tagged in each file")
                    .onChange(of: replayGainEnabled) { _, newValue in
                        playbackManager.setReplayGainEnabled(newValue)
                    }

                replayGainSourceRow
                    .disabled(!replayGainEnabled)
                    .padding(.leading, dependentIndent)

                replayGainPreampRow
                    .disabled(!replayGainEnabled)
                    .padding(.leading, dependentIndent)
            }
        }
        .formStyle(.grouped)
        .scrollDisabled(true)
        .padding(5)
        .onAppear {
            crossfadeEnabled = playbackManager.isCrossfadeEnabled()

            let storedDuration = playbackManager.getCrossfadeDuration()
            crossfadeDuration = storedDuration.rounded()
            if crossfadeDuration != storedDuration {
                playbackManager.setCrossfadeDuration(crossfadeDuration)
            }

            replayGainEnabled = playbackManager.isReplayGainEnabled()
            replayGainMode = playbackManager.selectedReplayGainMode
            replayGainPreamp = playbackManager.getReplayGainPreamp()
        }
    }

    private var crossfadeDurationRow: some View {
        HStack(spacing: 10) {
            Text("Duration")
                .frame(width: sliderLabelWidth, alignment: .leading)

            Slider(
                value: $crossfadeDuration,
                in: playbackManager.crossfadeDurationRange,
                step: 1
            )
            .onChange(of: crossfadeDuration) { _, newValue in
                playbackManager.setCrossfadeDuration(newValue)
            }

            Text(crossfadeDurationLabel)
                .font(.system(.body, design: .monospaced))
                .frame(width: sliderValueWidth, alignment: .trailing)
                .foregroundColor(.secondary)
        }
        .help("Applies to the next track change")
    }

    private var crossfadeDurationLabel: String {
        String(format: "%.0fs", crossfadeDuration)
    }

    private var replayGainSourceRow: some View {
        Picker("Gain source", selection: $replayGainMode) {
            ForEach(ReplayGainMode.selectableCases, id: \.self) { mode in
                Text(mode.displayName).tag(mode)
            }
        }
        .pickerStyle(.menu)
        .help("Automatic prefers album gain and falls back to track gain")
        .onChange(of: replayGainMode) { _, newValue in
            playbackManager.setReplayGainMode(newValue)
        }
    }

    private var replayGainPreampRow: some View {
        HStack(spacing: 10) {
            Text("Gain preamp")
                .frame(width: sliderLabelWidth, alignment: .leading)

            Slider(
                value: $replayGainPreamp,
                in: playbackManager.replayGainPreampRange,
                step: 1
            )
            .onChange(of: replayGainPreamp) { _, newValue in
                playbackManager.setReplayGainPreamp(newValue)
            }

            Text(replayGainPreampLabel)
                .font(.system(.body, design: .monospaced))
                .frame(width: sliderValueWidth, alignment: .trailing)
                .foregroundColor(.secondary)
        }
        .help("Raises normalized playback, which ReplayGain otherwise aims low by modern standards")
    }

    private var replayGainPreampLabel: String {
        String(format: "%+.0f dB", replayGainPreamp)
    }

    /// Reads as off in dev builds, where the updater never runs, without writing to
    /// the stored preference - a production install still honours the user's choice.
    private var automaticUpdatesBinding: Binding<Bool> {
        AppInfo.isProductionBuild ? $automaticUpdatesEnabled : .constant(false)
    }
}

#Preview {
    GeneralTabView()
        .frame(width: 600, height: 500)
        .environmentObject(LibraryManager())
        .environmentObject(PlaybackManager(libraryManager: LibraryManager(), playlistManager: PlaylistManager()))
}
