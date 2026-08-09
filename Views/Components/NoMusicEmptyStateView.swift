import SwiftUI

struct NoMusicEmptyStateView: View {
    @EnvironmentObject var libraryManager: LibraryManager
    @ObservedObject private var radioManager = InternetRadioManager.shared
    @State private var stableScanningState = false
    @State private var scanningStateTimer: Timer?
    @State private var showFormatsPopover = false
    @State private var isDownloadingStations = false

    // Customization options
    let context: EmptyStateContext

    enum EmptyStateContext {
        case onboarding
        case localLibrary
        case settings

        var iconSize: CGFloat {
            switch self {
            case .onboarding, .localLibrary: return 80
            case .settings: return 60
            }
        }

        var spacing: CGFloat {
            switch self {
            case .onboarding, .localLibrary: return 24
            case .settings: return 20
            }
        }

        var titleFont: Font {
            switch self {
            case .onboarding, .localLibrary: return .largeTitle
            case .settings: return .title2
            }
        }
    }
    
    /// Determines if scanning state should be shown based on context and initial scan progress
    private var shouldShowScanningState: Bool {
        switch context {
        case .onboarding, .localLibrary:
            if libraryManager.isInitialOnboardingScan {
                return !libraryManager.hasReachedInitialScanThreshold
            }
            return libraryManager.folders.isEmpty
        case .settings:
            // Settings always shows scanning state when scanning is active
            return true
        }
    }

    var body: some View {
        VStack(spacing: context.spacing) {
            if isDownloadingStations {
                downloadingStationsContent
                    .transition(.opacity)
            } else if stableScanningState && shouldShowScanningState {
                // Show scanning animation during initial scan until threshold is reached
                scanningProgressContent
                    .transition(.opacity)
            } else if context == .onboarding && libraryManager.folders.isEmpty {
                onboardingContent
                    .transition(.opacity)
            } else if context != .settings && libraryManager.folders.isEmpty {
                localLibraryContent
                    .transition(.opacity)
            } else {
                noContentView
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.3), value: stableScanningState)
        .animation(.easeInOut(duration: 0.3), value: libraryManager.hasReachedInitialScanThreshold)
        .frame(maxWidth: context == .settings ? 500 : .infinity)
        .frame(maxHeight: context == .settings ? 400 : .infinity)
        .padding(context == .settings ? 40 : 60)
        .onAppear {
            setupScanningStateObserver()
        }
        .onDisappear {
            scanningStateTimer?.invalidate()
        }
        .onChange(of: libraryManager.isScanning) { _, newValue in
            updateStableScanningState(newValue)
        }
    }

    private func setupScanningStateObserver() {
        // Initialize with current state
        stableScanningState = libraryManager.isScanning
    }

