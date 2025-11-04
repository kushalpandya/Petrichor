//
// DatabaseManager class extension
//
// This extension contains methods for setting up database schema and seed initial data.
// Updated to use migration helpers and static methods.
//

import Foundation
import GRDB

extension DatabaseManager {
    // MARK: - Main Setup Method (Static)
    static func setupDatabaseSchema(in db: Database) throws {
        // Create tables in dependency order
        try createFoldersTable(in: db)
        try createArtistsTable(in: db)
        try createAlbumsTable(in: db)
        try createAlbumArtistsTable(in: db)
        try createGenresTable(in: db)
        try createTracksTable(in: db)
        try createPlaylistsTable(in: db)
        try createPlaylistTracksTable(in: db)
        try createTrackArtistsTable(in: db)
        try createTrackGenresTable(in: db)
        try createPinnedItemsTable(in: db)

        // Create all indices
        try createIndices(in: db)
        
        // Create FTS5 search index
        try createFTSTable(in: db)
        
        // Seed default data
        try seedDefaultPlaylists(in: db)
        try seedDefaultPinnedItems(in: db)
        
        Logger.info("Database schema setup completed")
    }
    
    // MARK: - Folders Table
    static func createFoldersTable(in db: Database) throws {
        try db.createTableIfNotExists("folders") { t in
            t.autoIncrementedPrimaryKey("id")
            t.column("name", .text).notNull()
            t.column("path", .text).notNull().unique()
            t.column("track_count", .integer).notNull().defaults(to: 0)
            t.column("date_added", .datetime).notNull()
            t.column("date_updated", .datetime).notNull()
            t.column("bookmark_data", .blob)
        }
        Logger.info("Created `folders` table")
    }

    // MARK: - Artists Table
    static func createArtistsTable(in db: Database) throws {
        try db.createTableIfNotExists("artists") { t in
            t.autoIncrementedPrimaryKey("id")
            t.column("name", .text).notNull()
            t.column("normalized_name", .text).notNull()
            t.column("sort_name", .text)
            t.column("artwork_data", .blob)

            // External API metadata
            t.column("bio", .text)
            t.column("bio_source", .text)
            t.column("bio_updated_at", .datetime)
            t.column("image_url", .text)
            t.column("image_source", .text)
            t.column("image_updated_at", .datetime)

            // External identifiers
            t.column("discogs_id", .text)
            t.column("musicbrainz_id", .text)
            t.column("spotify_id", .text)
            t.column("apple_music_id", .text)

            // Additional metadata
            t.column("country", .text)
            t.column("formed_year", .integer)
            t.column("disbanded_year", .integer)
            t.column("genres", .text) // JSON array
            t.column("websites", .text) // JSON array
            t.column("members", .text) // JSON array

            // Stats
            t.column("total_tracks", .integer).notNull().defaults(to: 0).check { $0 >= 0 }
            t.column("total_albums", .integer).notNull().defaults(to: 0).check { $0 >= 0 }

            t.column("created_at", .datetime).notNull()
            t.column("updated_at", .datetime).notNull()
        }
        Logger.info("Created `artists` table")
    }

    // MARK: - Albums Table
    static func createAlbumsTable(in db: Database) throws {
        try db.createTableIfNotExists("albums") { t in
            t.autoIncrementedPrimaryKey("id")
            t.column("title", .text).notNull()
            t.column("normalized_title", .text).notNull()
            t.column("sort_title", .text)
            t.column("artwork_data", .blob)

            // Album metadata
            t.column("release_date", .text)
            t.column("release_year", .integer).check { $0 == nil || ($0 >= 1900 && $0 <= 2100) }
            t.column("album_type", .text)
            t.column("total_tracks", .integer).check { $0 == nil || $0 >= 0 }
            t.column("total_discs", .integer).check { $0 == nil || $0 >= 0 }

            // External API metadata
            t.column("description", .text)
            t.column("review", .text)
            t.column("review_source", .text)
            t.column("cover_art_url", .text)
            t.column("thumbnail_url", .text)

            // External identifiers
            t.column("discogs_id", .text)
            t.column("musicbrainz_id", .text)
            t.column("spotify_id", .text)
            t.column("apple_music_id", .text)

            // Additional metadata
            t.column("label", .text)
            t.column("catalog_number", .text)
            t.column("barcode", .text)
            t.column("genres", .text) // JSON array

            t.column("created_at", .datetime).notNull()
            t.column("updated_at", .datetime).notNull()
        }
        Logger.info("Created `albums` table")
    }
    
