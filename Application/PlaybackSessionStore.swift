import Foundation

final class PlaybackSessionStore {
    private let fileURL: URL?
    private let queue = DispatchQueue(label: "org.petrichor.playback-session", qos: .utility)

    init() {
        do {
            let root = try FileManager.default.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            )
            let directory = root.appendingPathComponent(AppInfo.bundleIdentifier, isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            fileURL = directory.appendingPathComponent("playback-session.plist")
            // Retire the former UserDefaults persistence, including its artwork blob.
            for key in ["SavedPlaybackState", "SavedPlaybackUIState", "SavedRadioStationId", "SavedRadioStationState"] {
                UserDefaults.standard.removeObject(forKey: key)
            }
        } catch {
            fileURL = nil
            Logger.error("Failed to prepare playback session storage: \(error)")
        }
    }

    func load() -> PlaybackSession? {
        guard let fileURL, let data = try? Data(contentsOf: fileURL) else { return nil }
        do {
            let session = try PropertyListDecoder().decode(PlaybackSession.self, from: data)
            guard session.formatVersion == PlaybackSession.formatVersion,
                  session.appVersion == AppInfo.version,
                  session.appBuild == AppInfo.build else {
                clear()
                return nil
            }
            return session
        } catch {
            Logger.warning("Discarding invalid playback session: \(error)")
            clear()
            return nil
        }
    }

    func save(_ session: PlaybackSession) {
        queue.async { [weak self] in self?.write(session) }
    }

    func flush(_ session: PlaybackSession) {
        queue.sync { write(session) }
    }

    func clear() {
        guard let fileURL else { return }
        queue.sync {
            do {
                if FileManager.default.fileExists(atPath: fileURL.path) {
                    try FileManager.default.removeItem(at: fileURL)
                }
            } catch {
                Logger.error("Failed to clear playback session: \(error)")
            }
        }
    }

    private func write(_ session: PlaybackSession) {
        guard let fileURL else { return }
        do {
            let encoder = PropertyListEncoder()
            encoder.outputFormat = .binary
            let data = try encoder.encode(session)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            Logger.error("Failed to save playback session: \(error)")
        }
    }
}