    private func updateStableScanningState(_ isScanning: Bool) {
        // Cancel any pending timer
        scanningStateTimer?.invalidate()

        if isScanning {
            // Turn on immediately
            stableScanningState = true
        } else {
            // Delay turning off to prevent flashing
            scanningStateTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: false) { _ in
                stableScanningState = false
            }
        }
    }

    // MARK: - Empty State Content

    private var noContentView: some View {
        VStack(spacing: 16) {
            Image(systemName: Icons.musicNoteList)
                .font(.system(size: 48))
                .foregroundColor(.gray)

            Text("No music found")
                .font(.headline)
                .foregroundColor(.secondary)

            Text("Your folders are being scanned for music files")
                .font(.subheadline)
                .foregroundColor(.secondary.opacity(0.8))
        }
    }

    private var onboardingContent: some View {
        VStack(spacing: context.spacing) {
            Image("custom.music")
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .foregroundStyle(.tint)
                .frame(width: context.iconSize, height: context.iconSize)
                .symbolEffect(.pulse, options: .repeating.speed(0.5))

            VStack(spacing: 12) {
                Text("Welcome to Petrichor")
                    .font(context.titleFont)
                    .fontWeight(.semibold)

                Text("Play music from your library or start with internet radio.")
                    .font(.title3)
                    .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            }

            HStack(spacing: 14) {
                onboardingButton(
                    title: String(localized: "Add Music Folder"),
                    subtitle: String(localized: "Scan music stored on this Mac or an external drive."),
                    icon: Icons.folderBadgePlus,
                    action: libraryManager.addFolder
                )

                onboardingButton(
                    title: String(localized: "Explore Internet Radio"),
                    subtitle: String(localized: "Download a starter set of popular stations."),
                    icon: Icons.radioFill
                ) {
                    isDownloadingStations = true
                    Task {
                        await Task.yield()
                        let result = await radioManager.downloadTopStations()
                        isDownloadingStations = false
                        guard result.canOpenRadio else { return }
                        NotificationCenter.default.post(name: .navigateToInternetRadio, object: nil)
                    }
                }
                .disabled(isDownloadingStations || radioManager.isFetchingDefaults)
            }

            supportedFormatsButton
        }
        .transition(.opacity)
    }

    private var localLibraryContent: some View {
        VStack(spacing: context.spacing) {
            ZStack {
                Circle()
                    .fill(Color.accentColor.opacity(0.1))
                    .frame(width: context.iconSize * 1.8, height: context.iconSize * 1.8)

                Image(systemName: Icons.folderBadgePlus)
                    .font(.system(size: context.iconSize, weight: .light))
                    .foregroundColor(.accentColor)
            }

            VStack(spacing: 8) {
                Text("No Music Added Yet")
                    .font(context.titleFont)
                    .fontWeight(.semibold)
                Text("Add folders containing your music to get started")
                    .font(.title3)
                    .foregroundColor(.secondary)
            }

            Button("Add Music Folder", action: libraryManager.addFolder)
                .buttonStyle(.borderedProminent)
                .controlSize(.large)

            supportedFormatsButton
        }
    }

    private func onboardingButton(
        title: String,
        subtitle: String,
        icon: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 24))
                    .foregroundStyle(.tint)
                    .frame(height: 24)
                Text(title)
                    .font(.headline)
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.leading)
            }
            .frame(width: 230, height: 105, alignment: .topLeading)
            .padding(18)
            .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
    }

    private var supportedFormatsButton: some View {
        Button {
            showFormatsPopover.toggle()
        } label: {
            Text("Supported formats")
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundStyle(.secondary)
                .underline()
        }
        .buttonStyle(.plain)
        .popover(isPresented: $showFormatsPopover, arrowEdge: .bottom) {
            SupportedFormatsPopover()
        }
    }

    // MARK: - Scanning Progress Content

    private var downloadingStationsContent: some View {
        VStack(spacing: 20) {
            ActivityAnimation(size: .large)

            Text("Downloading popular stations...")
                .font(.title2)
                .fontWeight(.semibold)

            Text("This may take a moment")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .transition(.opacity)
    }

    private var scanningProgressContent: some View {
        VStack(spacing: 20) {
            ActivityAnimation(size: .large)

            VStack(spacing: 8) {
                Text("Scanning Music Library")
                    .font(.title2)
                    .fontWeight(.semibold)

                (libraryManager.scanStatusMessage.isEmpty ? Text("Discovering your music...") : Text(libraryManager.scanStatusMessage))
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 350, minHeight: 40)
            }

            // Track count (hidden until the first track lands, so it doesn't read "0 tracks found")
            if !libraryManager.folders.isEmpty && libraryManager.totalTrackCount > 0 {
                Text("\(libraryManager.totalTrackCount) tracks found")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Text("This may take a few minutes for large libraries")
                .font(.caption)
                .foregroundColor(.secondary.opacity(0.7))
                .italic()
        }
        .transition(.opacity)
    }
}

// MARK: - Preview

#Preview("Main Window") {
    NoMusicEmptyStateView(context: .onboarding)
        .environmentObject(LibraryManager())
        .frame(width: 800, height: 600)
}

#Preview("Settings") {
    NoMusicEmptyStateView(context: .settings)
        .environmentObject(LibraryManager())
        .frame(width: 600, height: 500)
}

#Preview("Scanning") {
    NoMusicEmptyStateView(context: .localLibrary)
        .environmentObject({
            let manager = LibraryManager()
            manager.isScanning = true
            manager.scanStatusMessage = "Processing My Music Collection..."
            return manager
        }())
        .frame(width: 800, height: 600)
}
