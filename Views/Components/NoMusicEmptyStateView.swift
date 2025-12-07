import SwiftUI

struct NoMusicEmptyStateView: View {
    @EnvironmentObject var libraryManager: LibraryManager
    @State private var stableScanningState = false
    @State private var scanningStateTimer: Timer?
    @State private var showFormatsPopover = false

    // Customization options
    let context: EmptyStateContext

    enum EmptyStateContext {
        case mainWindow
        case settings

        var iconSize: CGFloat {
            switch self {
            case .mainWindow: return 80
            case .settings: return 60
            }
        }

        var spacing: CGFloat {
            switch self {
            case .mainWindow: return 24
            case .settings: return 20
            }
        }

        var titleFont: Font {
            switch self {
            case .mainWindow: return .largeTitle
            case .settings: return .title2
            }
        }
    }

    var body: some View {
        VStack(spacing: context.spacing) {
            if stableScanningState {
                // Only show scanning animation when truly empty (no folders)
                scanningProgressContent
                    .transition(.opacity)
            } else if libraryManager.folders.isEmpty {
                // Show empty state only when no folders exist
                emptyStateContent
                    .transition(.opacity)
            } else {
                // Folders exist but view is empty - show appropriate message
                noContentView
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.3), value: stableScanningState)
        .frame(maxWidth: context == .mainWindow ? .infinity : 500)
        .frame(maxHeight: context == .mainWindow ? .infinity : 400)
        .padding(context == .mainWindow ? 60 : 40)
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

    private var emptyStateContent: some View {
        VStack(spacing: context.spacing) {
            // Icon with subtle animation
            ZStack {
                Circle()
                    .fill(Color.accentColor.opacity(0.1))
                    .frame(width: context.iconSize * 1.8, height: context.iconSize * 1.8)

                Image(systemName: Icons.folderBadgePlus)
                    .font(.system(size: context.iconSize, weight: .light))
                    .foregroundColor(.accentColor)
                    .symbolEffect(.pulse.byLayer, options: .repeating.speed(0.5))
            }

            VStack(spacing: 12) {
                Text("No Music Added Yet")
                    .font(context.titleFont)
                    .fontWeight(.semibold)

                VStack(spacing: 8) {
                    Text("Add folders containing your music to get started")
                        .font(.title3)
                        .foregroundColor(.secondary)

                    Text("You can select multiple folders at once")
                        .font(.subheadline)
                        .foregroundColor(.secondary.opacity(0.7))
                }
                .multilineTextAlignment(.center)
            }

            // Add button
            Button(action: { libraryManager.addFolder() }) {
                HStack(spacing: 6) {
                    Image(systemName: Icons.plusCircleFill)
                        .font(.system(size: 16))
                    Text("Add Music Folder")
                        .font(.system(size: 14, weight: .medium))
                }
                .foregroundColor(.white)
                .padding(.horizontal, 20)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.accentColor)
                        .shadow(color: Color.accentColor.opacity(0.3), radius: 6, x: 0, y: 3)
                )
            }
            .buttonStyle(PlainButtonStyle())

            // Supported formats
            Button {
                showFormatsPopover.toggle()
            } label: {
                Text("Supported formats")
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundColor(.secondary)
                    .underline()
            }
            .buttonStyle(.plain)
            .popover(isPresented: $showFormatsPopover, arrowEdge: .bottom) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Supported Formats")
                        .font(.headline)

                    Divider()

                    ScrollView {
                        Text(AudioFormat.supportedFormatsDisplay)
                            .font(.system(size: 12, design: .monospaced))
                            .textSelection(.enabled)
                            .padding(.vertical, 4)
                    }
                    .frame(maxWidth: 320, maxHeight: 160)
                }
                .padding(12)
                .frame(width: 340)
            }
            .padding(.top, 8)
        }
        .transition(.opacity)
    }

    // MARK: - Scanning Progress Content

    private var scanningProgressContent: some View {
        VStack(spacing: 20) {
            ActivityAnimation(size: .large)

            VStack(spacing: 8) {
                Text("Scanning Music Library")
                    .font(.title2)
                    .fontWeight(.semibold)

                Text(libraryManager.scanStatusMessage.isEmpty ? "Discovering your music..." : libraryManager.scanStatusMessage)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 350, minHeight: 40)
            }

            // Track count
            if !libraryManager.folders.isEmpty {
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
    NoMusicEmptyStateView(context: .mainWindow)
        .environmentObject(LibraryManager())
        .frame(width: 800, height: 600)
}

#Preview("Settings") {
    NoMusicEmptyStateView(context: .settings)
        .environmentObject(LibraryManager())
        .frame(width: 600, height: 500)
}

#Preview("Scanning") {
    NoMusicEmptyStateView(context: .mainWindow)
        .environmentObject({
            let manager = LibraryManager()
            manager.isScanning = true
            manager.scanStatusMessage = "Processing My Music Collection..."
            return manager
        }())
        .frame(width: 800, height: 600)
}