    // MARK: - Album Artists Junction Table
    static func createAlbumArtistsTable(in db: Database) throws {
        try db.createTableIfNotExists("album_artists") { t in
            t.column("album_id", .integer).notNull().references("albums", onDelete: .cascade)
            t.column("artist_id", .integer).notNull().references("artists", onDelete: .cascade)
            t.column("role", .text).notNull().defaults(to: "primary")
            t.column("position", .integer).notNull().defaults(to: 0)
            t.primaryKey(["album_id", "artist_id", "role"])
        }
        Logger.info("Created `album_artists` table")
    }

    // MARK: - Genres Table
    static func createGenresTable(in db: Database) throws {
        try db.createTableIfNotExists("genres") { t in
            t.autoIncrementedPrimaryKey("id")
            t.column("name", .text).notNull().unique()
        }
        Logger.info("Created `genres` table")
    }

    // MARK: - Tracks Table
    static func createTracksTable(in db: Database) throws {
        try db.createTableIfNotExists("tracks") { t in
            t.autoIncrementedPrimaryKey("id")
            t.column("folder_id", .integer).notNull().references("folders", onDelete: .cascade)
            t.column("album_id", .integer).references("albums", onDelete: .setNull)
            t.column("path", .text).notNull().unique()
            t.column("filename", .text).notNull()
            t.column("title", .text)
            t.column("artist", .text)
            t.column("album", .text)
            t.column("composer", .text)
            t.column("genre", .text)
            t.column("year", .text)
            t.column("duration", .double).check { $0 >= 0 }
            t.column("format", .text)
            t.column("file_size", .integer)
            t.column("date_added", .datetime).notNull()
            t.column("date_modified", .datetime)
            t.column("track_artwork_data", .blob)
            t.column("is_favorite", .boolean).notNull().defaults(to: false)
            t.column("play_count", .integer).notNull().defaults(to: 0)
            t.column("last_played_date", .datetime)
            
            // Duplicate tracking
            t.column("is_duplicate", .boolean).notNull().defaults(to: false)
            t.column("primary_track_id", .integer).references("tracks", column: "id", onDelete: .setNull)
            t.column("duplicate_group_id", .text)

            // Additional metadata
            t.column("album_artist", .text)
            t.column("track_number", .integer)
            t.column("total_tracks", .integer)
            t.column("disc_number", .integer)
            t.column("total_discs", .integer)
            t.column("rating", .integer).check { $0 == nil || ($0 >= 0 && $0 <= 5) }
            t.column("compilation", .boolean).defaults(to: false)
            t.column("release_date", .text)
            t.column("original_release_date", .text)
            t.column("bpm", .integer)
            t.column("media_type", .text)

            // Audio properties
            t.column("bitrate", .integer).check { $0 == nil || $0 > 0 }
            t.column("sample_rate", .integer)
            t.column("channels", .integer)
            t.column("codec", .text)
            t.column("bit_depth", .integer)

            // Sort fields
            t.column("sort_title", .text)
            t.column("sort_artist", .text)
            t.column("sort_album", .text)
            t.column("sort_album_artist", .text)

            // Extended metadata as JSON
            t.column("extended_metadata", .text)
        }
        Logger.info("Created `tracks` table")
    }

    // MARK: - Playlists Table
    static func createPlaylistsTable(in db: Database) throws {
        try db.createTableIfNotExists("playlists") { t in
            t.column("id", .text).primaryKey()
            t.column("name", .text).notNull()
            t.column("type", .text).notNull()
            t.column("is_user_editable", .boolean).notNull()
            t.column("is_content_editable", .boolean).notNull()
            t.column("date_created", .datetime).notNull()
            t.column("date_modified", .datetime).notNull()
            t.column("cover_artwork_data", .blob)
            t.column("smart_criteria", .text)
            t.column("sort_order", .integer).notNull().defaults(to: 0)
        }
        Logger.info("Created `playlists` table")
    }

