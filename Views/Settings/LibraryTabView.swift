import SwiftUI

struct LibraryTabView: View {
    @EnvironmentObject var libraryManager: LibraryManager
    @State private var showingRemoveFolderAlert = false
    @State private var showingResetConfirmation = false
    @State private var selectedFolderIDs: Set<Int64> = []
    @State private var isSelectMode: Bool = false
    @State private var folderToRemove: Folder?
    @State private var stableScanningState = false
    @State private var stableRefreshButtonState = false
    @State private var scanningStateTimer: Timer?
    @StateObject private var notificationManager = NotificationManager.shared
    
    private var isLibraryUpdateInProgress: Bool {
        libraryManager.isScanning ||
        notificationManager.isActivityInProgress ||
        stableScanningState
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
            stableScanningState = libraryManager.isScanning || notificationManager.isActivityInProgress
        }
        .onDisappear {
            scanningStateTimer?.invalidate()
        }
        .onChange(of: libraryManager.isScanning) { _, newValue in
            updateStableScanningState(newValue || notificationManager.isActivityInProgress)
            updateStableRefreshState(newValue || notificationManager.isActivityInProgress)
        }
        .onChange(of: notificationManager.isActivityInProgress) { _, newValue in
            updateStableScanningState(newValue || libraryManager.isScanning)
            updateStableRefreshState(newValue || libraryManager.isScanning)
        }
        .alert("Remove Folder", isPresented: $showingRemoveFolderAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Remove", role: .destructive) {
                if let folder = folderToRemove {
                    Task {
                        await MainActor.run {
                            NotificationManager.shared.startActivity("Removing folder '\(folder.name)'...")
                        }
                        
                        // Small delay to ensure UI updates
                        try? await Task.sleep(nanoseconds: TimeConstants.fiftyMilliseconds)
                        
                        libraryManager.removeFolder(folder)
                        
                        await MainActor.run {
                            folderToRemove = nil
                        }
                    }
                }
            }
        } message: {
            if let folder = folderToRemove {
                Text("Are you sure you want to stop watching \"\(folder.name)\"? This will remove all tracks from this folder from your library.")
            }
        }
        .alert("Reset Library Data", isPresented: $showingResetConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Reset All Data", role: .destructive) {
                resetLibraryData()
            }
        } message: {
            Text("This will permanently remove all library data, including added folders, tracks, and playlists. This action cannot be undone.")
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

            Button(action: { libraryManager.refreshLibrary() }) {
                Label("Refresh Library", systemImage: "arrow.clockwise")
            }
            .help("Scan for new files and update metadata")
            .disabled(isLibraryUpdateInProgress)

            Button(action: { libraryManager.addFolder() }) {
                Label("Add Folder", systemImage: "plus")
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
                        compactFolderRow(for: folder)
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

                Button(action: { showingResetConfirmation = true }) {
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
            }

            // Status info
            if let lastScan = UserDefaults.standard.object(forKey: "LastScanDate") as? Date {
                HStack {
                    Text("Last scan: \(lastScan, style: .relative) ago")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Spacer()
                }
            }
        }
        .padding(.horizontal, 34)
        .padding(.vertical, 10)
    }

    // MARK: - Folder Row
    @ViewBuilder
    private func compactFolderRow(for folder: Folder) -> some View {
        let isSelected = selectedFolderIDs.contains(folder.id ?? -1)
        let trackCount = folder.trackCount

        CompactFolderRowView(
            folder: folder,
            trackCount: trackCount,
            isSelected: isSelected,
            isSelectMode: isSelectMode,
            onToggleSelection: { toggleFolderSelection(folder) },
            onRefresh: { libraryManager.refreshFolder(folder) },
            onRemove: {
                folderToRemove = folder
                showingRemoveFolderAlert = true
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
        let selectedFolders = libraryManager.folders.filter { folder in
            guard let id = folder.id else { return false }
            return selectedFolderIDs.contains(id)
        }

        let alert = NSAlert()
        alert.messageText = "Remove Selected Folders"
        alert.informativeText = "Are you sure you want to remove \(selectedFolders.count) folders? This will remove all tracks from these folders from your library."
        alert.addButton(withTitle: "Remove")
        alert.addButton(withTitle: "Cancel")
        alert.alertStyle = .warning

        if alert.runModal() == .alertFirstButtonReturn {
            // User confirmed - now show progress
            Task {
                await MainActor.run {
                    let message = selectedFolders.count == 1
                        ? "Removing folder '\(selectedFolders[0].name)'..."
                        : "Removing \(selectedFolders.count) folders..."
                    NotificationManager.shared.startActivity(message)
                }
                
                // Small delay to ensure UI updates
                try? await Task.sleep(nanoseconds: TimeConstants.fiftyMilliseconds)
                
                for folder in selectedFolders {
                    libraryManager.removeFolder(folder)
                    // Small delay between removals
                    try? await Task.sleep(nanoseconds: TimeConstants.fiftyMilliseconds)
                }
                
                await MainActor.run {
                    selectedFolderIDs.removeAll()
                    isSelectMode = false
                }
            }
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

        Task {
            do {
                try await libraryManager.resetAllData()
                Logger.info("All library data has been reset")
            } catch {
                Logger.error("Failed to reset library data: \(error)")
            }
        }
    }
}

private struct CompactFolderRowView: View {
    let folder: Folder
    let trackCount: Int
    let isSelected: Bool
    let isSelectMode: Bool
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
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Refresh this folder")

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
