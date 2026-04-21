import SwiftUI

struct LibraryTabView: View {
    @EnvironmentObject var libraryManager: LibraryManager
    @Environment(\.dismiss) var dismiss

    @AppStorage("autoScanInterval")
    private var autoScanInterval: AutoScanInterval = .every60Minutes

    @AppStorage("discoverUpdateInterval")
    private var discoverUpdateInterval: DiscoverUpdateInterval = .weekly

    @AppStorage("discoverTrackCount")
    private var discoverTrackCount: Int = 50

    @State private var isFoldersListExpanded: Bool = false

    @State private var initialDiscoverTrackCount: Int = 0
    @State private var showRefreshInfo = false
    @State private var showOptimizeInfo = false
    @State private var showResetInfo = false
    @State private var selectedFolderIDs: Set<Int64> = []
    @State private var isSelectMode: Bool = false
    @State private var foldersToRemove: [Folder] = []
    @State private var stableScanningState = false
    @State private var scanningStateTimer: Timer?
    @State private var alsoResetPreferences = false
    @State private var isCommandKeyPressed = false
    @State private var modifierMonitor: Any?

    private var isLibraryUpdateInProgress: Bool {
        libraryManager.isScanning || stableScanningState
    }

    var body: some View {
        Form {
            Section("Discover & Scanning") {
                Picker("Refresh added folders for changes", selection: $autoScanInterval) {
                    ForEach(AutoScanInterval.allCases, id: \.self) { interval in
                        Text(interval.displayName).tag(interval)
                    }
                }
                .help("Automatically scan for new music in the library on selected interval")
                .pickerStyle(.menu)

                Picker("Refresh Discover tracks", selection: $discoverUpdateInterval) {
                    ForEach(DiscoverUpdateInterval.allCases, id: \.self) { interval in
                        Text(interval.displayName).tag(interval)
                    }
                }
                .help("How often to refresh the Discover tracks list")
                .pickerStyle(.menu)

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
                            .controlSize(.mini)
                    }
                    .help("Number of tracks to show in Discover (1-200)")
                }
            }