    // MARK: - Playlist Tracks Table
    static func createPlaylistTracksTable(in db: Database) throws {
        try db.createTableIfNotExists("playlist_tracks") { t in
            t.column("playlist_id", .text).notNull().references("playlists", column: "id", onDelete: .cascade)
            t.column("track_id", .integer).notNull().references("tracks", column: "id", onDelete: .cascade)
            t.column("position", .integer).notNull()
            t.column("date_added", .datetime).notNull()
            t.primaryKey(["playlist_id", "track_id"])
        }
        Logger.info("Created `playlist_tracks` table")
    }

    // MARK: - Track Artists Junction Table
    static func createTrackArtistsTable(in db: Database) throws {
        try db.createTableIfNotExists("track_artists") { t in
            t.column("track_id", .integer).notNull().references("tracks", onDelete: .cascade)
            t.column("artist_id", .integer).notNull().references("artists", onDelete: .cascade)
            t.column("role", .text).notNull().defaults(to: "artist")
            t.column("position", .integer).notNull().defaults(to: 0)
            t.primaryKey(["track_id", "artist_id", "role"])
        }
        Logger.info("Created `track_artists` table")
    }

    // MARK: - Track Genres Junction Table
    static func createTrackGenresTable(in db: Database) throws {
        try db.createTableIfNotExists("track_genres") { t in
            t.column("track_id", .integer).notNull().references("tracks", onDelete: .cascade)
            t.column("genre_id", .integer).notNull().references("genres", onDelete: .cascade)
            t.primaryKey(["track_id", "genre_id"])
        }
        Logger.info("Created `track_genres` table")
    }
    
    // MARK: - Pinned Items Table
    static func createPinnedItemsTable(in db: Database) throws {
        try db.createTableIfNotExists("pinned_items") { t in
            t.autoIncrementedPrimaryKey("id")
            t.column("item_type", .text).notNull() // "library" or "playlist"
            t.column("filter_type", .text) // For library items: artists, albums, etc.
            t.column("filter_value", .text) // The specific artist/album name
            t.column("entity_id", .text) // UUID for entities (optional)
            t.column("artist_id", .integer) // Database ID for artist (optional)
            t.column("album_id", .integer) // Database ID for album (optional)
            t.column("playlist_id", .text) // For playlist items
            t.column("display_name", .text).notNull()
            t.column("subtitle", .text) // For albums, shows artist name
            t.column("icon_name", .text).notNull()
            t.column("sort_order", .integer).notNull().defaults(to: 0)
            t.column("date_added", .datetime).notNull()
        }
        Logger.info("Created `pinned_items` table")
    }
    
    // MARK: - FTS5 Search Table
    static func createFTSTable(in db: Database) throws {
        // Create FTS5 virtual table for tracks
        try db.create(virtualTable: "tracks_fts", ifNotExists: true, using: FTS5()) { t in
            t.column("track_id").notIndexed()
            t.column("title")
            t.column("artist")
            t.column("album")
            t.column("album_artist")
            t.column("composer")
            t.column("genre")
            t.column("year")
            
            t.tokenizer = .unicode61()
        }
        
        // Create triggers to keep FTS index in sync
        try createFTSTriggers(in: db)
        
        // Populate FTS table with existing data (it checks internally if needed)
        try populateFTSTable(in: db)
        
        Logger.info("Created FTS5 `tracks_fts` table")
    }

    // MARK: - FTS5 Triggers
    private static func createFTSTriggers(in db: Database) throws {
        // Trigger for new tracks
        try db.execute(sql: """
            CREATE TRIGGER IF NOT EXISTS tracks_fts_insert
            AFTER INSERT ON tracks
            BEGIN
                INSERT INTO tracks_fts(
                    rowid, track_id, title, artist, album, album_artist, composer, genre, year
                ) VALUES (
                    NEW.id, NEW.id, NEW.title, NEW.artist, NEW.album, NEW.album_artist, NEW.composer, NEW.genre, NEW.year
                );
            END
        """)
        
        // Trigger for updated tracks
        try db.execute(sql: """
            CREATE TRIGGER IF NOT EXISTS tracks_fts_update
            AFTER UPDATE ON tracks
            BEGIN
                UPDATE tracks_fts SET
                    title = NEW.title,
                    artist = NEW.artist,
                    album = NEW.album,
                    album_artist = NEW.album_artist,
                    composer = NEW.composer,
                    genre = NEW.genre,
                    year = NEW.year
                WHERE rowid = NEW.id;
            END
        """)
        
        // Trigger for deleted tracks
        try db.execute(sql: """
            CREATE TRIGGER IF NOT EXISTS tracks_fts_delete
            AFTER DELETE ON tracks
            BEGIN
                DELETE FROM tracks_fts WHERE rowid = OLD.id;
            END
        """)
        
        Logger.info("Created FTS5 `tracks_fts` triggers")
    }

