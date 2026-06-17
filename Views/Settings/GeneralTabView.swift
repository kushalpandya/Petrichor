import SwiftUI
import Sparkle

struct GeneralTabView: View {
    @AppStorage("startAtLogin")
    private var startAtLogin = false

    @AppStorage("closeToMenubar")
    private var closeToMenubar = true
    
    @AppStorage("hideDuplicateTracks")
    private var hideDuplicateTracks: Bool = true
    
    @AppStorage("automaticUpdatesEnabled")
    private var automaticUpdatesEnabled = true

    @AppStorage("colorMode")
    private var colorMode: ColorMode = .auto

    @AppStorage("showFoldersTab")
    private var showFoldersTab = false

    @AppStorage("useArtworkColors")
    private var useArtworkColors = true

    @AppStorage(MediaBackend.userDefaultsKey)
    private var useModernPlaybackEngine = true

    @ObservedObject private var notificationManager = NotificationManager.shared

    enum ColorMode: String, CaseIterable, TabbedItem {
        case light = "Light"
        case dark = "Dark"
        case auto = "Auto"

        var displayName: String {
            self.rawValue
        }

        var icon: String {
            switch self {
            case .light:
                return "sun.max.fill"
            case .dark:
                return "moon.fill"
            case .auto:
                return "circle.lefthalf.filled"
            }
        }

        var title: String { self.displayName }
    }

    var body: some View {
        Form {
            Section("Behavior") {
                Toggle("Start at login", isOn: $startAtLogin)
                    .help("Starts app on login")
                Toggle("Keep running in menubar on close", isOn: $closeToMenubar)
                    .help("Keeps the app running in the menubar even after closing")
                Toggle("Hide duplicate songs (requires app relaunch)", isOn: $hideDuplicateTracks)
                    .help("Shows only the highest quality version when multiple copies exist")
                    .onChange(of: hideDuplicateTracks) {
                        // Force UserDefaults to write immediately to prevent out of sync
                        Logger.info(
                            """
                            Hide duplicate songs setting changed to \(hideDuplicateTracks), \
                            synchronizing UserDefaults, this will require a relaunch
                            """
                        )
                        UserDefaults.standard.synchronize()
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

            Section("Appearance") {
                HStack {
                    Text("Color mode")
                    Spacer()
                    TabbedButtons(
                        items: ColorMode.allCases,
                        selection: $colorMode,
                        style: .flexible
                    )
                    .frame(width: 200)
                }

                Toggle("Show folders tab in main window", isOn: $showFoldersTab)
                    .help("Shows Folders tab within the main window to browse music directly from added folders")

                Toggle("Use album artwork colors in backgrounds", isOn: $useArtworkColors)
                    .help("Applies a gradient background derived from album artwork colors across the app")
            }

            Section("Media Backend") {
                Toggle(isOn: $useModernPlaybackEngine) {
                    HStack(spacing: 6) {
                        Text("Use modern media engine")
                        betaBadge
                    }
                }
                .disabled(notificationManager.isActivityInProgress)
                .help(
                    notificationManager.isActivityInProgress
                        ? "Unavailable while the library is updating"
                        : "Switches the engine used to play your music. Changing this will cause the playback to stop, and you can resume it later."
                )
                .onChange(of: useModernPlaybackEngine) {
                    UserDefaults.standard.synchronize()
                    AppCoordinator.shared?.playbackManager.reloadPlaybackEngine()
                }
            }
        }
        .formStyle(.grouped)
        .scrollDisabled(true)
        .padding(5)
        .onChange(of: colorMode) { _, newValue in
            updateAppearance(newValue)
        }
        .onAppear {
            updateAppearance(colorMode)
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

    private func updateAppearance(_ mode: ColorMode) {
        switch mode {
        case .light:
            NSApp.appearance = NSAppearance(named: .aqua)
        case .dark:
            NSApp.appearance = NSAppearance(named: .darkAqua)
        case .auto:
            NSApp.appearance = nil
        }
    }
}

#Preview {
    GeneralTabView()
        .frame(width: 600, height: 500)
}
