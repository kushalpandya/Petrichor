//
// DatabaseManager class extension
//
// This extension contains background migration logic for heavy one-time data transformations
// that run asynchronously after app launch without blocking the UI.
//

import Foundation
import GRDB

extension DatabaseManager {
    func runPendingBackgroundMigrations() async {
        let pending: [(identifier: String, progress: String?)]
        do {
            pending = try await dbQueue.read { db -> [(String, String?)] in
                if try db.tableExists("background_migrations") {
                    return try Row.fetchAll(db, sql: "SELECT identifier, progress FROM background_migrations WHERE completed_at IS NULL ORDER BY identifier")
                        .map { ($0["identifier"], $0["progress"]) }
                }
                return []
            }
        } catch {
            Logger.error("Failed to read pending background migrations: \(error)")
            return
        }
        if pending.isEmpty { return }

        for (identifier, progress) in pending {
            switch identifier {
            default:
                Logger.warning("Unknown background migration: \(identifier)")
            }
        }
    }

    // MARK: - Migration State

    func isActiveBackgroundMigrationResumable() -> Bool {
        do {
            return try dbQueue.read { db -> Bool in
                if try db.tableExists("background_migrations") {
                    return try Bool.fetchOne(db,
                        sql: "SELECT resumable FROM background_migrations WHERE completed_at IS NULL LIMIT 1"
                    ) ?? true
                }
                return true
            }
        } catch {
            return true
        }
    }

    // MARK: - Helpers

    func updateMigrationProgress(_ identifier: String, progress: String) {
        do {
            try dbQueue.write { db in
                try db.execute(
                    sql: "UPDATE background_migrations SET progress = ? WHERE identifier = ?",
                    arguments: [progress, identifier]
                )
            }
        } catch {
            Logger.error("Failed to update migration progress for \(identifier): \(error)")
        }
    }

    func completeBackgroundMigration(_ identifier: String) {
        do {
            try dbQueue.write { db in
                try db.execute(
                    sql: "UPDATE background_migrations SET completed_at = ?, progress = NULL WHERE identifier = ?",
                    arguments: [Date(), identifier]
                )
            }
        } catch {
            Logger.error("Failed to mark migration \(identifier) as completed: \(error)")
        }
    }
}