    // MARK: - Populate FTS Table
    private static func populateFTSTable(in db: Database) throws {
        // Check if FTS table already has data
        let ftsCount = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM tracks_fts") ?? 0
        
        if ftsCount > 0 {
            Logger.info("FTS table already populated with \(ftsCount) entries, skipping population")
            return
        }
        
        // Only populate if empty
        try db.execute(sql: """
            INSERT INTO tracks_fts(
                rowid, track_id, title, artist, album, album_artist, composer, genre, year
            )
            SELECT
                id, id, title, artist, album, album_artist, composer, genre, year
            FROM tracks
        """)
        
        Logger.info("Populated FTS5 `tracks_fts` table with tracks")
    }

    // MARK: - Create All Indices
    static func createIndices(in db: Database) throws {
        // Tracks table indices
        try db.createIndexIfNotExists(name: "idx_tracks_folder_id", table: "tracks", columns: ["folder_id"])
        try db.createIndexIfNotExists(name: "idx_tracks_album_id", table: "tracks", columns: ["album_id"])
        try db.createIndexIfNotExists(name: "idx_tracks_artist", table: "tracks", columns: ["artist"])
        try db.createIndexIfNotExists(name: "idx_tracks_album", table: "tracks", columns: ["album"])
        try db.createIndexIfNotExists(name: "idx_tracks_composer", table: "tracks", columns: ["composer"])
        try db.createIndexIfNotExists(name: "idx_tracks_genre", table: "tracks", columns: ["genre"])
        try db.createIndexIfNotExists(name: "idx_tracks_year", table: "tracks", columns: ["year"])
        try db.createIndexIfNotExists(name: "idx_tracks_album_artist", table: "tracks", columns: ["album_artist"])
        try db.createIndexIfNotExists(name: "idx_tracks_is_favorite", table: "tracks", columns: ["is_favorite"])
        try db.createIndexIfNotExists(name: "idx_tracks_rating", table: "tracks", columns: ["rating"])
        try db.createIndexIfNotExists(name: "idx_tracks_compilation", table: "tracks", columns: ["compilation"])
        try db.createIndexIfNotExists(name: "idx_tracks_media_type", table: "tracks", columns: ["media_type"])
        
        // Duplicate tracking indices
        try db.createIndexIfNotExists(name: "idx_tracks_primary_track_id", table: "tracks", columns: ["primary_track_id"])
        try db.createIndexIfNotExists(name: "idx_tracks_is_duplicate", table: "tracks", columns: ["is_duplicate"])
        try db.createIndexIfNotExists(name: "idx_tracks_duplicate_group_id", table: "tracks", columns: ["duplicate_group_id"])
        
        // Composite indices for duplicate-aware category queries
        try db.createIndexIfNotExists(name: "idx_tracks_duplicate_artist", table: "tracks", columns: ["is_duplicate", "artist"])
        try db.createIndexIfNotExists(name: "idx_tracks_duplicate_album_artist", table: "tracks", columns: ["is_duplicate", "album_artist"])
        try db.createIndexIfNotExists(name: "idx_tracks_duplicate_composer", table: "tracks", columns: ["is_duplicate", "composer"])
        try db.createIndexIfNotExists(name: "idx_tracks_duplicate_genre", table: "tracks", columns: ["is_duplicate", "genre"])
        try db.createIndexIfNotExists(name: "idx_tracks_duplicate_year", table: "tracks", columns: ["is_duplicate", "year"])
        try db.createIndexIfNotExists(name: "idx_tracks_album_id_duplicate", table: "tracks", columns: ["album_id", "is_duplicate", "disc_number", "track_number"])
        try db.createIndexIfNotExists(name: "idx_tracks_album_name_artist", table: "tracks", columns: ["album", "album_artist", "is_duplicate", "disc_number", "track_number"])

        // Artists table indices
        try db.createIndexIfNotExists(name: "idx_artists_normalized_name_unique", table: "artists", columns: ["normalized_name"], unique: true)
        try db.createIndexIfNotExists(name: "idx_artists_name_normalized", table: "artists", columns: ["name", "normalized_name"])

        // Albums table indices
        try db.createIndexIfNotExists(name: "idx_albums_title_year", table: "albums", columns: ["normalized_title", "release_year"])
        try db.createIndexIfNotExists(name: "idx_albums_normalized_title", table: "albums", columns: ["normalized_title"])
        try db.createIndexIfNotExists(name: "idx_albums_release_year", table: "albums", columns: ["release_year"])
                
        // Album artists junction table indices
        try db.createIndexIfNotExists(name: "idx_album_artists_album_id", table: "album_artists", columns: ["album_id"])
        try db.createIndexIfNotExists(name: "idx_album_artists_artist_id", table: "album_artists", columns: ["artist_id"])
        
        // Composite index for primary artist lookups
        try db.createIndexIfNotExists(name: "idx_album_artists_primary", table: "album_artists", columns: ["role", "position", "album_id", "artist_id"])

        // Playlist tracks index
        try db.createIndexIfNotExists(name: "idx_playlist_tracks_playlist_id", table: "playlist_tracks", columns: ["playlist_id"])

        // Junction table indices
        try db.createIndexIfNotExists(name: "idx_track_artists_artist_id", table: "track_artists", columns: ["artist_id"])
        try db.createIndexIfNotExists(name: "idx_track_artists_track_id", table: "track_artists", columns: ["track_id"])
        
        // Composite index for role-based queries
        try db.createIndexIfNotExists(name: "idx_track_artists_role_artist", table: "track_artists", columns: ["role", "artist_id", "track_id"])
        
        try db.createIndexIfNotExists(name: "idx_track_genres_genre_id", table: "track_genres", columns: ["genre_id"])
        
        // Pinned items indices
        try db.createIndexIfNotExists(name: "idx_pinned_items_sort_order", table: "pinned_items", columns: ["sort_order"])
        try db.createIndexIfNotExists(name: "idx_pinned_items_item_type", table: "pinned_items", columns: ["item_type"])
        
        Logger.info("Created column indices")
    }
    
