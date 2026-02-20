import SwiftUI

struct LibraryTabView: View {
    @EnvironmentObject var libraryManager: LibraryManager
    @Environment(\.dismiss) var dismiss

    @State private var selectedFolderIDs: Set<Int64> = []
    @State private var isSelectMode: Bool = false
    @State private var foldersToRemove: [Folder] = []
    @State private var stableScanningState = false
    @State private var stableRefreshButtonState = false
    @State private var scanningStateTimer: Timer?
    @State private var alsoResetPreferences = false
    @State private var isCommandKeyPressed = false
    @State private var modifierMonitor: Any?
    @StateObject private var notificationManager = NotificationManager.shared
    
    private var isLibraryUpdateInProgress: Bool {
        libraryManager.isScanning || stableScanningState
    }

    var body: some View {
        VStack(spacing: 0) {
            if libraryManager.folders.isEmpty {
                // Empty state
                NoMusicEmptyStateView(context: .settings)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                // Library management UI
                libraryManagementContent
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            stableScanningState = libraryManager.isScanning
            
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
        }
        .onChange(of: libraryManager.isScanning) { _, newValue in
            updateStableScanningState(newValue)
            updateStableRefreshState(newValue)
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

    private var libraryManagementContent: some View {
        VStack(spacing: 0) {
            libraryHeader
            foldersList
            libraryFooter
        }
    }

    private var libraryHeader: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Watched Folders")
                    .font(.system(size: 14, weight: .semibold))
            }

            Spacer()

            Button(action: { libraryManager.refreshLibrary(hardRefresh: isCommandKeyPressed) }) {
                Label(
                    isCommandKeyPressed ? "Force Refresh Library" : "Refresh Library",
                    systemImage: isCommandKeyPressed ? Icons.arrowClockwiseCircle : Icons.arrowClockwise
                )
                .frame(height: 16)
            }
            .help(isCommandKeyPressed
                ? "Force complete re-scan of all metadata (slower)"
                : "Scan for new files and update metadata. Hold ⌘ for deep refresh")
            .disabled(isLibraryUpdateInProgress)

            Button(action: { libraryManager.addFolder() }) {
                Label("Add Folder", systemImage: "plus")
                    .frame(height: 16)
            }
            .buttonStyle(.borderedProminent)
            .help("Add a folder to library")
            .disabled(isLibraryUpdateInProgress)
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 10)
    }

    private var foldersList: some View {
        VStack(spacing: 0) {
            // Selection controls bar - Always visible
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
                        .padding(.leading, 8)
                }

                Spacer()

                if isSelectMode && !selectedFolderIDs.isEmpty {
                    Button(action: removeSelectedFolders) {
                        Label("Remove Selected", systemImage: "trash")
                            .font(.system(size: 12))
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.regular)
                    .tint(.red)
                }
            }
            .padding(.horizontal, 0)
            .padding(.vertical, 5)

            // Folders list
            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(libraryManager.folders) { folder in
                        compactFolderRow(for: folder, isCommandKeyPressed: isCommandKeyPressed)
                            .padding(.horizontal, 6)
                    }
                }
                .padding(.vertical, 6)
            }
            .frame(height: 350)
            .background(Color.secondary.opacity(0.08))
            .cornerRadius(6)
            .overlay(refreshOverlay)
            
            Text("\(libraryManager.folders.count) folders • \(libraryManager.totalTrackCount) tracks")
                .font(.footnote)
                .foregroundColor(.secondary)
                .padding(.vertical, 6)
        }
        .padding(.horizontal, 35)
    }

    @ViewBuilder
    private var refreshOverlay: some View {
        if stableScanningState {
            ZStack {
                // Semi-transparent background
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.black.opacity(0.2))
                
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

    private var libraryFooter: some View {
        VStack(spacing: 12) {
            // Action buttons row
            HStack(spacing: 12) {
                Button(action: { libraryManager.optimizeDatabase(notifyUser: true) }) {
                    HStack(spacing: 6) {
                        Image(systemName: "sparkles")
                            .font(.system(size: 12, weight: .medium))
                        Text("Optimize Library Database")
                            .font(.system(size: 13, weight: .medium))
                    }
                    .foregroundColor(.primary)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 6)
                    .frame(maxWidth: .infinity)
                    .background(Color(NSColor.separatorColor))
                    .cornerRadius(5)
                }
                .buttonStyle(.plain)
                .disabled(isLibraryUpdateInProgress)
                .help("Removes references to library data that no longer exists on disk and compacts the database to reclaim space")

                Button(action: { showResetConfirmation() }) {
                    HStack(spacing: 6) {
                        Image(systemName: "trash.fill")
                            .font(.system(size: 12, weight: .medium))
                        Text("Reset All Library Data")
                            .font(.system(size: 13, weight: .medium))
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 6)
                    .frame(maxWidth: .infinity)
                    .background(Color.red)
                    .cornerRadius(5)
                }
                .buttonStyle(.plain)
                .disabled(isLibraryUpdateInProgress)
                .help("Remove all folders, tracks, playlists, and pinned items. Use the checkbox in the confirmation dialog to optionally reset app preferences.")
            }
        }
        .padding(.horizontal, 34)
        .padding(.vertical, 10)
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
    
    private func updateStableRefreshState(_ isDisabled: Bool) {
        if isDisabled {
            stableRefreshButtonState = true
        } else {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                stableRefreshButtonState = false
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
        // Stop any current playback
        if let coordinator = AppCoordinator.shared {
            coordinator.playbackManager.stop()
            coordinator.playlistManager.clearQueue()
        }

        // Clear UserDefaults settings
        UserDefaults.standard.removeObject(forKey: "SavedMusicFolders")
        UserDefaults.standard.removeObject(forKey: "SavedMusicTracks")
        UserDefaults.standard.removeObject(forKey: "SecurityBookmarks")
        UserDefaults.standard.removeObject(forKey: "LastScanDate")

        // Clear playback state
        UserDefaults.standard.removeObject(forKey: "SavedPlaybackState")
        UserDefaults.standard.removeObject(forKey: "SavedPlaybackUIState")
        
        // Optionally clear all preferences
        if alsoResetPreferences {
            if let bundleID = Bundle.main.bundleIdentifier {
                UserDefaults.standard.removePersistentDomain(forName: bundleID)
                UserDefaults.standard.synchronize()
                Logger.info("All app preferences reset along with library data")
                
                // Clear Last.fm connection from Keychain
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
            
            // Close settings window first
            dismiss()
            
            // Small delay to let the window close
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
                .foregroundColor(.accentColor)

            // Folder info
            VStack(alignment: .leading, spacing: 2) {
                Text(folder.name)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)

                HStack(spacing: 4) {
                    Text(folder.url.path)
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)

                    Spacer()

                    Text("\(trackCount)")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.secondary)
                    +
                    Text(" tracks")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
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
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
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
