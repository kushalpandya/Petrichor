//
// PlaylistManager class extension
//
// This extension contains methods for importing and exporting M3U playlists.
//

import Foundation

// MARK: - Import/Export Result Types

enum M3UImportError: Error, LocalizedError {
    case fileReadFailed(filename: String)
    case invalidFormat(filename: String)
    case emptyFile(filename: String)
    
    var errorDescription: String? {
        switch self {
        case .fileReadFailed(let filename):
            return "Could not read file '\(filename)'"
        case .invalidFormat(let filename):
            return "File '\(filename)' has invalid M3U format"
        case .emptyFile(let filename):
            return "File '\(filename)' contains no tracks"
        }
    }
}

struct PlaylistImportResult {
    let playlistName: String
    let totalTracksInFile: Int
    let tracksAdded: Int
    let tracksMissing: [String]
    let error: Error?
    
    var isSuccess: Bool {
        error == nil && tracksAdded > 0
    }
    
    var hasWarnings: Bool {
        error == nil && !tracksMissing.isEmpty && tracksAdded > 0
    }
    
    var isCompleteFailure: Bool {
        error != nil || (tracksAdded == 0 && totalTracksInFile > 0)
    }
}

struct BulkImportResult {
    let results: [PlaylistImportResult]
    
    var totalFiles: Int { results.count }
    var successful: Int { results.filter { $0.isSuccess && !$0.hasWarnings }.count }
    var withWarnings: Int { results.filter { $0.hasWarnings }.count }
    var failed: Int { results.filter { $0.isCompleteFailure }.count }
    var totalTracksImported: Int { results.reduce(0) { $0 + $1.tracksAdded } }
    var totalTracksMissing: Int { results.reduce(0) { $0 + $1.tracksMissing.count } }
}

struct PlaylistExportResult {
    let playlistName: String
    let trackCount: Int
    let filePath: String
    let error: Error?
    
    var isSuccess: Bool { error == nil }
}

struct BulkExportResult {
    let results: [PlaylistExportResult]
    
    var totalPlaylists: Int { results.count }
    var successful: Int { results.filter { $0.isSuccess }.count }
    var failed: [(playlist: String, error: Error)] {
        results.filter { !$0.isSuccess }.compactMap { result in
            guard let error = result.error else { return nil }
            return (result.playlistName, error)
        }
    }
}

private enum M3UFormat {
    static let header = "#EXTM3U"
    static let infoPrefix = "#EXTINF:"
    static let commentPrefix = "#"
    static let lineEnding = "\r\n"
}

// MARK: - PlaylistManager Extension

extension PlaylistManager {
    // MARK: - Import
    
    func importPlaylists(from urls: [URL]) async -> BulkImportResult {
        let existingNames = await fetchExistingPlaylistNames()
        var usedNames = Set(existingNames.map { $0.lowercased() })
        var results: [PlaylistImportResult] = []
        
        for url in urls {
            let didStartAccess = url.startAccessingSecurityScopedResource()
            let result = await importSinglePlaylist(from: url, usedNames: usedNames)
            results.append(result)
            
            if didStartAccess {
                url.stopAccessingSecurityScopedResource()
            }
            
            usedNames.insert(result.playlistName.lowercased())
        }
        
        return BulkImportResult(results: results)
    }
    
    private func fetchExistingPlaylistNames() async -> [String] {
        await MainActor.run { playlists.map { $0.name } }
    }
    
    private func importSinglePlaylist(from url: URL, usedNames: Set<String>) async -> PlaylistImportResult {
        let basePlaylistName = url.deletingPathExtension().lastPathComponent
        
        let fileContent = (try? String(contentsOf: url, encoding: .utf8)) ??
                          (try? String(contentsOf: url, encoding: .isoLatin1))
        
        guard let content = fileContent else {
            Logger.error("Failed to read '\(url.lastPathComponent)' (tried UTF-8 and Latin-1)")
            return PlaylistImportResult(
                playlistName: basePlaylistName,
                totalTracksInFile: 0,
                tracksAdded: 0,
                tracksMissing: [],
                error: M3UImportError.fileReadFailed(filename: url.lastPathComponent)
            )
        }
        
        return await processM3UContent(content, playlistName: basePlaylistName, usedNames: usedNames)
    }
    
