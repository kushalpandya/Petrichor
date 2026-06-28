import SwiftUI

struct AppearanceTabView: View {
    @AppStorage("colorMode")
    private var colorMode: ColorMode = .auto

    @AppStorage("showFoldersTab")
    private var showFoldersTab = false

    @AppStorage("showTrackTechnicalInfo")
    private var showTrackTechnicalInfo = true

    @AppStorage("useArtworkColors")
    private var useArtworkColors = true

    @AppStorage("playerBarBackgroundStyle")
    private var playerBarBackgroundStyle: PlayerBarBackgroundStyle = .fullWidth

    @AppStorage("tintPlaybackControls")
    private var tintPlaybackControls = true

    @AppStorage("tintNowPlayingBackground")
    private var tintNowPlayingBackground = true

    @AppStorage("miniPlayerAlwaysOnTop")
    private var miniPlayerAlwaysOnTop = false

    @State private var showTrackInfoHelp = false

    /// Leading inset used to nest the options that depend on the master tint toggle.
    private let dependentIndent: CGFloat = 20

    enum ColorMode: String, CaseIterable, TabbedItem {
        case light = "Light"
        case dark = "Dark"
        case auto = "Auto"

        var displayName: String {
            switch self {
            case .light: return String(localized: "Light")
            case .dark: return String(localized: "Dark")
            case .auto: return String(localized: "Auto")
            }
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
            Section("Visibility") {
                Toggle("Show folders tab in main window", isOn: $showFoldersTab)
                    .help("Shows Folders tab within the main window to browse music directly from added folders")

                Toggle(isOn: $showTrackTechnicalInfo) {
                    HStack(spacing: 4) {
                        Text("Show audio format details")
                        infoButton
                    }
                }
                .help("Shows the playing track's codec, bitrate, sample rate, and channels in the player")

                Toggle("Keep Mini Player on top of all other windows", isOn: $miniPlayerAlwaysOnTop)
                    .help("Floats the Mini Player window above windows from other apps")
            }

            Section("Customization") {
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

                Toggle("Tint interface with album artwork colors", isOn: $useArtworkColors)
                    .help("Applies a gradient background derived from album artwork colors across the app")

                Picker("Player bar background style", selection: $playerBarBackgroundStyle) {
                    ForEach(PlayerBarBackgroundStyle.allCases, id: \.self) { style in
                        Text(style.displayName).tag(style)
                    }
                }
                .pickerStyle(.radioGroup)
                .disabled(!useArtworkColors)
                .padding(.leading, dependentIndent)

                Toggle("Color playback and audio controls", isOn: $tintPlaybackControls)
                    .help("Uses the album artwork's dominant color for playback and volume controls in the player, Mini Player, and Immersive mode")
                    .disabled(!useArtworkColors)
                    .padding(.leading, dependentIndent)

                Toggle("Use artwork background in Mini Player and Immersive mode", isOn: $tintNowPlayingBackground)
                    .help("Uses album artwork colors as the background in Mini Player and Immersive mode")
                    .disabled(!useArtworkColors)
                    .padding(.leading, dependentIndent)
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

    private var infoButton: some View {
        Button { showTrackInfoHelp.toggle() } label: {
            Image(systemName: "questionmark.circle")
                .font(.system(size: 12))
                .foregroundColor(.secondary)
        }
        .buttonStyle(.plain)
        .popover(isPresented: $showTrackInfoHelp, arrowEdge: .trailing) {
            Text("Shows small badges under the playing track for its audio details like codec (FLAC, MP3, etc.), bitrate, sample rate, and channels.")
                .font(.system(size: 12))
                .padding(10)
                .frame(width: 240)
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
    AppearanceTabView()
        .frame(width: 600, height: 500)
}
