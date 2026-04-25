import SwiftUI

struct FoldersSidebarView: View {
    @EnvironmentObject var libraryManager: LibraryManager
    @Binding var selectedNode: FolderNode?
    @State private var folderNodes: [FolderNode] = []
    @State private var isLoadingHierarchy = false

    private let hierarchyBuilder = FolderHierarchyBuilder()

    var body: some View {
        VStack(spacing: 0) {
            // Header
            sidebarHeader

            Divider()

            // Folder tree
            if isLoadingHierarchy {
                loadingView
            } else if folderNodes.isEmpty {
                emptyView
            } else {
                ScrollView(.vertical) {
                    VStack(alignment: .leading, spacing: 1) {
                        ForEach(folderNodes) { node in
                            FolderNodeRow(
                                node: node,
                                selectedNode: $selectedNode,
                                level: 0
                            )
                        }

                        Spacer(minLength: 0)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .padding(.vertical, 4)
                }
            }
        }
        .task {
            await loadFolderHierarchy()
        }
        .onChange(of: libraryManager.folders) {
            Task {
                await loadFolderHierarchy()
            }
        }
    }

    // MARK: - Header

    private var sidebarHeader: some View {
        ListHeader(opaque: true) {
            Text("Folders")
                .headerTitleStyle()

            Spacer()
        }
    }

    // MARK: - Empty/Loading Views

    private var loadingView: some View {
        VStack {
            ProgressView("Loading library folders...")
                .font(.caption)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    private var emptyView: some View {
        VStack(spacing: 16) {
            Image(systemName: Icons.folder)
                .font(.system(size: 32))
                .foregroundColor(.gray)

            Text("No Folders")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 200)
        .padding()
    }

    // MARK: - Helper Methods

    private func loadFolderHierarchy() async {
        await MainActor.run {
            isLoadingHierarchy = true
        }

        let trackCounts = libraryManager.getTrackCountsByFolderPath()

        let nodes = await hierarchyBuilder.buildHierarchy(
            for: libraryManager.folders,
            trackCountsByFolder: trackCounts
        )

        await MainActor.run {
            self.folderNodes = nodes
            isLoadingHierarchy = false

            // Select first node if none selected
            if selectedNode == nil, let firstNode = nodes.first {
                selectedNode = firstNode
            }
        }
    }
}

// MARK: - Folder Node Row

private struct FolderNodeRow: View {
    @ObservedObject var node: FolderNode
    @Binding var selectedNode: FolderNode?
    let level: Int

    @State private var isHovered = false

    private var isSelected: Bool {
        selectedNode?.id == node.id
    }

    private var folderIcon: String {
        if node.children.isEmpty {
            return Icons.folderFill
        }
        return node.isExpanded ? Icons.folderFillBadgeMinus : Icons.folderFillBadgePlus
    }

    private var subtitle: String? {
        let folderCount = node.immediateFolderCount
        let trackCount = node.displayTrackCount
        if folderCount > 0 && trackCount > 0 {
            return "\(folderCount) folders, \(trackCount) tracks"
        } else if folderCount > 0 {
            return "\(folderCount) folders"
        } else if trackCount > 0 {
            return "\(trackCount) tracks"
        }
        return nil
    }

    var body: some View {
        VStack(spacing: 1) {
            // Main row
            Button {
                selectedNode = node
                if !node.children.isEmpty {
                    toggleExpansion()
                }
            } label: {
                HStack(spacing: 8) {
                    // Indentation
                    if level > 0 {
                        Color.clear
                            .frame(width: CGFloat(level * 20))
                    }

                    // Expand/collapse button
                    if !node.children.isEmpty {
                        Image(systemName: node.isExpanded ? Icons.chevronDown : Icons.chevronRight)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(.secondary)
                            .frame(width: 16, height: 16)
                            .animation(.easeInOut(duration: AnimationDuration.standardDuration), value: node.isExpanded)
                    } else {
                        // Spacer for alignment
                        Color.clear
                            .frame(width: 16, height: 16)
                    }

                    // Icon
                    Image(systemName: folderIcon)
                        .foregroundColor(isSelected ? .white : .secondary)
                        .font(.system(size: 16))
                        .frame(width: 16, height: 16)

                    // Title and subtitle
                    VStack(alignment: .leading, spacing: 1) {
                        Text(node.name)
                            .font(.system(size: 13, weight: isSelected ? .medium : .regular))
                            .lineLimit(1)
                            .foregroundColor(isSelected ? .white : .primary)
                            .truncationMode(.tail)
                            .help(node.name)

                        if let subtitle {
                            Text(subtitle)
                                .font(.system(size: 11))
                                .foregroundColor(isSelected ? .white.opacity(0.8) : .secondary)
                                .lineLimit(1)
                        }
                    }

                    Spacer()
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(backgroundColor)
                    .animation(.easeInOut(duration: AnimationDuration.quickDuration), value: isHovered)
                    .animation(.easeInOut(duration: 0.05), value: isSelected)
            )
            .onHover { hovering in
                isHovered = hovering
            }

            // Child nodes (if expanded)
            if node.isExpanded {
                ForEach(node.children) { childNode in
                    FolderNodeRow(
                        node: childNode,
                        selectedNode: $selectedNode,
                        level: level + 1
                    )
                }
            }
        }
        .padding(.horizontal, level > 0 ? 0 : 4)
    }

    private var backgroundColor: Color {
        if isSelected {
            return Color.accentColor
        } else if isHovered {
            return Color(NSColor.selectedContentBackgroundColor).opacity(0.15)
        } else {
            return Color.clear
        }
    }

    private func toggleExpansion() {
        withAnimation(.easeInOut(duration: 0.15)) {
            node.isExpanded.toggle()
        }
    }
}

#Preview {
    @Previewable @State var selectedNode: FolderNode?

    return FoldersSidebarView(selectedNode: $selectedNode)
        .environmentObject(LibraryManager())
        .frame(width: 250, height: 500)
}
