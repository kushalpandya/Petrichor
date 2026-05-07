import Foundation

enum DiagnosticSnapshot {
    /// Writes a single-entry snapshot of the current user settings, library
    /// statistics, app/OS info, and device hardware to the log file as
    /// pretty-printed JSON. Emitted at launch and termination so users can
    /// share the log for diagnosis. Always written regardless of the
    /// configured log level.
    static func write(phase: String) {
        let defaults = UserDefaults.standard
        var payload: [String: Any] = [
            "phase": phase,
            "uniqueId": uniqueInstallationId(),
            "app": [
                "name": AppInfo.name,
                "version": AppInfo.versionWithBuild,
                "bundleId": AppInfo.bundleIdentifier,
                "build": AppInfo.isDebugBuild ? "debug" : "release"
            ]
        ]

        var device: [String: Any] = [
            "os": ProcessInfo.processInfo.operatingSystemVersionString,
            "model": sysctlString("hw.model") ?? NSNull(),
            "arch": sysctlString("hw.machine") ?? NSNull(),
            "processor": sysctlString("machdep.cpu.brand_string") ?? NSNull(),
            "physicalCores": sysctlInt32("hw.physicalcpu") ?? NSNull(),
            "logicalCores": sysctlInt32("hw.logicalcpu") ?? NSNull(),
            "memory": bytes(Int64(clamping: ProcessInfo.processInfo.physicalMemory), style: .memory)
        ]
        if let vals = try? URL(fileURLWithPath: "/").resourceValues(
            forKeys: [.volumeTotalCapacityKey, .volumeAvailableCapacityKey]
        ) {
            if let total = vals.volumeTotalCapacity {
                device["storageTotal"] = bytes(Int64(total))
            }
            if let avail = vals.volumeAvailableCapacity {
                device["storageAvailable"] = bytes(Int64(avail))
            }
        }
        payload["device"] = device

        var library: [String: Any] = [:]
        if let coordinator = AppCoordinator.shared {
            let lm = coordinator.libraryManager
            let db = lm.databaseManager
            let duration = db.getTotalDuration()
            library["folderCount"] = lm.folders.count
            library["trackCount"] = lm.totalTrackCount
            library["artistCount"] = lm.artistCount
            library["albumCount"] = lm.albumCount
            library["playlistCount"] = coordinator.playlistManager.playlists.count
            library["pinnedItemCount"] = lm.pinnedItems.count
            library["totalDurationSec"] = duration.isFinite ? Int(duration) : 0
            library["totalSize"] = bytes(db.getTotalFileSize())
            library["formats"] = db.getTrackCountsByFormat()
            library["folders"] = lm.folders.map { ($0.url.path as NSString).abbreviatingWithTildeInPath }
        } else {
            library["available"] = false
        }
        if let lastScan = defaults.object(forKey: "LastScanDate") as? Date {
            library["lastScanDate"] = ISO8601DateFormatter().string(from: lastScan)
        } else {
            library["lastScanDate"] = NSNull()
        }
        payload["library"] = library

        payload["settings"] = [
            "general": [
                "closeToMenubar": defaults.boolOrNull("closeToMenubar"),
                "startAtLogin": defaults.boolOrNull("startAtLogin"),
                "hideDuplicateTracks": defaults.boolOrNull("hideDuplicateTracks"),
                "automaticUpdatesEnabled": defaults.boolOrNull("automaticUpdatesEnabled"),
                "colorMode": defaults.stringOrNull("colorMode"),
                "showFoldersTab": defaults.boolOrNull("showFoldersTab"),
                "useArtworkColors": defaults.boolOrNull("useArtworkColors")
            ],
            "library": [
                "autoScanInterval": defaults.stringOrNull("autoScanInterval"),
                "discoverUpdateInterval": defaults.stringOrNull("discoverUpdateInterval"),
                "discoverTrackCount": defaults.intOrNull("discoverTrackCount")
            ],
            "online": [
                "lastfmUsername": defaults.string(forKey: "lastfmUsername") != nil ? "<set>" : "<unset>",
                "scrobblingEnabled": defaults.boolOrNull("scrobblingEnabled"),
                "loveSyncEnabled": defaults.boolOrNull("loveSyncEnabled"),
                "onlineLyricsEnabled": defaults.boolOrNull("onlineLyricsEnabled"),
                "artistInfoFetchEnabled": defaults.boolOrNull("artistInfoFetchEnabled")
            ]
        ]

        var equalizer: [String: Any] = [
            "eqEnabled": defaults.boolOrNull("eqEnabled"),
            "eqPreset": defaults.stringOrNull("eqPreset"),
            "preampGain": defaults.doubleOrNull("preampGain"),
            "stereoWideningEnabled": defaults.boolOrNull("stereoWideningEnabled")
        ]
        if let gains = defaults.array(forKey: "customEQGains") as? [Float] {
            equalizer["customEQGains"] = gains.map { Double($0) }
        }
        payload["equalizer"] = equalizer

        payload["others"] = [
            "librarySelectedFilterType": defaults.stringOrNull("librarySelectedFilterType"),
            "albumSortBy": defaults.stringOrNull("albumSortBy"),
            "trackTableRowSize": defaults.stringOrNull("trackTableRowSize"),
            "entitySortAscending": defaults.boolOrNull("entitySortAscending"),
            "playlistSortAscending": defaults.boolOrNull("playlistSortAscending"),
            "playlistSortFields": defaults.stringOrNull("playlistSortFields"),
            "trackColumns": trackColumns(from: defaults)
        ]

        Logger.diagnostic(header: "DIAGNOSTIC SNAPSHOT (\(phase))", body: serialize(payload))
    }

