//
// DatabaseManager class extension
//
// This extension contains methods for updating individual tracks based on user
// interaction events like marking as favorite, play count, last played, etc.
//

import Foundation
import GRDB
import SFBAudioEngine

extension DatabaseManager {
    // Updates a track's favorite status
    func updateTrackFavoriteStatus(trackId: Int64, isFavorite: Bool) async throws {
        _ = try await dbQueue.write { db in
            try Track
                .filter(Track.Columns.trackId == trackId)
                .updateAll(db, Track.Columns.isFavorite.set(to: isFavorite))
        }
    }

    // Updates a track's play count and last played date
    func updatePlayingTrackMetadata(trackId: Int64, playCount: Int, lastPlayedDate: Date) async throws {
        _ = try await dbQueue.write { db in
            try Track
                .filter(Track.Columns.trackId == trackId)
                .updateAll(
                    db,
                    Track.Columns.playCount.set(to: playCount),
                    Track.Columns.lastPlayedDate.set(to: lastPlayedDate)
                )
        }
    }

    /// Batch update for track properties
    func updateTrack(_ track: Track) async throws {
        guard track.trackId != nil else {
            throw DatabaseError.invalidTrackId
        }

        try await dbQueue.write { db in
            try track.update(db)
        }
    }
    
    /// Updates a track's lyrics in extended_metadata
    func updateTrackLyrics(for fullTrack: FullTrack, lyrics: String) async throws {
        guard fullTrack.trackId != nil else {
            throw DatabaseError.invalidTrackId
        }
        
        var updatedTrack = fullTrack
        var extendedMetadata = updatedTrack.extendedMetadata ?? ExtendedMetadata()
        extendedMetadata.lyrics = lyrics
        updatedTrack.extendedMetadata = extendedMetadata
        
        let trackToSave = updatedTrack
        try await dbQueue.write { db in
            try trackToSave.update(db)
        }
    }
}