            Section("Watched Folders") {
                refreshRow
                optimizeRow
                foldersSection
                resetRow
            }
        }
        .formStyle(.grouped)
        .scrollDisabled(true)
        .padding(5)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay(refreshOverlay)
        .onAppear {
            stableScanningState = libraryManager.isScanning
            initialDiscoverTrackCount = discoverTrackCount

            modifierMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { event in
                isCommandKeyPressed = event.modifierFlags.contains(.command)
                return event
            }
        }
        .onDisappear {
            scanningStateTimer?.invalidate()

            if let monitor = modifierMonitor {
                NSEvent.removeMonitor(monitor)
                modifierMonitor = nil
            }

            if discoverTrackCount != initialDiscoverTrackCount {
                libraryManager.refreshDiscoverTracks()
            }
        }
        .onChange(of: libraryManager.isScanning) { _, newValue in
            updateStableScanningState(newValue)
        }
        .alert(
            foldersToRemove.count == 1 ? "Remove Folder" : "Remove Folders",
            isPresented: .init(
                get: { !foldersToRemove.isEmpty },
                set: { if !$0 { foldersToRemove = [] } }
            )
        ) {
            Button("Cancel", role: .cancel) { }
            Button("Remove", role: .destructive) {
                let folders = foldersToRemove
                Task {
                    await MainActor.run {
                        let message = folders.count == 1
                            ? "Removing folder '\(folders[0].name)'..."
                            : "Removing \(folders.count) folders..."
                        NotificationManager.shared.startActivity(message)
                    }

                    try? await Task.sleep(nanoseconds: TimeConstants.fiftyMilliseconds)

                    for folder in folders {
                        libraryManager.removeFolder(folder)
                        try? await Task.sleep(nanoseconds: TimeConstants.fiftyMilliseconds)
                    }

                    await MainActor.run {
                        let message = folders.count == 1
                            ? "Removed folder '\(folders[0].name)'"
                            : "Removed \(folders.count) folders"
                        NotificationManager.shared.addMessage(.info, message)

                        selectedFolderIDs.removeAll()
                        isSelectMode = false
                        foldersToRemove = []
                    }
                }
            }
        } message: {
            let count = foldersToRemove.count
            if count == 1 {
                Text("Are you sure you want to stop watching \"\(foldersToRemove[0].name)\"? This will remove all tracks from this folder from your library.")
            } else {
                Text("Are you sure you want to remove \(count) folders? This will remove all tracks from these folders from your library.")
            }
        }
    }

    // MARK: - Watched Folders Section Rows

    private var refreshRow: some View {
        HStack {
            Text("Refresh added library folders for updates")
            infoButton(isPresented: $showRefreshInfo, text: "Hold the ⌘ key while clicking Refresh for a forced deep re-scan of all metadata.")

            Spacer()

            Button(action: { libraryManager.refreshLibrary(hardRefresh: isCommandKeyPressed) }) {
                Label(
                    isCommandKeyPressed ? "Force Refresh" : "Refresh",
                    systemImage: isCommandKeyPressed ? Icons.arrowClockwiseCircle : Icons.arrowClockwise
                )
            }
            .disabled(isLibraryUpdateInProgress)
        }
    }

    private var foldersSection: some View {
        DisclosureGroup(isExpanded: $isFoldersListExpanded) {
            VStack(spacing: 8) {
                // Selection + Add Folder controls
                HStack {
                    Button(action: toggleSelectMode) {
                        Text(isSelectMode ? "Done" : "Select")
                            .font(.system(size: 12))
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.regular)
                    .disabled(libraryManager.folders.isEmpty || isLibraryUpdateInProgress)

                    if isSelectMode {
                        Text("\(selectedFolderIDs.count) selected")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .padding(.leading, 4)
                    }

                    Spacer()

                    if isSelectMode && !selectedFolderIDs.isEmpty {
                        Button(action: removeSelectedFolders) {
                            Label("Remove Selected", systemImage: "trash")
                                .font(.system(size: 12))
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.regular)
                        .tint(.red)
                    }

                    Button(action: { libraryManager.addFolder() }) {
                        Label("Add Folder", systemImage: "plus")
                    }
                    .buttonStyle(.bordered)
                    .tint(.accentColor)
                    .help("Add a folder to library")
                    .disabled(isLibraryUpdateInProgress)
                }

                // Folders list
                ScrollView {
                    LazyVStack(spacing: 2) {
                        if libraryManager.folders.isEmpty {
                            Text("No folders added yet")
                                .font(.system(size: 12))
                                .foregroundColor(.secondary)
                                .frame(maxWidth: .infinity, minHeight: 80)
                        } else {
                            ForEach(libraryManager.folders) { folder in
                                compactFolderRow(for: folder, isCommandKeyPressed: isCommandKeyPressed)
                                    .padding(.horizontal, 6)
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
                .frame(height: 140)
                .background(Color.secondary.opacity(0.08))
                .cornerRadius(6)
            }
            .padding(.top, 6)
        } label: {
            Text("Folders (\(libraryManager.folders.count))")
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
                .onTapGesture {
                    withAnimation {
                        isFoldersListExpanded.toggle()
                    }
                }
        }
    }

    private var optimizeRow: some View {
        HStack {
            Text("Optimize library database")
            infoButton(isPresented: $showOptimizeInfo, text: "Removes references to library data that no longer exists on disk and compacts the database to reclaim space.")

            Spacer()

            Button(action: { libraryManager.optimizeDatabase(notifyUser: true) }) {
                Label("Optimize", systemImage: "sparkles")
            }
            .disabled(isLibraryUpdateInProgress)
        }
    }

    private var resetRow: some View {
        HStack {
            Text("Reset all library data")
            infoButton(isPresented: $showResetInfo, text: "Removes all folders, tracks, playlists, and pinned items. Use the checkbox in the confirmation dialog to optionally reset app preferences.")

            Spacer()

            Button(action: { showResetConfirmation() }) {
                Label("Reset", systemImage: "trash.fill")
            }
            .buttonStyle(.borderedProminent)
            .tint(.red)
            .disabled(isLibraryUpdateInProgress)
        }
    }

    private func infoButton(isPresented: Binding<Bool>, text: String) -> some View {
        Button { isPresented.wrappedValue.toggle() } label: {
            Image(systemName: "questionmark.circle")
                .font(.system(size: 12))
                .foregroundColor(.secondary)
        }
        .buttonStyle(.plain)
        .popover(isPresented: isPresented, arrowEdge: .trailing) {
            Text(text)
                .font(.system(size: 12))
                .padding(10)
                .frame(width: 240)
        }
    }

    @ViewBuilder
    private var refreshOverlay: some View {
        if stableScanningState {
            ZStack {
                Color.black.opacity(0.2)
                    .ignoresSafeArea()

                VStack(spacing: 20) {
                    ActivityAnimation(size: .medium)

                    VStack(spacing: 8) {
                        Text("Refreshing Library")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.primary)

                        Text(libraryManager.scanStatusMessage.isEmpty ?
                             "Refreshing Library..." : libraryManager.scanStatusMessage)
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .lineLimit(2)
                            .frame(maxWidth: 250, minHeight: 32)
                    }
                }
                .padding(.vertical, 30)
                .padding(.horizontal, 40)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(.thickMaterial)
                        .shadow(color: .black.opacity(0.2), radius: 10)
                )
            }
            .transition(.opacity)
            .animation(.easeInOut(duration: 0.3), value: stableScanningState)
        }
    }

    // MARK: - Folder Row
    @ViewBuilder
    private func compactFolderRow(for folder: Folder, isCommandKeyPressed: Bool) -> some View {
        let isSelected = selectedFolderIDs.contains(folder.id ?? -1)
        let trackCount = folder.trackCount

        CompactFolderRowView(
            folder: folder,
            trackCount: trackCount,
            isSelected: isSelected,
            isSelectMode: isSelectMode,
            isCommandKeyPressed: isCommandKeyPressed,
            onToggleSelection: { toggleFolderSelection(folder) },
            onRefresh: { libraryManager.refreshFolder(folder, hardRefresh: isCommandKeyPressed) },
            onRemove: {
                foldersToRemove = [folder]
            }
        )
    }

    // MARK: - Helper Methods

    private func updateStableScanningState(_ isScanning: Bool) {
        scanningStateTimer?.invalidate()

        if isScanning {
            stableScanningState = true
        } else {
            scanningStateTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: false) { _ in
                stableScanningState = false
            }
        }
    }

    private func toggleSelectMode() {
        guard !libraryManager.folders.isEmpty else { return }

        withAnimation(.easeInOut(duration: 0.2)) {
            isSelectMode.toggle()
            if !isSelectMode {
                selectedFolderIDs.removeAll()
            }
        }
    }

    private func toggleFolderSelection(_ folder: Folder) {
        guard let folderId = folder.id else { return }

        withAnimation(.easeInOut(duration: 0.1)) {
            if selectedFolderIDs.contains(folderId) {
                selectedFolderIDs.remove(folderId)
            } else {
                selectedFolderIDs.insert(folderId)
            }
        }
    }

    private func removeSelectedFolders() {
        foldersToRemove = libraryManager.folders.filter { folder in
            guard let id = folder.id else { return false }
            return selectedFolderIDs.contains(id)
        }
    }

    private func resetLibraryData() {
        if let coordinator = AppCoordinator.shared {
            coordinator.playbackManager.stop()
            coordinator.playlistManager.clearQueue()
        }

        UserDefaults.standard.removeObject(forKey: "SavedMusicFolders")
        UserDefaults.standard.removeObject(forKey: "SavedMusicTracks")
        UserDefaults.standard.removeObject(forKey: "SecurityBookmarks")
        UserDefaults.standard.removeObject(forKey: "LastScanDate")

        UserDefaults.standard.removeObject(forKey: "SavedPlaybackState")
        UserDefaults.standard.removeObject(forKey: "SavedPlaybackUIState")

        if alsoResetPreferences {
            if let bundleID = Bundle.main.bundleIdentifier {
                UserDefaults.standard.removePersistentDomain(forName: bundleID)
                UserDefaults.standard.synchronize()
                Logger.info("All app preferences reset along with library data")

                KeychainManager.delete(key: KeychainManager.Keys.lastfmSessionKey)
            }
        }

        Task {
            do {
                try await libraryManager.resetAllData()
                Logger.info("All library data has been reset")
            } catch {
                Logger.error("Failed to reset library data: \(error)")
            }
        }
    }

    private func showRestartAlert() {
        let alert = NSAlert()
        alert.messageText = "Restart Required"
        alert.informativeText = "App preferences have been reset. Please restart Petrichor for changes to take full effect."
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Quit Now")
        alert.addButton(withTitle: "Later")

        if alert.runModal() == .alertFirstButtonReturn {
            exit(0)
        }
    }

    private func showResetConfirmation() {
        let alert = NSAlert()
        alert.messageText = "Reset Library Data"
        alert.informativeText = "This will permanently remove all library data, including added folders, tracks, playlists, and pinned items. This action cannot be undone."
        alert.alertStyle = .critical
        alert.icon = nil

        let resetButton = alert.addButton(withTitle: "Reset All Data")
        resetButton.hasDestructiveAction = true

        alert.addButton(withTitle: "Cancel")

        alert.showsSuppressionButton = true
        alert.suppressionButton?.title = "Also reset app preferences"

        let response = alert.runModal()

        if response == .alertFirstButtonReturn {
            alsoResetPreferences = alert.suppressionButton?.state == .on

            dismiss()

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                self.resetLibraryData()

                if self.alsoResetPreferences {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        self.showRestartAlert()
                    }
                }

                self.alsoResetPreferences = false
            }
        }
    }
}

