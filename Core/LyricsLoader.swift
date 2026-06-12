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
    
    /// Load file content with automatic encoding detection, trying a broader set of
    /// common East‑Asian and Western encodings instead of only UTF‑8 and EUC‑KR.
    private static func loadFileWithEncodingDetection(_ url: URL) -> String? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        
        // 1. Try the most common Swift built‑in encodings
        let builtInEncodings: [String.Encoding] = [
            .utf8,
            .utf16,                  // Detects BOM and picks LE/BE accordingly
            .utf16BigEndian,
            .utf16LittleEndian,
            .isoLatin1,              // Covers most Western languages
            .windowsCP1252,          // Another Western fallback
            .shiftJIS,
            .japaneseEUC,
        ]
        for enc in builtInEncodings {
            if let content = String(data: data, encoding: enc) {
                return content
            }
        }
        
        // 2. Try additional encodings via IANA charset names (EUC‑KR, GBK, etc.)
        let ianaNames = [
            "EUC-KR",   // Korean
            "GBK",      // Simplified Chinese
            "BIG5",     // Traditional Chinese
            "ISO-2022-JP",
        ]
        for name in ianaNames {
            let cfEnc = CFStringConvertIANACharSetNameToEncoding(name as CFString)
            guard cfEnc != kCFStringEncodingInvalidId else { continue }
            let nsEnc = CFStringConvertEncodingToNSStringEncoding(cfEnc)
            if let content = String(data: data, encoding: String.Encoding(rawValue: nsEnc)) {
                return content
            }
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
