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
        ListHeader {
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
    @State private var isTruncated = false

    private var isSelected: Bool {
        selectedNode?.id == node.id
    }

    var body: some View {
        VStack(spacing: 1) {
            // Main row
            Button(action: {
                selectedNode = node
                if !node.children.isEmpty {
                    toggleExpansion()
                }
            }) {
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

                    // Create sidebar item for the row content
                    let sidebarItem = FolderNodeSidebarItem(folderNode: node)

                    // Icon
                    Image(systemName: sidebarItem.icon ?? Icons.folderFill)
                        .foregroundColor(isSelected ? .white : .secondary)
                        .font(.system(size: 16))
                        .frame(width: 16, height: 16)

                    // Title and subtitle
                    VStack(alignment: .leading, spacing: 1) {
                        Text(sidebarItem.title)
                            .font(.system(size: 13, weight: isSelected ? .medium : .regular))
                            .lineLimit(1)
                            .foregroundColor(isSelected ? .white : .primary)
                            .truncationMode(.tail)
                            .help(isTruncated ? sidebarItem.title : "")
                            .background(
                                GeometryReader { geometry in
                                    Color.clear
                                        .onAppear {
                                            checkIfTruncated(text: sidebarItem.title, width: geometry.size.width)
                                        }
                                        .onChange(of: sidebarItem.title) {
                                            checkIfTruncated(text: sidebarItem.title, width: geometry.size.width)
                                        }
                                        .onChange(of: geometry.size.width) { _, newWidth in
                                            checkIfTruncated(text: sidebarItem.title, width: newWidth)
                                        }
                                }
                            )

                        if let subtitle = sidebarItem.subtitle {
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

    private func checkIfTruncated(text: String, width: CGFloat) {
        let font = NSFont.systemFont(ofSize: 13, weight: isSelected ? .medium : .regular)
        let attributes = [NSAttributedString.Key.font: font]
        let size = (text as NSString).size(withAttributes: attributes)
        isTruncated = size.width > width
    }
}

#Preview {
    @Previewable @State var selectedNode: FolderNode?

    return FoldersSidebarView(selectedNode: $selectedNode)
        .environmentObject(LibraryManager())
        .frame(width: 250, height: 500)
}
