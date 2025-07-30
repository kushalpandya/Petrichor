import SwiftUI

struct GeneralTabView: View {
    @AppStorage("startAtLogin")
    private var startAtLogin = false

    @AppStorage("closeToMenubar")
    private var closeToMenubar = true
    
    @AppStorage("hideDuplicateTracks")
    private var hideDuplicateTracks: Bool = true

    @AppStorage("autoScanInterval")
    private var autoScanInterval: AutoScanInterval = .every60Minutes

    @AppStorage("colorMode")
    private var colorMode: ColorMode = .auto

    @AppStorage("showFoldersTab")
    private var showFoldersTab = false
    
    @AppStorage("discoverUpdateInterval")
    private var discoverUpdateInterval: DiscoverUpdateInterval = .weekly

    @AppStorage("discoverTrackCount")
    private var discoverTrackCount: Int = 50
    
    @State private var initialDiscoverTrackCount: Int = 0

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
                        Logger.info("Hide duplicate songs setting changed to \(hideDuplicateTracks), synchronizing UserDefaults, this will require a relaunch")
                        UserDefaults.standard.synchronize()
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
            }

            Section("Library") {
                HStack {
                    Picker("Auto-scan library every", selection: $autoScanInterval) {
                        ForEach(AutoScanInterval.allCases, id: \.self) { interval in
                            Text(interval.displayName).tag(interval)
                        }
                    }
                    .help("Automatically scan for new music in the library on selected interval")
                    .pickerStyle(.menu)
                    .frame(maxWidth: .infinity)
                }
                
                HStack {
                    Picker("Refresh Discover every", selection: $discoverUpdateInterval) {
                        ForEach(DiscoverUpdateInterval.allCases, id: \.self) { interval in
                            Text(interval.displayName).tag(interval)
                        }
                    }
                    .help("How often to refresh the Discover tracks list")
                    .pickerStyle(.menu)
                    .frame(maxWidth: .infinity)
                }

                HStack {
                    Text("Number of Discover tracks")
                    Spacer()
                    HStack(spacing: 4) {
                        Text("\(discoverTrackCount)")
                            .font(.system(.body, design: .monospaced))
                            .frame(minWidth: 40, alignment: .trailing)
                            .foregroundColor(.primary)
                        Stepper("", value: $discoverTrackCount, in: 1...200, step: 1)
                            .labelsHidden()
                            .fixedSize()
                    }
                    .help("Number of tracks to show in Discover (1-200)")
                }
            }
        }
        .formStyle(.grouped)
        .scrollDisabled(true)
        .scrollContentBackground(.hidden)
        .background(Color.clear)
        .padding()
        .onChange(of: colorMode) { _, newValue in
            updateAppearance(newValue)
        }
        .onAppear {
            updateAppearance(colorMode)
        }
        .onAppear {
            initialDiscoverTrackCount = discoverTrackCount
        }
        .onDisappear {
            if discoverTrackCount != initialDiscoverTrackCount {
                if let libraryManager = AppCoordinator.shared?.libraryManager {
                    libraryManager.refreshDiscoverTracks()
                }
            }
        }
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