    // MARK: - Seed Default Playlists
    static func seedDefaultPlaylists(in db: Database) throws {
        // Check if playlists table is empty (first time setup)
        let playlistCount = try Playlist.fetchCount(db)
        
        if playlistCount == 0 {
            Logger.info("Seeding default smart playlists")
            
            let defaultPlaylists = Playlist.createDefaultSmartPlaylists()
            
            for playlist in defaultPlaylists {
                try playlist.insert(db)
                Logger.info("Created default smart playlist: \(playlist.name)")
            }
        }
    }
    
    // MARK: - Seed Default Pinned Items
    static func seedDefaultPinnedItems(in db: Database) throws {
        // Check if pinned_items table is empty (first time setup)
        let pinnedCount = try PinnedItem.fetchCount(db)
        
        if pinnedCount == 0 {
            Logger.info("Seeding default pinned items")
            
            // Get the default playlists that were just created
            let favoritesPlaylist = try Playlist
                .filter(Playlist.Columns.name == DefaultPlaylists.favorites)
                .fetchOne(db)
            
            let mostPlayedPlaylist = try Playlist
                .filter(Playlist.Columns.name == DefaultPlaylists.mostPlayed)
                .fetchOne(db)
            
            // Create pinned items for these playlists
            if let favorites = favoritesPlaylist {
                let pinnedFavorites = PinnedItem(playlist: favorites)
                var savedItem = pinnedFavorites
                savedItem.sortOrder = 0
                try savedItem.insert(db)
                Logger.info("Pinned default playlist: \(favorites.name)")
            }
            
            if let mostPlayed = mostPlayedPlaylist {
                let pinnedMostPlayed = PinnedItem(playlist: mostPlayed)
                var savedItem = pinnedMostPlayed
                savedItem.sortOrder = 1
                try savedItem.insert(db)
                Logger.info("Pinned default playlist: \(mostPlayed.name)")
            }
        }
    }
    
    // MARK: - Instance Methods
    func setupDatabase() throws {
        try dbQueue.write { db in
            try DatabaseManager.setupDatabaseSchema(in: db)
        }
    }
}
