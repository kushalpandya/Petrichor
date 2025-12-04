import Foundation
import GRDB

struct LyricsLoader {
    /// Load lyrics for a track, checking external files first, then embedded lyrics
    /// - Parameters:
    ///   - track: The track to load lyrics for
    ///   - dbQueue: Database queue for fetching embedded lyrics
    /// - Returns: Tuple containing lyrics text and source type
    static func loadLyrics(
        for track: Track,
        using dbQueue: DatabaseQueue
    ) async throws -> (lyrics: String, source: LyricsSource) {
        // First, check for external LRC/SRT files
        if let externalLyrics = try? loadExternalLyrics(for: track) {
            return externalLyrics
        }
        
        // Fall back to embedded lyrics
        if let fullTrack = try? await track.fullTrack(using: dbQueue),
           let embeddedLyrics = fullTrack.extendedMetadata?.lyrics,
           !embeddedLyrics.isEmpty {
            return (embeddedLyrics, .embedded)
        }
        
        // No lyrics found
        return ("", .none)
    }
    
    /// Check for and load external lyrics files (.lrc or .srt)
    private static func loadExternalLyrics(for track: Track) throws -> (lyrics: String, source: LyricsSource)? {
        let trackURL = track.url
        let baseURL = trackURL.deletingPathExtension()
        
        // Define file extensions to check in priority order
        let lyricsFormats: [(extension: String, source: LyricsSource, parser: (String) -> String)] = [
            ("lrc", .lrc, parseLRC),
            ("srt", .srt, parseSRT)
        ]
        
        for format in lyricsFormats {
            let lyricsURL = baseURL.appendingPathExtension(format.extension)
            if FileManager.default.fileExists(atPath: lyricsURL.path),
               let content = loadFileWithEncodingDetection(lyricsURL),
               !content.isEmpty {
                return (format.parser(content), format.source)
            }
        }
        
        return nil
    }

    /// Load file content with automatic encoding detection
    private static func loadFileWithEncodingDetection(_ url: URL) -> String? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        
        // Try UTF-8 first
        if let content = String(data: data, encoding: .utf8) {
            return content
        }
        
        // Fall back to automatic detection for other encodings
        let usedEncoding: UInt = 0
        if let nsString = NSString(data: data, encoding: usedEncoding) {
            return nsString as String
        }
        
        return nil
    }
    
    /// Parse LRC file format and extract lyrics text
    private static func parseLRC(_ content: String) -> String {
        let lines = content.components(separatedBy: .newlines)
        var lyricsLines: [String] = []
        
        for line in lines {
            // LRC format: [mm:ss.xx]lyrics text
            // Remove timestamp and metadata tags for now
            if line.hasPrefix("[") {
                if let endBracket = line.firstIndex(of: "]") {
                    let afterBracket = line.index(after: endBracket)
                    if afterBracket < line.endIndex {
                        let lyricsText = String(line[afterBracket...]).trimmingCharacters(in: .whitespaces)
                        if !lyricsText.isEmpty {
                            // Skip metadata lines (ar:, ti:, al:, etc.)
                            let tag = String(line[line.index(after: line.startIndex)..<endBracket])
                            if !tag.contains(":") || tag.contains(".") {
                                lyricsLines.append(lyricsText)
                            }
                        }
                    }
                }
            } else if !line.trimmingCharacters(in: .whitespaces).isEmpty {
                lyricsLines.append(line)
            }
        }
        
        return lyricsLines.joined(separator: "\n")
    }
    
    /// Parse SRT file format and extract lyrics text (ignoring timestamps for now)
    private static func parseSRT(_ content: String) -> String {
        let lines = content.components(separatedBy: .newlines)
        var lyricsLines: [String] = []
        var skipNext = false
        
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            
            // Skip empty lines and sequence numbers
            if trimmed.isEmpty {
                skipNext = false
                continue
            }
            
            // Skip timestamp lines (format: 00:00:00,000 --> 00:00:00,000)
            if trimmed.contains("-->") {
                skipNext = true
                continue
            }
            
            // Skip sequence numbers (just digits)
            if trimmed.allSatisfy({ $0.isNumber }) {
                continue
            }
            
            // Skip the line immediately after timestamp
            if skipNext {
                skipNext = false
            }
            
            // This is lyrics text
            lyricsLines.append(trimmed)
        }
        
        return lyricsLines.joined(separator: "\n")
    }
}

enum LyricsSource {
    case lrc
    case srt
    case embedded
    case none
}