    private func processM3UContent(_ content: String, playlistName: String, usedNames: Set<String>) async -> PlaylistImportResult {
        let trackPaths = parseM3UContent(content)
        
        guard !trackPaths.isEmpty else {
            Logger.error("Empty M3U file: \(playlistName)")
            return PlaylistImportResult(
                playlistName: playlistName,
                totalTracksInFile: 0,
                tracksAdded: 0,
                tracksMissing: [],
                error: M3UImportError.emptyFile(filename: "\(playlistName).m3u")
            )
        }
        
        let matchResult = await matchTracksToLibrary(trackPaths: trackPaths)
        
        guard !matchResult.matchedTracks.isEmpty else {
            Logger.error("Import failed - '\(playlistName)': 0/\(trackPaths.count) tracks found in library")
            return PlaylistImportResult(
                playlistName: playlistName,
                totalTracksInFile: trackPaths.count,
                tracksAdded: 0,
                tracksMissing: matchResult.unmatchedPaths,
                error: nil
            )
        }
        
        if !matchResult.unmatchedPaths.isEmpty {
            let sample = matchResult.unmatchedPaths.prefix(3).joined(separator: ", ")
            let more = matchResult.unmatchedPaths.count > 3 ? " (+\(matchResult.unmatchedPaths.count - 3) more)" : ""
            Logger.warning("Partial import - '\(playlistName)': \(matchResult.matchedTracks.count)/\(trackPaths.count) tracks. Missing: \(sample)\(more)")
        }
        
        let uniquePlaylistName = generateUniquePlaylistName(baseName: playlistName, existingNames: usedNames)
        
        let createdPlaylist = await MainActor.run {
            createPlaylist(name: uniquePlaylistName, tracks: matchResult.matchedTracks)
        }
        
        await MainActor.run {
            guard let index = playlists.firstIndex(where: { $0.id == createdPlaylist.id }),
                  let dbManager = libraryManager?.databaseManager else {
                return
            }
            playlists[index].tracks = dbManager.loadTracksForPlaylist(createdPlaylist.id)
        }
        
        return PlaylistImportResult(
            playlistName: uniquePlaylistName,
            totalTracksInFile: trackPaths.count,
            tracksAdded: matchResult.matchedTracks.count,
            tracksMissing: matchResult.unmatchedPaths,
            error: nil
        )
    }
    
    private func parseM3UContent(_ content: String) -> [String] {
        content.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && !$0.hasPrefix(M3UFormat.commentPrefix) }
    }
    
    private func matchTracksToLibrary(trackPaths: [String]) async -> (matchedTracks: [Track], unmatchedPaths: [String]) {
        guard let dbManager = libraryManager?.databaseManager else {
            return ([], trackPaths)
        }
        
        var matchedTracks: [Track] = []
        var unmatchedPaths: [String] = []
        
        for path in trackPaths {
            if let track = await dbManager.findTrackByPath(path) {
                matchedTracks.append(track)
            } else {
                unmatchedPaths.append(path)
            }
        }
        
        return (matchedTracks, unmatchedPaths)
    }
    
    private func generateUniquePlaylistName(baseName: String, existingNames: Set<String>) -> String {
        guard existingNames.contains(baseName.lowercased()) else {
            return baseName
        }
        
        let baseNameLower = baseName.lowercased()
        let highestNumber = existingNames.reduce(1) { currentMax, name in
            guard name.hasPrefix(baseNameLower + " ") else { return currentMax }
            let suffix = String(name.dropFirst(baseNameLower.count + 1))
            return max(currentMax, Int(suffix) ?? 0)
        }
        
        return "\(baseName) \(highestNumber + 1)"
    }
    
    // MARK: - Export
    
    func exportPlaylists(_ playlists: [Playlist], to directoryURL: URL) async -> BulkExportResult {
        var results: [PlaylistExportResult] = []
        
        for playlist in playlists {
            let filename = FilesystemUtils.sanitizeFilename(playlist.name) + ".m3u"
            let fileURL = directoryURL.appendingPathComponent(filename)
            let result = await exportSinglePlaylist(playlist, to: fileURL)
            results.append(result)
        }
        
        return BulkExportResult(results: results)
    }
    
    func exportPlaylist(_ playlist: Playlist, to fileURL: URL) async -> PlaylistExportResult {
        await exportSinglePlaylist(playlist, to: fileURL)
    }
    
    private func exportSinglePlaylist(_ playlist: Playlist, to fileURL: URL) async -> PlaylistExportResult {
        let tracks = playlist.tracks.isEmpty
            ? await MainActor.run { getPlaylistTracks(playlist) }
            : playlist.tracks
        
        let m3uContent = generateM3UContent(for: tracks)
        
        do {
            try FilesystemUtils.writeM3UFile(content: m3uContent, to: fileURL)
            return PlaylistExportResult(
                playlistName: playlist.name,
                trackCount: tracks.count,
                filePath: fileURL.path,
                error: nil
            )
        } catch {
            Logger.error("Failed to export '\(playlist.name)': \(error)")
            return PlaylistExportResult(
                playlistName: playlist.name,
                trackCount: tracks.count,
                filePath: fileURL.path,
                error: error
            )
        }
    }
    
    private func generateM3UContent(for tracks: [Track]) -> String {
        var lines = [M3UFormat.header]
        
        for track in tracks {
            let durationSeconds = Int(track.duration)
            let artistTitle = "\(track.artist) - \(track.title)"
            lines.append("\(M3UFormat.infoPrefix)\(durationSeconds),\(artistTitle)")
            lines.append(track.url.path)
        }
        
        return lines.joined(separator: M3UFormat.lineEnding)
    }
}