    private static func bytes(_ count: Int64, style: ByteCountFormatter.CountStyle = .file) -> String {
        ByteCountFormatter.string(fromByteCount: count, countStyle: style)
    }

    private static func serialize(_ payload: [String: Any]) -> String {
        do {
            let data = try JSONSerialization.data(
                withJSONObject: payload,
                options: [.prettyPrinted, .sortedKeys]
            )
            return String(data: data, encoding: .utf8) ?? "{}"
        } catch {
            return "{\"error\": \"failed to serialize diagnostic snapshot: \(error)\"}"
        }
    }

    private static func sysctlString(_ name: String) -> String? {
        var size = 0
        guard sysctlbyname(name, nil, &size, nil, 0) == 0, size > 0 else { return nil }
        var buffer = [CChar](repeating: 0, count: size)
        guard sysctlbyname(name, &buffer, &size, nil, 0) == 0 else { return nil }
        return String(cString: buffer)
    }

    private static func sysctlInt32(_ name: String) -> Int? {
        var value: Int32 = 0
        var size = MemoryLayout<Int32>.size
        return sysctlbyname(name, &value, &size, nil, 0) == 0 ? Int(value) : nil
    }

    /// Default visible track-table columns in their default arrangement.
    /// Mirrors `TrackTableView`'s `.defaultVisibility(.visible)` columns in
    /// declaration order. Keep in sync if columns are added/reordered there.
    private static let defaultTrackColumns: [String] = [
        "title", "artist", "album", "year", "duration"
    ]

    /// Extracts the user's track table column setup from SwiftUI's
    /// `TableColumnCustomization` blob. Returns visible columns; hidden
    /// columns are omitted. Falls back to the defaults when the user has
    /// not customized columns yet.
    ///
    /// Note: array order reflects SwiftUI's internal customization storage
    /// (roughly the order columns were last touched), not the visual
    /// left-to-right order in the UI. SwiftUI does not expose visual
    /// column order through any public API on macOS 14/15. Treat this as
    /// a visibility report only.
    private static func trackColumns(from defaults: UserDefaults) -> [String] {
        guard let data = defaults.data(forKey: "trackTableColumnCustomizationData"),
              !data.isEmpty,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let perColumnState = json["perColumnState"] as? [[String: Any]],
              !perColumnState.isEmpty else {
            return defaultTrackColumns
        }

        var result: [String] = []
        var pendingId: String?

        for entry in perColumnState {
            if let base = entry["base"] as? [String: Any],
               let explicit = base["explicit"] as? [String: Any],
               let id = explicit["_0"] as? String {
                pendingId = id
            } else if let id = pendingId {
                let visibility = entry["visibility"] as? [String: Any]
                let isHidden = visibility?["hidden"] != nil
                if !isHidden {
                    result.append(id)
                }
                pendingId = nil
            }
        }

        return result.isEmpty ? defaultTrackColumns : result
    }

    /// Returns a stable, anonymous identifier for this installation.
    /// Generated as a random UUID on first call and persisted in UserDefaults.
    /// Survives app updates but resets on app data wipe or reinstall — which
    /// is the correct semantics for "this specific installation". Contains no
    /// hardware identifiers or user-derived data.
    private static func uniqueInstallationId() -> String {
        let key = "diagnosticUniqueId"
        let defaults = UserDefaults.standard
        if let existing = defaults.string(forKey: key), !existing.isEmpty {
            return existing
        }
        let new = UUID().uuidString
        defaults.set(new, forKey: key)
        return new
    }
}

private extension UserDefaults {
    func boolOrNull(_ key: String) -> Any {
        object(forKey: key) != nil ? bool(forKey: key) : NSNull()
    }
    func stringOrNull(_ key: String) -> Any {
        string(forKey: key) ?? NSNull()
    }
    func intOrNull(_ key: String) -> Any {
        object(forKey: key) != nil ? integer(forKey: key) : NSNull()
    }
    func doubleOrNull(_ key: String) -> Any {
        object(forKey: key) != nil ? double(forKey: key) : NSNull()
    }
}
