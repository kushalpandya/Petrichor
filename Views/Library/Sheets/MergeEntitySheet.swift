import SwiftUI

/// Sheet for merging duplicate artists / album artists / composers / albums into a single
/// canonical entity. Mirrors the playlist editor chrome (large editable title, footer) and
/// the export sheet's multi-select list.
struct MergeEntitySheet: View {
    @EnvironmentObject var libraryManager: LibraryManager
    let request: MergeRequest

    @State private var canonicalName: String
    @State private var searchText: String = ""
    @State private var selectedIds: Set<String> = []
    @State private var candidates: [MergeCandidate] = []
    @State private var winnerAlbumId: Int64?
    @State private var isLoadingCandidates = true
    @State private var isMerging = false
    @State private var showingConfirmation = false

    init(request: MergeRequest) {
        self.request = request
        _canonicalName = State(initialValue: request.name)
        // Seed search with the invoked name to surface likely variations first.
        _searchText = State(initialValue: request.name)
    }

    // MARK: - Derived state

    private var filteredCandidates: [MergeCandidate] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return candidates }
        return candidates.filter {
            $0.name.lowercased().contains(query) || ($0.subtitle?.lowercased().contains(query) ?? false)
        }
    }

    private var allFilteredSelected: Bool {
        !filteredCandidates.isEmpty && filteredCandidates.allSatisfy { selectedIds.contains($0.id) }
    }

    private var trimmedName: String {
        canonicalName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var canMerge: Bool {
        !selectedIds.isEmpty && !trimmedName.isEmpty && !isMerging
    }

    private var summary: String? {
        guard !selectedIds.isEmpty else { return nil }
        return String(localized: "Merging \(selectedIds.count) into “\(trimmedName)”")
    }

    private var namePlaceholder: String {
        switch request.kind {
        case .album: return String(localized: "Album Title")
        default: return String(localized: "Name")
        }
    }

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            PlaylistEditorHeader(title: String(localized: "Merge \(request.kind.filterType.pluralDisplayName)")) {
                dismiss()
            }
            Divider()
            titleField
            Divider()
            controls
            Divider()
            candidateList
            Divider()
            PlaylistEditorFooter(
                summary: summary,
                saveTitle: String(localized: "Merge"),
                canSave: canMerge,
                onCancel: { dismiss() },
                onSave: { showingConfirmation = true }
            )
        }
        .frame(width: 640, height: 700)
        .onAppear { loadCandidates() }
        .confirmationDialog(
            String(localized: "Merge \(selectedIds.count) into “\(trimmedName)”?"),
            isPresented: $showingConfirmation,
            titleVisibility: .visible
        ) {
            Button(String(localized: "Merge")) { performMerge() }
                .keyboardShortcut(.defaultAction)
            Button(String(localized: "Cancel"), role: .cancel) {}
        } message: {
            Text("This will combine the selected entries into a single entry under the provided title. It cannot be undone.")
        }
    }

    // MARK: - Title field

    private var titleField: some View {
        ZStack(alignment: .leading) {
            if canonicalName.isEmpty {
                Text(namePlaceholder)
                    .font(.system(size: 24, weight: .regular))
                    .foregroundColor(Color(nsColor: .placeholderTextColor))
            }
            TextField("", text: $canonicalName)
                .textFieldStyle(.plain)
                .font(.system(size: 24, weight: .bold))
                .lineLimit(1)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 16)
    }

    // MARK: - Search + Select All

    private var controls: some View {
        VStack(spacing: 8) {
            searchBox

            HStack {
                Toggle(isOn: Binding(
                    get: { allFilteredSelected },
                    set: { newValue in
                        if newValue {
                            filteredCandidates.forEach { selectedIds.insert($0.id) }
                        } else {
                            filteredCandidates.forEach { selectedIds.remove($0.id) }
                        }
                    }
                )) {
                    Text("Select All (\(filteredCandidates.count))")
                        .font(.subheadline)
                        .fontWeight(.medium)
                }
                .toggleStyle(.checkbox)
                .disabled(filteredCandidates.isEmpty)

                Spacer()
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    private var searchBox: some View {
        HStack {
            Image(systemName: Icons.magnifyingGlass)
                .foregroundColor(.secondary)

            TextField(request.kind.filterType.filterPlaceholder, text: $searchText)
                .textFieldStyle(.plain)

            if !searchText.isEmpty {
                Button(action: { searchText = "" }, label: {
                    Image(systemName: Icons.xmarkCircleFill)
                        .foregroundColor(.secondary)
                })
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 8)
        .frame(height: 28)
        .background(RoundedRectangle(cornerRadius: 6).fill(Color(NSColor.textBackgroundColor)))
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.secondary.opacity(0.3), lineWidth: 1))
    }

    // MARK: - Candidate list

    @ViewBuilder private var candidateList: some View {
        if isLoadingCandidates {
            ProgressView()
                .controlSize(.small)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if candidates.isEmpty {
            emptyState(message: String(localized: "No other entries to merge with"))
        } else if filteredCandidates.isEmpty {
            emptyState(message: String(localized: "No matches"))
        } else {
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(filteredCandidates) { candidate in
                        candidateRow(candidate)
                        if candidate.id != filteredCandidates.last?.id {
                            Divider().padding(.leading, 44)
                        }
                    }
                }
            }
        }
    }

    private func candidateRow(_ candidate: MergeCandidate) -> some View {
        HStack(spacing: 12) {
            Toggle(isOn: Binding(
                get: { selectedIds.contains(candidate.id) },
                set: { isOn in
                    if isOn { selectedIds.insert(candidate.id) } else { selectedIds.remove(candidate.id) }
                }
            )) {
                EmptyView()
            }
            .toggleStyle(.checkbox)

            VStack(alignment: .leading, spacing: 2) {
                Text(candidate.name)
                    .font(.body)
                    .lineLimit(1)

                if let subtitle = candidate.subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer()

            Text(HelperUtils.songCount(candidate.trackCount))
                .font(.caption)
                .foregroundColor(.secondary)
                .monospacedDigit()
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .contentShape(Rectangle())
        .onTapGesture {
            if selectedIds.contains(candidate.id) { selectedIds.remove(candidate.id) } else { selectedIds.insert(candidate.id) }
        }
    }

    private func emptyState(message: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: Icons.magnifyingGlass)
                .font(.system(size: 32))
                .foregroundColor(.gray)
            Text(message)
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    // MARK: - Actions

    private func dismiss() {
        libraryManager.pendingMergeRequest = nil
    }

    /// Load merge candidates off the main thread so presenting the sheet never blocks on the
    /// album candidate query (a full-album scan on large libraries). The album winner is
    /// resolved here too so it stays stable for the sheet's lifetime.
    private func loadCandidates() {
        let libManager = libraryManager
        let request = request
        Task {
            let result = await Task.detached { () -> (Int64?, [MergeCandidate]) in
                let winner = request.kind == .album ? libManager.albumWinnerId(for: request) : nil
                return (winner, libManager.mergeCandidates(for: request, winnerAlbumId: winner))
            }.value
            await MainActor.run {
                winnerAlbumId = result.0
                candidates = result.1
                isLoadingCandidates = false
            }
        }
    }

    private func performMerge() {
        let selected = candidates.filter { selectedIds.contains($0.id) }
        guard !selected.isEmpty else { return }
        isMerging = true
        Task {
            // Success clears pendingMergeRequest, dismissing the sheet.
            await libraryManager.performMerge(request, selected: selected, newName: canonicalName, winnerAlbumId: winnerAlbumId)
            await MainActor.run { isMerging = false }
        }
    }
}
