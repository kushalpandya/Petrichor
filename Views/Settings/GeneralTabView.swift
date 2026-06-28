import SwiftUI
import Sparkle

struct GeneralTabView: View {
    @EnvironmentObject var libraryManager: LibraryManager

    @AppStorage("startAtLogin")
    private var startAtLogin = false

    @AppStorage("closeToMenubar")
    private var closeToMenubar = true
    
    @AppStorage("hideDuplicateTracks")
    private var hideDuplicateTracks: Bool = true
    
    @AppStorage("automaticUpdatesEnabled")
    private var automaticUpdatesEnabled = true

    @AppStorage(MediaBackend.userDefaultsKey)
    private var useModernPlaybackEngine = true

    @ObservedObject private var notificationManager = NotificationManager.shared

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
                Toggle("Check for updates automatically", isOn: $automaticUpdatesEnabled)
                    .help("Automatically download and install updates when available")
                    .onChange(of: automaticUpdatesEnabled) { _, newValue in
                        if let appDelegate = NSApp.delegate as? AppDelegate,
                           let updater = appDelegate.updaterController?.updater {
                            updater.automaticallyChecksForUpdates = newValue
                        }
                    }
            }

            Section("Media Backend") {
                HStack(spacing: 6) {
                    Text("Use modern media engine")
                    betaBadge
                    engineInfoButton

                    Spacer()

                    Toggle("", isOn: $useModernPlaybackEngine)
                        .labelsHidden()
                        .disabled(notificationManager.isActivityInProgress)
                        .help(engineToggleHelp)
                        .onChange(of: useModernPlaybackEngine) {
                            UserDefaults.standard.synchronize()
                            AppCoordinator.shared?.playbackManager.reloadPlaybackEngine()
                        }
                }
            }
        }
        .formStyle(.grouped)
        .scrollDisabled(true)
        .padding(5)
    }

    private var engineToggleHelp: String {
        if notificationManager.isActivityInProgress {
            return String(localized: "Unavailable while the library is updating")
        }
        // swiftlint:disable:next line_length - localization key must remain a single literal for extraction.
        let message = String(localized: "Switches the engine used to play your music. Changing this will cause the playback to stop, and you can resume it later.")
        return message
    }

    @State private var showEngineInfo = false

    private var engineInfoButton: some View {
        Button { showEngineInfo.toggle() } label: {
            Image(systemName: "questionmark.circle")
                .font(.system(size: 12))
                .foregroundColor(.secondary)
        }
        .buttonStyle(.plain)
        .popover(isPresented: $showEngineInfo, arrowEdge: .trailing) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Our newer engine for playing your music. With it on, you may notice:")

                VStack(alignment: .leading, spacing: 6) {
                    engineInfoPoint(
                        String(localized: "Gapless playback, so albums and live recordings flow from one track to the next with no silent pause.")
                    )
                    engineInfoPoint(String(localized: "Wider, more spacious stereo sound."))
                    engineInfoPoint(String(localized: "Spatial Audio on supported headphones."))
                }

                Text("Turn it off to switch back to the classic engine. Your music and library stay exactly the same either way.")
                    .foregroundColor(.secondary)
            }
            .font(.system(size: 12))
            .padding(12)
            .frame(width: 260)
        }
    }

    private func engineInfoPoint(_ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text("•")
            Text(text)
        }
    }

    private var betaBadge: some View {
        Text("Beta")
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Color.accentColor.opacity(0.15))
            .foregroundStyle(Color.accentColor)
            .clipShape(Capsule())
    }
}

#Preview {
    GeneralTabView()
        .frame(width: 600, height: 500)
        .environmentObject(LibraryManager())
}
