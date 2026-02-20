import Foundation
import GRDB

struct LyricsLoader {
    /// Load lyrics for a track, checking external files first, then embedded lyrics, then online
    /// - Parameters:
    ///   - track: The track to load lyrics for
    ///   - dbQueue: Database queue for fetching embedded lyrics
    ///   - databaseManager: Database manager for online lyrics storage (optional)
    /// - Returns: Tuple containing lyrics text and source type
    static func loadLyrics(
        for track: Track,
        using dbQueue: DatabaseQueue,
        databaseManager: DatabaseManager? = nil
    ) async throws -> (lyrics: String, source: LyricsSource) {
        var rawLyrics: String?
        var source: LyricsSource = .none
        
        // First, check for external LRC/SRT files
        if let externalLyrics = try? loadExternalLyrics(for: track) {
            rawLyrics = externalLyrics.lyrics
            source = externalLyrics.source
        }
        
        // Second, check for embedded lyrics (stored in db during library scan)
        let fullTrack = try? await track.fullTrack(using: dbQueue)
        if rawLyrics == nil,
           let fullTrack = fullTrack,
           let embeddedLyrics = fullTrack.extendedMetadata?.lyrics,
           !embeddedLyrics.isEmpty {
            rawLyrics = embeddedLyrics
            source = .embedded
        }
        
        // Finally, try fetching from online source
        if rawLyrics == nil,
           let fullTrack = fullTrack,
           let databaseManager = databaseManager,
           let onlineLyrics = await LyricsManager.shared.fetchLyrics(for: fullTrack, using: databaseManager) {
            rawLyrics = onlineLyrics
            source = .online
        }
        
        // Strip timestamps for display
        guard let lyrics = rawLyrics else {
            return ("", .none)
        }
        
        let displayLyrics = stripTimestamps(lyrics)
        return (displayLyrics, source)
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
    
    // MARK: - Timestamp Stripping
            
    /// Strip LRC-style timestamps from lyrics for display
    private static func stripTimestamps(_ content: String) -> String {
        let lines = content.components(separatedBy: .newlines)
        var strippedLines: [String] = []
        
        for line in lines {
            var currentLine = line
            
            // Remove all timestamp tags [mm:ss.xx] from the line
            while currentLine.hasPrefix("[") {
                if let endBracket = currentLine.firstIndex(of: "]") {
                    let tag = String(currentLine[currentLine.index(after: currentLine.startIndex)..<endBracket])
                    // Check if it's a timestamp (contains digits and colons/periods)
                    let isTimestamp = tag.contains(":") && tag.rangeOfCharacter(from: .decimalDigits) != nil
                    
                    if isTimestamp {
                        currentLine = String(currentLine[currentLine.index(after: endBracket)...])
                    } else {
                        break
                    }
                } else {
                    break
                }
            }
            
            let trimmed = currentLine.trimmingCharacters(in: .whitespaces)
            if !trimmed.isEmpty {
                strippedLines.append(trimmed)
            }
        }
        
        return strippedLines.joined(separator: "\n")
    }
    
    // MARK: - Format Parsing
    
    /// Parse LRC file format and extract lyrics text
    private static func parseLRC(_ content: String) -> String {
        let lines = content.components(separatedBy: .newlines)
        var lyricsLines: [String] = []
        
        for line in lines {
            if line.hasPrefix("[") {
                if let endBracket = line.firstIndex(of: "]") {
                    let tag = String(line[line.index(after: line.startIndex)..<endBracket])
                    
                    // Skip metadata lines (ar:, ti:, al:, etc.) but not timestamps
                    let isMetadata = tag.contains(":") && tag.rangeOfCharacter(from: .decimalDigits) == nil
                    if isMetadata {
                        continue
                    }
                    
                    // Keep the full line (with timestamps) for now
                    lyricsLines.append(line)
                }
            } else if !line.trimmingCharacters(in: .whitespaces).isEmpty {
                lyricsLines.append(line)
            }
        }
        
        // Strip timestamps at the end
        return stripTimestamps(lyricsLines.joined(separator: "\n"))
    }
    
    /// Parse SRT file format and extract lyrics text
    private static func parseSRT(_ content: String) -> String {
        let lines = content.components(separatedBy: .newlines)
        var lyricsLines: [String] = []
        
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            
            // Skip empty lines
            if trimmed.isEmpty {
                continue
            }
            
            // Skip timestamp lines (format: 00:00:00,000 --> 00:00:00,000)
            if trimmed.contains("-->") {
                continue
            }
            
            // Skip sequence numbers (just digits)
            if trimmed.allSatisfy({ $0.isNumber }) {
                continue
            }
            
            lyricsLines.append(trimmed)
        }
        
        return lyricsLines.joined(separator: "\n")
    }
}

enum LyricsSource {
    case lrc
    case srt
    case embedded
    case online
    case none
}
