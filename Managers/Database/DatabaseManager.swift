//
// DatabaseManager class
//
// This class handles all the Database operations done by the app, note that this file only
// contains core methods, the domain-specific logic is spread across extension files within this
// directory where each file is prefixed with `DM`.
//

import Foundation
import GRDB

class DatabaseManager: ObservableObject {
    // MARK: - Properties
    @Published var isScanning: Bool = false
    @Published var scanStatusMessage: String = ""

    let dbQueue: DatabaseQueue
    private let dbPath: String
    private var lastStatusUpdateTime: Date = .distantPast
    private let statusUpdateInterval: TimeInterval = 0.5

    // MARK: - Initialization

    init() throws {
        // Create database in app support directory
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory,
                                                  in: .userDomainMask).first!
        // Use bundle identifier as the folder name
        let bundleID = Bundle.main.bundleIdentifier ?? About.bundleIdentifier
        let appDirectory = appSupport.appendingPathComponent(bundleID, isDirectory: true)

        // Create directory if it doesn't exist
        try FileManager.default.createDirectory(at: appDirectory,
                                                withIntermediateDirectories: true,
                                                attributes: nil)

        let dbFilename = bundleID.hasSuffix(".debug") ? "petrichor-debug.db" : "petrichor.db"
        dbPath = appDirectory.appendingPathComponent(dbFilename).path

        // Configure database before creating the queue
        var config = Configuration()
        config.prepareDatabase { db in
            // Set journal mode to WAL
            try db.execute(sql: "PRAGMA journal_mode = WAL")
            // Enable synchronous mode for better durability
            try db.execute(sql: "PRAGMA synchronous = NORMAL")
            // Set a reasonable busy timeout
            try db.execute(sql: "PRAGMA busy_timeout = 5000")
        }

        // Initialize database queue with configuration
        dbQueue = try DatabaseQueue(path: dbPath, configuration: config)

        // Use migration system for both new and existing databases
        try DatabaseMigrator.migrate(dbQueue)
    }

    // MARK: - Database Maintenance

    func checkpoint() {
        do {
            try dbQueue.writeWithoutTransaction { db in
                try db.execute(sql: "PRAGMA wal_checkpoint(TRUNCATE)")
            }
            Logger.info("WAL checkpoint completed")
        } catch {
            Logger.error("WAL checkpoint failed: \(error)")
        }
    }

    // MARK: - Migration Status
    
    /// Check if database needs migration
    func needsMigration() -> Bool {
        DatabaseMigrator.hasUnappliedMigrations(dbQueue)
    }
    
    /// Get list of applied migrations
    func getAppliedMigrations() -> [String] {
        DatabaseMigrator.appliedMigrations(dbQueue)
    }

    // MARK: - Helper Methods
    
    internal func updateScanStatus(_ message: String) {
        let now = Date()
        guard now.timeIntervalSince(lastStatusUpdateTime) >= statusUpdateInterval else { return }
        lastStatusUpdateTime = now
        
        Task { @MainActor in
            self.scanStatusMessage = message
        }
    }

    /// Clean up database file and recreate schema
    /// Warning: This will delete all data!
    func resetDatabase() throws {
        Task { @MainActor in
            self.isScanning = false
            self.scanStatusMessage = ""
        }
        
        // Erase the database
        try dbQueue.erase()
        
        // Re-run migrations on the fresh database
        try DatabaseMigrator.migrate(dbQueue)
        
        Logger.info("Database reset completed")
    }
    
    /// Get database file size in bytes
    func getDatabaseSize() -> Int64? {
        let fileManager = FileManager.default
        do {
            let attributes = try fileManager.attributesOfItem(atPath: dbPath)
            return attributes[.size] as? Int64
        } catch {
            Logger.error("Failed to get database size: \(error)")
            return nil
        }
    }
    
    /// Vacuum the database to reclaim space
    func vacuumDatabase() async throws {
        try await dbQueue.writeWithoutTransaction { db in
            try db.execute(sql: "VACUUM")
        }
        Logger.info("Database vacuum completed")
    }
    
    /// Analyze the database to update statistics
    func analyzeDatabase() async throws {
        try await dbQueue.writeWithoutTransaction { db in
            try db.execute(sql: "ANALYZE")
        }
        Logger.info("Database analyze completed")
    }
}

// MARK: - Local Enums

enum TrackProcessResult {
    case new(FullTrack, TrackMetadata)
    case update(FullTrack, TrackMetadata)
    case skipped
}

enum DatabaseError: Error {
    case invalidTrackId
    case invalidFolderId
    case updateFailed
    case migrationFailed(String)
    case scanFailed(String)
    
    var localizedDescription: String {
        switch self {
        case .invalidTrackId:
            return "Invalid track ID"
        case .invalidFolderId:
            return "Invalid folder ID"
        case .updateFailed:
            return "Failed to update database"
        case .migrationFailed(let message):
            return "Migration failed: \(message)"
        case .scanFailed(let message):
            return "Scan failed: \(message)"
        }
    }
}

// MARK: - Array Extension

extension Array {
    func chunked(into size: Int) -> [[Element]] {
        stride(from: 0, to: count, by: size).map {
            Array(self[$0 ..< Swift.min($0 + size, count)])
        }
    }
}

extension Array where Element: Hashable {
    func removingDuplicates() -> [Element] {
        var seen = Set<Element>()
        return self.filter { element in
            guard !seen.contains(element) else { return false }
            seen.insert(element)
            return true
        }
    }
}
