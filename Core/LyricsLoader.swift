import Foundation
import GRDB

struct LyricsLoader {
    /// Load structured lyrics for a track
    /// - Parameters:
    ///   - track: The track to load lyrics for
    ///   - dbQueue: Database queue for fetching embedded lyrics
    ///   - databaseManager: Database manager for online lyrics storage (optional)
    /// - Returns: Tuple containing parsed lyrics lines and source type
    static func loadLyrics(
        for track: Track,
        using dbQueue: DatabaseQueue,
        databaseManager: DatabaseManager? = nil
    ) async throws -> (lyrics: [LyricLine], source: LyricsSource) {
        var lines: [LyricLine]?
        var source: LyricsSource = .none
        
        // 1. External LRC/SRT files
        if let external = try? loadExternalLyrics(for: track) {
            lines = external.lyrics
            source = external.source
        }
        
        // 2. Embedded lyrics from database
        let fullTrack = try? await track.fullTrack(using: dbQueue)
        if lines == nil,
           let fullTrack = fullTrack,
           let embeddedText = fullTrack.extendedMetadata?.lyrics,
           !embeddedText.isEmpty {
            lines = parseAnyLyrics(embeddedText)
            source = .embedded
        }
        
        // 3. Online lyrics
        if lines == nil,
           let fullTrack = fullTrack,
           let databaseManager = databaseManager,
           let onlineText = await LyricsManager.shared.fetchLyrics(for: fullTrack, using: databaseManager) {
            lines = parseAnyLyrics(onlineText)
            source = .online
        }
        
        // Fallback to empty array
        return (lines ?? [], source)
    }
    
    // MARK: - External files
    
    private static func loadExternalLyrics(for track: Track) throws -> (lyrics: [LyricLine], source: LyricsSource)? {
        let baseURL = track.url.deletingPathExtension()
        
        // LRC
        let lrcURL = baseURL.appendingPathExtension("lrc")
        if FileManager.default.fileExists(atPath: lrcURL.path),
           let content = loadFileWithEncodingDetection(lrcURL),
           !content.isEmpty {
            let parsed = LyricLine.parseLRC(from: content)   // Using your LRC parser
            if !parsed.isEmpty {
                return (parsed, .lrc)
            }
        }
        
        // SRT
        let srtURL = baseURL.appendingPathExtension("srt")
        if FileManager.default.fileExists(atPath: srtURL.path),
           let content = loadFileWithEncodingDetection(srtURL),
           !content.isEmpty {
            let parsed = LyricLine.parseSRT(from: content) // Using your SRT parser
            if !parsed.isEmpty {
                return (parsed, .srt)
            }
        }
        
        return nil
    }
    
    // MARK: - Helpers
    
    /// Try to parse as LRC first, then fallback to plain text lines
    private static func parseAnyLyrics(_ raw: String) -> [LyricLine] {
        // Attempt LRC parsing (covers embedded/online that already have timestamps)
        let lrcResult = LyricLine.parseLRC(from: raw)
        if !lrcResult.isEmpty {
            return lrcResult
        }
        
        // Plain text: split by newlines, each line with startTime=0
        let lines = raw.components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .map { LyricLine(text: $0, startTime: 0, endTime: nil) }
        return lines
    }
    
    /// Load file content with automatic encoding detection
    private static func loadFileWithEncodingDetection(_ url: URL) -> String? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        if let content = String(data: data, encoding: .utf8) {
            return content
        }
        // Fallback for other encodings
        let cfEncoding = CFStringConvertIANACharSetNameToEncoding("EUC_KR" as CFString)
        let nsEncoding = CFStringConvertEncodingToNSStringEncoding(cfEncoding)
        if let content = String(data: data, encoding: String.Encoding(rawValue: nsEncoding)) {
            return content
        }
        return nil
    }
}

enum LyricsSource {
    case lrc
    case srt
    case embedded
    case online
    case none
}
