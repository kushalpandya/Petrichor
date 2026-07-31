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
        }
        .formStyle(.grouped)
        .scrollDisabled(true)
        .padding(5)
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
}
