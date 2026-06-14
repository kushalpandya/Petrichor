import Foundation

struct LyricLine: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    let text: String           // Lyric text of the line
    let startTime: TimeInterval // Start time (seconds)
    var endTime: TimeInterval?  // End time (seconds)
    
    init(text: String, startTime: TimeInterval, endTime: TimeInterval? = nil) {
        self.text = text
        self.startTime = startTime
        self.endTime = endTime
    }
}

typealias Lyrics = [LyricLine]

extension LyricLine {
    
    /// Parse the lyrics from the LRC files
    static func parseLRC(from lrcString: String) -> Lyrics {
        let lines = lrcString.components(separatedBy: "\n")
        var lyrics: [LyricLine] = []
        
        // Use the regular expression to parse the time stamps
        let pattern = "\\[(\\d+):(\\d+)(?:\\.(\\d+))?\\]"
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return lyrics
        }
        
        for line in lines {
            let matches = regex.matches(in: line, range: NSRange(line.startIndex..., in: line))
            let timestamps = matches.map { match -> TimeInterval in
                let nsLine = line as NSString
                let minStr = nsLine.substring(with: match.range(at: 1))
                let secStr = nsLine.substring(with: match.range(at: 2))
                
                let minutes = Double(minStr) ?? 0
                let seconds = Double(secStr) ?? 0

                let timeWithoutMs = minutes * 60 + seconds

                let msRange = match.range(at: 3)
                if msRange.location != NSNotFound, msRange.length > 0 {
                    let msStr = nsLine.substring(with: msRange)
                    let msValue = Double(msStr) ?? 0
                    let divisor = pow(10.0, Double(msStr.count))
                    return timeWithoutMs + msValue / divisor
                } else {
                    return timeWithoutMs
                }
            }
            
            // Get the plain text part from the lyric
            let text = line.replacingOccurrences(of: pattern, with: "", options: .regularExpression)
                .trimmingCharacters(in: .whitespaces)
            
            for timestamp in timestamps {
                lyrics.append(LyricLine(text: text, startTime: timestamp))
            }
        }
        
        // Sort by start time
        var sorted = lyrics.sorted { $0.startTime < $1.startTime }
        if sorted.count > 1 {
            for i in 0..<sorted.count - 1 {
                sorted[i].endTime = sorted[i+1].startTime
            }
        }
        return sorted
    }
    
    /// Parse the lyrics from the SRT files
    static func parseSRT(from srtString: String) -> Lyrics {
        // Divide the content into blocks based on blank lines.
        let blocks = srtString
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .components(separatedBy: "\n\n")
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        
        var lyrics: Lyrics = []
        
        let timePattern = "^(\\d{2}):(\\d{2}):(\\d{2}),(\\d{3}) --> (\\d{2}):(\\d{2}):(\\d{2}),(\\d{3})$"
        guard let timeRegex = try? NSRegularExpression(pattern: timePattern, options: .anchorsMatchLines) else {
            return lyrics
        }
        
        for block in blocks {
            let lines = block.components(separatedBy: "\n").map { $0.trimmingCharacters(in: .whitespaces) }
            
            // Every block has at least 3 lines
            guard lines.count >= 3 else { continue }
            
            // The second line is the time
            let timeLine = lines[1]
            guard let match = timeRegex.firstMatch(in: timeLine, range: NSRange(timeLine.startIndex..., in: timeLine)) else {
                continue
            }
            
            let nsLine = timeLine as NSString
            // Start time
            let startH = Double(nsLine.substring(with: match.range(at: 1))) ?? 0
            let startM = Double(nsLine.substring(with: match.range(at: 2))) ?? 0
            let startS = Double(nsLine.substring(with: match.range(at: 3))) ?? 0
            let startMs = Double(nsLine.substring(with: match.range(at: 4))) ?? 0
            let startTime = startH * 3600 + startM * 60 + startS + startMs / 1000.0
            
            // End time
            let endH = Double(nsLine.substring(with: match.range(at: 5))) ?? 0
            let endM = Double(nsLine.substring(with: match.range(at: 6))) ?? 0
            let endS = Double(nsLine.substring(with: match.range(at: 7))) ?? 0
            let endMs = Double(nsLine.substring(with: match.range(at: 8))) ?? 0
            let endTime = endH * 3600 + endM * 60 + endS + endMs / 1000.0
            
            // The lines from the third line save as the plain text
            let textLines = lines.dropFirst(2)
            let text = textLines.joined(separator: "\n")
            
            lyrics.append(LyricLine(text: text, startTime: startTime, endTime: endTime))
        }
        
        // Sort by start time
        return lyrics.sorted { $0.startTime < $1.startTime }
    }
}


