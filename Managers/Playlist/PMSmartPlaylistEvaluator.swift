//
// PlaylistManager class extension
//
// This extension contains methods for computing smart playlists with custom matching criteria.
//

import Foundation

extension PlaylistManager {
    /// Evaluate tracks for a smart playlist based on its criteria
    func evaluateSmartPlaylist(_ playlist: Playlist, allTracks: [Track]) -> [Track] {
        guard playlist.type == .smart,
              let criteria = playlist.smartCriteria else {
            return []
        }
        
        // First, filter tracks based on rules
        var filteredTracks = allTracks.filter { track in
            evaluateTrackAgainstCriteria(track, criteria: criteria)
        }
        
        // Then sort if specified
        if let sortBy = criteria.sortBy {
            filteredTracks = sortTracks(filteredTracks, by: sortBy, ascending: criteria.sortAscending)
        }
        
        // Finally, apply limit if specified
        if let limit = criteria.limit {
            filteredTracks = Array(filteredTracks.prefix(limit))
        }
        
        return filteredTracks
    }
    
    /// Evaluate a single track against smart playlist criteria
    internal func evaluateTrackAgainstCriteria(_ track: Track, criteria: SmartPlaylistCriteria) -> Bool {
        let results = criteria.rules.map { rule in
            evaluateRule(track, rule: rule)
        }
        
        switch criteria.matchType {
        case .all:
            return results.allSatisfy { $0 }
        case .any:
            return results.contains { $0 }
        }
    }
    
    /// Evaluate a single rule against a track
    private func evaluateRule(_ track: Track, rule: SmartPlaylistCriteria.Rule) -> Bool {
        switch rule.field {
        case "isFavorite":
            return evaluateBooleanRule(track.isFavorite, condition: rule.condition, value: rule.value)
            
        case "playCount":
            return evaluateNumericRule(Double(track.playCount), condition: rule.condition, value: rule.value)
            
        case "lastPlayedDate":
            return evaluateDateRule(track.lastPlayedDate, condition: rule.condition, value: rule.value)
            
        case "title":
            return evaluateStringRule(track.title, condition: rule.condition, value: rule.value)
            
        case "artist":
            return evaluateStringRule(track.artist, condition: rule.condition, value: rule.value)
            
        case "album":
            return evaluateStringRule(track.album, condition: rule.condition, value: rule.value)
            
        case "genre":
            return evaluateStringRule(track.genre, condition: rule.condition, value: rule.value)
            
        case "year":
            // Handle year as numeric for greater than/less than comparisons
            if let yearInt = Int(track.year) {
                return evaluateNumericRule(Double(yearInt), condition: rule.condition, value: rule.value)
            } else {
                return evaluateStringRule(track.year, condition: rule.condition, value: rule.value)
            }
            
        case "composer":
            return evaluateStringRule(track.composer, condition: rule.condition, value: rule.value)
            
        case "albumArtist":
            return evaluateStringRule(track.albumArtist ?? "", condition: rule.condition, value: rule.value)
            
        case "duration":
            return evaluateNumericRule(track.duration, condition: rule.condition, value: rule.value)
            
        default:
            Logger.warning("Unknown field for smart playlist rule: \(rule.field)")
            return false
        }
    }
    
    // MARK: - Rule Evaluation Helpers
    
    private func evaluateBooleanRule(_ value: Bool, condition: SmartPlaylistCriteria.Condition, value ruleValue: String) -> Bool {
        let expectedValue = ruleValue.lowercased() == "true"
        
        switch condition {
        case .equals:
            return value == expectedValue
        default:
            return false
        }
    }
    
    private func evaluateStringRule(_ value: String, condition: SmartPlaylistCriteria.Condition, value ruleValue: String) -> Bool {
        let lowercasedValue = value.lowercased()
        let lowercasedRuleValue = ruleValue.lowercased()
        
        switch condition {
        case .contains:
            return lowercasedValue.contains(lowercasedRuleValue)
        case .equals:
            return lowercasedValue == lowercasedRuleValue
        case .startsWith:
            return lowercasedValue.hasPrefix(lowercasedRuleValue)
        case .endsWith:
            return lowercasedValue.hasSuffix(lowercasedRuleValue)
        default:
            return false
        }
    }
    
    private func evaluateNumericRule(_ value: Double, condition: SmartPlaylistCriteria.Condition, value ruleValue: String) -> Bool {
        guard let numericRuleValue = Double(ruleValue) else { return false }
        
        switch condition {
        case .equals:
            return value == numericRuleValue
        case .greaterThan:
            return value > numericRuleValue
        case .greaterThanOrEqual:
            return value >= numericRuleValue
        case .lessThan:
            return value < numericRuleValue
        case .lessThanOrEqual:
            return value <= numericRuleValue
        default:
            return false
        }
    }
    
    private func evaluateDateRule(_ value: Date?, condition: SmartPlaylistCriteria.Condition, value ruleValue: String) -> Bool {
        guard let date = value else { return false }
        
        // Handle special case for "Xdays" format (e.g., "7days")
        if ruleValue.hasSuffix("days") {
            let daysString = ruleValue.replacingOccurrences(of: "days", with: "")
            guard let days = Int(daysString) else { return false }
            
            let calendar = Calendar.current
            let cutoffDate = calendar.date(byAdding: .day, value: -days, to: Date()) ?? Date()
            
            switch condition {
            case .greaterThan:
                return date > cutoffDate
            case .lessThan:
                return date < cutoffDate
            default:
                return false
            }
        }
        
        // For other date formats, you can extend this
        return false
    }
    
    // MARK: - Sorting
    
    internal func sortTracks(_ tracks: [Track], by field: String, ascending: Bool) -> [Track] {
        let sorted = tracks.sorted { track1, track2 in
            switch field {
            case "title":
                return track1.title.localizedCaseInsensitiveCompare(track2.title) == .orderedAscending
            case "artist":
                return track1.artist.localizedCaseInsensitiveCompare(track2.artist) == .orderedAscending
            case "album":
                return track1.album.localizedCaseInsensitiveCompare(track2.album) == .orderedAscending
            case "albumArtist":
                let artist1 = track1.albumArtist ?? ""
                let artist2 = track2.albumArtist ?? ""
                return artist1.localizedCaseInsensitiveCompare(artist2) == .orderedAscending
            case "composer":
                return track1.composer.localizedCaseInsensitiveCompare(track2.composer) == .orderedAscending
            case "playCount":
                return track1.playCount < track2.playCount
            case "lastPlayedDate":
                let date1 = track1.lastPlayedDate ?? Date.distantPast
                let date2 = track2.lastPlayedDate ?? Date.distantPast
                return date1 < date2
            case "dateAdded":
                let date1 = track1.dateAdded ?? Date.distantPast
                let date2 = track2.dateAdded ?? Date.distantPast
                return date1 < date2
            case "duration":
                return track1.duration < track2.duration
            default:
                return false
            }
        }
        
        return ascending ? sorted : sorted.reversed()
    }
}
