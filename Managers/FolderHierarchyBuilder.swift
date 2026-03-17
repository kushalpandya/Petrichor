//
// FolderHierarchyBuilder class
//
// This class handles the Folders tree view within the sidebar in Folders tab.
//

import Foundation

class FolderHierarchyBuilder {
    private let fileManager = FileManager.default
    private let supportedExtensions = AudioFormat.supportedExtensions

    // Build hierarchy for all watched folders
    func buildHierarchy(for folders: [Folder], trackCountsByFolder: [String: Int]) async -> [FolderNode] {
        var rootNodes: [FolderNode] = []

        for folder in folders {
            // Create root node for each watched folder
            let rootNode = FolderNode(url: folder.url, name: folder.name, isWatchFolder: true)
            rootNode.databaseFolder = folder

            // Build the hierarchy for this root folder
            await buildSubtree(for: rootNode, tracksByFolder: trackCountsByFolder)

            rootNodes.append(rootNode)
        }

        return rootNodes
    }

    // Recursively build subtree for a node
    private func buildSubtree(for node: FolderNode, tracksByFolder: [String: Int]) async {
        do {
            let contents = try fileManager.contentsOfDirectory(
                at: node.url,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            )

            var subfolders: [FolderNode] = []
            var trackCount = 0

            for itemURL in contents {
                let resourceValues = try itemURL.resourceValues(forKeys: [.isDirectoryKey])

                if resourceValues.isDirectory == true {
                    // It's a subfolder - create a node for it
                    let childNode = FolderNode(url: itemURL)

                    // Recursively build its subtree
                    await buildSubtree(for: childNode, tracksByFolder: tracksByFolder)

                    // Only add folders that contain tracks (directly or in subfolders)
                    if childNode.immediateTrackCount > 0 || !childNode.children.isEmpty {
                        subfolders.append(childNode)
                    }
                } else {
                    // Check if it's a supported audio file
                    let fileExtension = itemURL.pathExtension.lowercased()
                    if supportedExtensions.contains(fileExtension) {
                        trackCount += 1
                    }
                }
            }

            let finalSubfolders = subfolders
            let finalTrackCount = trackCount
            let dbTrackCount = tracksByFolder[node.url.path] ?? 0

            await MainActor.run {
                node.children = finalSubfolders.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
                node.immediateTrackCount = finalTrackCount
                node.displayTrackCount = dbTrackCount
            }
        } catch {
            Logger.error("Failed to scan folder \(node.url.path): \(error)")
        }
    }

    // Get all tracks for a specific folder node (immediate only, not recursive)
    func getTracksForNode(_ node: FolderNode, from allTracks: [Track]) -> [Track] {
        allTracks.filter { track in
            track.url.deletingLastPathComponent() == node.url
        }
    }

    // Check if a folder node contains a specific track
    func nodeContainsTrack(_ node: FolderNode, track: Track) -> Bool {
        // Check if track's parent directory matches this node's URL
        track.url.deletingLastPathComponent() == node.url
    }
}