private struct CompactFolderRowView: View {
    let folder: Folder
    let trackCount: Int
    let isSelected: Bool
    let isSelectMode: Bool
    let isCommandKeyPressed: Bool
    let onToggleSelection: () -> Void
    let onRefresh: () -> Void
    let onRemove: () -> Void

    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 12) {
            // Selection checkbox (only in select mode)
            if isSelectMode {
                Image(systemName: isSelected ? Icons.checkmarkSquareFill : Icons.square)
                    .font(.system(size: 16))
                    .foregroundColor(isSelected ? .accentColor : .secondary)
                    .onTapGesture {
                        onToggleSelection()
                    }
            }

            // Folder icon
            Image(systemName: Icons.folderFill)
                .font(.system(size: 16))
                .foregroundColor(.secondary)

            // Folder info
            HStack(spacing: 6) {
                Text(folder.name)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)

                Text("(\(folder.url.path))")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .help(folder.url.path)

                Spacer(minLength: 8)

                Text("\(trackCount)")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.secondary)
                +
                Text(" tracks")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }

            // Individual actions (when not in select mode)
            if !isSelectMode {
                HStack(spacing: 4) {
                    Button(action: onRefresh) {
                        Image(systemName: isCommandKeyPressed ? Icons.arrowClockwiseCircle : Icons.arrowClockwise)
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help(isCommandKeyPressed
                        ? "⌘ + Click for deep refresh (re-scans all metadata)"
                        : "Refresh this folder. Hold ⌘ for deep refresh")

                    Button(action: onRemove) {
                        Image(systemName: Icons.minusCircleFill)
                            .font(.system(size: 14))
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Remove this folder")
                }
                .padding(.trailing, 4)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(
                    isSelected && isSelectMode ?
                    Color.accentColor.opacity(0.1) :
                    (isHovered ? Color(NSColor.selectedContentBackgroundColor).opacity(0.15) : Color.clear)
                )
                .animation(.easeInOut(duration: 0.15), value: isHovered)
        )
        .contentShape(Rectangle())
        .onHover { hovering in
            isHovered = hovering
        }
        .onTapGesture {
            if isSelectMode {
                onToggleSelection()
            }
        }
    }
}

#Preview {
    LibraryTabView()
        .environmentObject(LibraryManager())
        .frame(width: 600, height: 500)
}
