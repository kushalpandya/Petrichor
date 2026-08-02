//
// LibraryManager class extension
//
// Refresh policy for the Discover screen. Featured and Fresh Music ride the
// DiscoverUpdateInterval or their own refresh button; Most Loved & Played reselects when a
// play or favorite moves its ranking; Recently Played is recomputed on every visit. All
// but Recently Played persist their selection, so it survives relaunch.
//
// SQL lives in DMDiscoverQueries, mixing rules in LMDiscoverSelection, collage warming in
// LMDiscoverArtwork. This file only decides what to ask for, and when.
//

import Foundation

// MARK: - Discover

extension LibraryManager {
    // MARK: - Constants
    private static let discoverTrackIdsKey = "discoverTrackIds"
    /// `discoverUpdateInterval` governs Featured and Fresh Music together. The per-section
    /// refresh buttons don't touch it.
    private static let discoverLastUpdatedKey = "discoverLastUpdated"
    private static let discoverUpdateIntervalKey = "discoverUpdateInterval"
    private static let discoverTrackCountKey = "discoverTrackCount"
    private static let discoverFeaturedCacheKey = "discoverFeaturedCache"
    private static let discoverMostLovedCacheKey = "discoverMostLovedCache"
    private static let discoverLovedNeedsRefreshKey = "discoverLovedNeedsRefresh"

    private static let recentTrackPoolSize = 200
    /// The interval is measured in days, so hourly is plenty.
    private static let expiryCheckInterval: TimeInterval = 3600

    private var discoverUpdateInterval: DiscoverUpdateInterval {
        guard let rawValue = userDefaults.string(forKey: Self.discoverUpdateIntervalKey) else { return .weekly }
        return DiscoverUpdateInterval(persistedValue: rawValue) ?? .weekly
    }

    private var discoverTrackCount: Int {
        let count = userDefaults.integer(forKey: Self.discoverTrackCountKey)
        return count > 0 ? count : 50
    }

    private var discoverLastUpdated: Date? {
        userDefaults.object(forKey: Self.discoverLastUpdatedKey) as? Date
    }

    /// Whether a favorite or play has landed since Most Loved & Played was last selected.
    /// Persisted, because the signal usually arrives while the user is elsewhere in the app
    /// and easily outlives the session. An absent key means the row has never been selected
    /// on this signal at all (fresh install, or a cache inherited from when it rode the
    /// interval), which counts as needing a refresh.
    var discoverLovedNeedsRefresh: Bool {
        get {
            guard userDefaults.object(forKey: Self.discoverLovedNeedsRefreshKey) != nil else {
                return true
            }
            return userDefaults.bool(forKey: Self.discoverLovedNeedsRefreshKey)
        }
        set { userDefaults.set(newValue, forKey: Self.discoverLovedNeedsRefreshKey) }
    }

    /// Written only on a real transition: this fires on every play, and each write wakes
    /// every `UserDefaults.didChangeNotification` observer in the app.
    @objc
    func handleDiscoverLovedSignalChanged() {
        guard !discoverLovedNeedsRefresh else { return }
        discoverLovedNeedsRefresh = true
    }

    private func hasElapsed(since date: Date?) -> Bool {
        guard let date else { return true }
        return Date().timeIntervalSince(date) >= discoverUpdateInterval.timeInterval
    }

    // MARK: - Loading

    /// Idempotent entry point. Restores the sticky sections while they're fresh and
    /// regenerates them when due; Recently Played is always recomputed.
    @MainActor
    func loadDiscover() async {
        await runDiscoverLoad(forceFeatured: false, forceTracks: false)
    }

    /// Reselect the Featured picks only, restarting just their clock.
    @MainActor
    func refreshFeatured() async {
        Logger.info("Force refreshing Discover featured picks")
        await runDiscoverLoad(forceFeatured: true, forceTracks: false)
    }

    /// Reselect the Fresh Music tracks only, restarting just their clock.
    @MainActor
    func refreshFreshMusic() async {
        Logger.info("Force refreshing Discover fresh music")
        await runDiscoverLoad(forceFeatured: false, forceTracks: true)
    }

    @MainActor
    private func runDiscoverLoad(forceFeatured: Bool, forceTracks: Bool) async {
        await enqueueDiscoverWork { [self] in
            await performDiscoverLoad(forceFeatured: forceFeatured, forceTracks: forceTracks)
        }
    }

    /// Runs Discover work one operation at a time, in request order. These write
    /// overlapping state and their reads are serialized anyway; cancelling a shared task
    /// instead had the two refresh buttons cancelling each other.
    @MainActor
    private func enqueueDiscoverWork(_ work: @escaping @MainActor () async -> Void) async {
        let previous = discoverLoadTask
        let epoch = discoverResetEpoch
        let task = Task { @MainActor in
            await previous?.value
            // Cancellation is cooperative, so a task cancelled while queued would walk
            // straight into `work()` once its predecessor finished. The epoch covers the
            // same window for a reset, which cancels only the tail of the queue.
            guard !Task.isCancelled, epoch == discoverResetEpoch else { return }
            await work()
        }
        discoverLoadTask = task
        await task.value

        if discoverLoadTask == task {
            discoverLoadTask = nil
        }
    }

    /// Re-resolve the existing sticky selections without reselecting them, for changes that
    /// alter tile counts or artwork but must not reshuffle the rows.
    @MainActor
    func reresolveStickyDiscoverSections() async {
        await enqueueDiscoverWork { [self] in await performStickyReresolve() }
    }

    @MainActor
    private func performStickyReresolve(attempt: Int = 0) async {
        let cachedRefs = loadFeaturedCache()?.refs ?? []
        let cachedLovedRefs = loadFeaturedCache(key: Self.discoverMostLovedCacheKey)?.refs ?? []
        guard !cachedRefs.isEmpty || !cachedLovedRefs.isEmpty else { return }

        let manager = databaseManager
        let eligiblePlaylists = discoverEligiblePlaylists()
        let smartPlaylists = eligiblePlaylists.filter(\.needsInMemorySmartEvaluation)
        discoverStickyGeneration += 1
        let generation = discoverStickyGeneration

        discoverArtworkGeneration += 1
        let artworkGeneration = discoverArtworkGeneration
        let smart = captureDiscoverSmartSnapshot(eligiblePlaylists)
        let epoch = discoverResetEpoch

        let rows = await Task.detached(priority: .utility) {
            () -> ([DiscoverEntityRow], [DiscoverEntityRow], [UUID: [Track]]) in
            // Evaluated here rather than inside `resolveDiscoverEntities` so the warmer can
            // reuse it, else a tile keeps its old collage beside a new count.
            let smartTracks = manager.discoverSmartPlaylistTracks(for: smartPlaylists)
            // One resolve covers both rows; they share entities by design.
            let resolved = manager.resolveDiscoverEntities(
                Array(Set(cachedRefs + cachedLovedRefs)),
                smartPlaylists: smartPlaylists,
                tracksByPlaylist: smartTracks
            )
            let featured = cachedRefs.compactMap { resolved[$0] }
            let loved = cachedLovedRefs.compactMap { resolved[$0] }
            LibraryManager.warmCategoryArtwork(for: featured + loved)
            return (featured, loved, smartTracks)
        }.value

        // Reset mid-evaluation: these rows describe a database that no longer exists, and
        // even the retry below would run against the wrong one.
        guard generation == discoverStickyGeneration, epoch == discoverResetEpoch else { return }
        // Retried rather than left to `smartPlaylistPersistenceDidFinish`, since not every
        // cause posts it: a rename bumps `dateModified` outside persistence entirely.
        guard smartSnapshotIsCurrent(smart) else {
            retryDiscoverWork(attempt: attempt) { [self] in
                await performStickyReresolve(attempt: attempt + 1)
            }
            return
        }
        if !cachedRefs.isEmpty {
            featuredSection = .loaded(makeEntities(from: rows.0))
        }
        if !cachedLovedRefs.isEmpty {
            mostLovedSection = .loaded(makeEntities(from: rows.1))
        }

        Task { @MainActor in
            await warmDiscoverPlaylistArtwork(
                smartTracks: rows.2,
                smartVersions: smart.versions,
                generation: artworkGeneration
            )
        }
    }

    /// Recompute only the Recently Played row. Cheap enough to run whenever Discover comes
    /// back into view after a play was recorded.
    @MainActor
    func reloadDiscoverRecentlyPlayed() async {
        await enqueueDiscoverWork { [self] in await performRecentlyPlayedReload() }
    }

    @MainActor
    private func performRecentlyPlayedReload(attempt: Int = 0) async {
        // Queued rather than run alongside a full load: it needs that load's published
        // Featured picks as its exclusion set, or an entity lands in both rows.
        let manager = databaseManager
        let eligiblePlaylists = discoverEligiblePlaylists()
        let smartPlaylists = eligiblePlaylists.filter(\.needsInMemorySmartEvaluation)
        let eligiblePlaylistIds = Set(eligiblePlaylists.map(\.id))
        let featuredRefs = Set(loadFeaturedCache()?.refs ?? [])
        discoverRecentGeneration += 1
        // Claimed here, not in the warmer: a warmer from the previous snapshot has to be
        // invalidated the moment this load starts evaluating.
        discoverArtworkGeneration += 1
        let generation = discoverRecentGeneration
        let artworkGeneration = discoverArtworkGeneration
        let smart = captureDiscoverSmartSnapshot(eligiblePlaylists)
        let epoch = discoverResetEpoch

        let result = await Task.detached(priority: .utility) { () -> ([DiscoverEntityRow], [UUID: [Track]]) in
            let smartTracks = manager.discoverSmartPlaylistTracks(for: smartPlaylists)
            let candidates = LibraryManager.mergingPlaylistCandidates(
                manager.getDiscoverRecentlyPlayedCandidates(trackPoolSize: LibraryManager.recentTrackPoolSize),
                smart: manager.getDiscoverRecentSmartPlaylistCandidates(
                    for: smartPlaylists,
                    tracksByPlaylist: smartTracks,
                    recentTrackIds: manager.discoverRecentTrackIds(limit: LibraryManager.recentTrackPoolSize)
                ),
                eligibleIds: eligiblePlaylistIds,
                ranking: .recency
            )
            let rows = LibraryManager.selectRoundRobin(
                candidates,
                target: LibraryManager.recentlyPlayedSlotCount,
                excluding: featuredRefs
            )
            LibraryManager.warmCategoryArtwork(for: rows)
            return (rows, smartTracks)
        }.value

        guard generation == discoverRecentGeneration, epoch == discoverResetEpoch else { return }
        guard smartSnapshotIsCurrent(smart) else {
            retryDiscoverWork(attempt: attempt) { [self] in
                await performRecentlyPlayedReload(attempt: attempt + 1)
            }
            return
        }
        recentlyPlayedSection = .loaded(makeEntities(from: result.0))

        Task { @MainActor in
            await warmDiscoverPlaylistArtwork(
                smartTracks: result.1,
                smartVersions: smart.versions,
                generation: artworkGeneration
            )
        }
    }

    /// One re-run, queued so it starts after whatever displaced it has settled. Only used
    /// by paths that clear nothing on the way in, so exhausting it leaves a row a version
    /// behind rather than empty.
    @MainActor
    private func retryDiscoverWork(attempt: Int, _ work: @escaping @MainActor () async -> Void) {
        guard attempt < 1 else { return }
        Task { @MainActor in await enqueueDiscoverWork(work) }
    }

    /// For callers that aren't in an async context (onboarding scan threshold, settings
    /// track-count stepper).
    func refreshDiscoverTracks() {
        Task { @MainActor in
            await refreshFreshMusic()
        }
    }

    /// Required on a library reset: the caches hold raw track IDs, and SQLite reuses
    /// rowids, so a restored-by-ID list can resolve to unrelated, already played tracks.
    func clearDiscoverCaches() {
        discoverPendingRequest = nil
        userDefaults.removeObject(forKey: Self.discoverLovedNeedsRefreshKey)
        // A load already detached can't be cancelled outright, so invalidate its tokens
        // too; otherwise it finishes afterwards and republishes pre-reset IDs.
        discoverLoadTask?.cancel()
        discoverLoadTask = nil
        discoverStickyGeneration += 1
        discoverRecentGeneration += 1
        discoverTracksGeneration += 1
        discoverArtworkGeneration += 1
        discoverResetEpoch += 1

        for key in [
            Self.discoverTrackIdsKey,
            Self.discoverLastUpdatedKey,
            Self.discoverFeaturedCacheKey,
            Self.discoverMostLovedCacheKey
        ] {
            userDefaults.removeObject(forKey: key)
        }

        discoverPlaylistArtwork.removeAll()
        discoverWarmedPlaylistSignatures.removeAll()
        discoverTracks = []
        featuredSection = .loading
        mostLovedSection = .loading
        recentlyPlayedSection = .loading
        isLoadingDiscoverTracks = true
    }

    // MARK: - Lifecycle

    func startDiscoverExpiryTimer() {
        discoverExpiryTimer?.invalidate()
        discoverExpiryTimer = Timer.scheduledTimer(
            withTimeInterval: Self.expiryCheckInterval,
            repeats: true
        ) { [weak self] _ in
            guard let self, !self.isScanning,
                  self.hasElapsed(since: self.discoverLastUpdated) else { return }
            Task { @MainActor in
                await self.loadDiscover()
            }
        }
    }

    /// A smart playlist's snapshot has been rewritten. Discover work that raced it refused
    /// to publish, so this is what puts those rows back in step. The sticky selections are
    /// re-resolved, never reshuffled.
    @objc
    func handleSmartPlaylistPersistenceDidFinish() {
        Task { @MainActor in
            // The decision is queued, not just the work it picks: queued work may be about
            // to record a pending request, and reading the field now would miss it with
            // nothing left to replay it. Calls `perform*` rather than the public wrappers,
            // which enqueue, and enqueueing from enqueued work self-deadlocks.
            await enqueueDiscoverWork { [self] in
                if discoverPendingRequest != nil {
                    await replayPendingDiscoverRequest()
                } else {
                    await performStickyReresolve()
                    await performRecentlyPlayedReload()
                }
            }
        }
    }

    @MainActor
    private func replayPendingDiscoverRequest() async {
        guard let pending = discoverPendingRequest else { return }
        discoverPendingRequest = nil
        await performDiscoverLoad(
            forceFeatured: pending.forceFeatured, forceTracks: pending.forceTracks
        )
    }

    func stopDiscoverExpiryTimer() {
        discoverExpiryTimer?.invalidate()
        discoverExpiryTimer = nil
    }

    /// Re-arm the timer so a shortened interval takes effect without waiting out the old.
    func discoverUpdateIntervalDidChange() {
        startDiscoverExpiryTimer()
        if !isScanning, hasElapsed(since: discoverLastUpdated) {
            Task { @MainActor in await loadDiscover() }
        }
    }

    // MARK: - Core Load

    @MainActor
    private func performDiscoverLoad(
        forceFeatured: Bool,
        forceTracks: Bool,
        attempt: Int = 0,
        prior: DiscoverPriorContent? = nil
    ) async {
        // Nothing runs mid-scan: dbQueue is serialized, so every read here interleaves with
        // the scanner's writes. Returning before touching state also avoids blanking Fresh
        // Music and republishing it from a first-run empty cache.
        guard !isScanning else { return }

        // A manual refresh blanks its section to a skeleton rather than leave stale content
        // on screen, so hold what was there for an abandoned attempt to restore. Threaded
        // through retries: by attempt two the screen holds attempt one's skeleton.
        let prior = prior ?? DiscoverPriorContent(
            featured: featuredSection,
            recent: recentlyPlayedSection,
            tracks: discoverTracks
        )
        if forceFeatured {
            featuredSection = .loading
            recentlyPlayedSection = .loading
            discoverWarmedPlaylistSignatures.removeAll()
            discoverPlaylistArtwork.removeAll()
        }
        if forceTracks {
            discoverTracks = []
            isLoadingDiscoverTracks = true
        }

        let featuredCache = loadFeaturedCache()
        let lovedCache = loadFeaturedCache(key: Self.discoverMostLovedCacheKey)
        let cachedRefs = featuredCache?.refs ?? []
        let cachedLovedRefs = lovedCache?.refs ?? []
        let cachedTrackIds = userDefaults.array(forKey: Self.discoverTrackIdsKey) as? [Int64] ?? []
        // Presence of the entry, not whether it holds anything: a library with everything
        // played legitimately persists an empty track list, and treating that as "never
        // generated" would make every visit a scheduled regeneration.
        let hasGenerated = discoverLastUpdated != nil && featuredCache != nil
        // The interval regenerates both; the refresh buttons regenerate only their own and
        // leave the schedule alone, so one can't silently postpone the other.
        let scheduled = hasElapsed(since: discoverLastUpdated) || !hasGenerated
        let regenerateFeatured = scheduled || forceFeatured
        // Off the interval entirely: this row answers "what do you love and play most", so
        // it reselects when that changes. Nothing played or favorited, nothing to reshuffle.
        let regenerateLoved = discoverLovedNeedsRefresh || lovedCache == nil
        let regenerateTracks = scheduled || forceTracks
        let trackLimit = discoverTrackCount
        let manager = databaseManager
        let eligiblePlaylists = discoverEligiblePlaylists()
        let smartPlaylists = eligiblePlaylists.filter(\.needsInMemorySmartEvaluation)
        let eligiblePlaylistIds = Set(eligiblePlaylists.map(\.id))
        discoverStickyGeneration += 1
        discoverRecentGeneration += 1
        discoverTracksGeneration += 1
        discoverArtworkGeneration += 1
        let stickyGeneration = discoverStickyGeneration
        let recentGeneration = discoverRecentGeneration
        let tracksGeneration = discoverTracksGeneration
        let artworkGeneration = discoverArtworkGeneration
        let smart = captureDiscoverSmartSnapshot(eligiblePlaylists)
        let epoch = discoverResetEpoch

        let payload = await Task.detached(priority: .userInitiated) { () -> DiscoverPayload in
            // One criteria evaluation shared by every consumer below.
            let smartTracks = manager.discoverSmartPlaylistTracks(for: smartPlaylists)

            // Featured: reselect, or cheaply re-resolve the persisted picks.
            let featuredRefs: [DiscoverEntityRef]
            let featuredRows: [DiscoverEntityRow]
            if regenerateFeatured {
                let rotation = LibraryManager.mergingPlaylistCandidates(
                    manager.getDiscoverFeaturedCandidates(signal: .inRotation),
                    smart: manager.getDiscoverSmartPlaylistCandidates(
                        for: smartPlaylists, tracksByPlaylist: smartTracks, signal: .inRotation
                    ),
                    eligibleIds: eligiblePlaylistIds,
                    ranking: .rotation
                )
                let neglected = LibraryManager.mergingPlaylistCandidates(
                    manager.getDiscoverFeaturedCandidates(signal: .neglected),
                    smart: manager.getDiscoverSmartPlaylistCandidates(
                        for: smartPlaylists, tracksByPlaylist: smartTracks, signal: .neglected
                    ),
                    eligibleIds: eligiblePlaylistIds,
                    ranking: .random
                )
                featuredRows = LibraryManager.selectFeatured(rotation: rotation, neglected: neglected)
                featuredRefs = featuredRows.map(\.ref)
            } else {
                let resolved = manager.resolveDiscoverEntities(
                    cachedRefs, smartPlaylists: smartPlaylists, tracksByPlaylist: smartTracks
                )
                featuredRows = cachedRefs.compactMap { resolved[$0] }
                featuredRefs = featuredRows.map(\.ref)
            }

            // Sticky like Featured, but sharing no exclusion set with the other rows: a
            // genuine favourite is allowed to appear in more than one.
            let lovedRefs: [DiscoverEntityRef]
            let lovedRows: [DiscoverEntityRow]
            if regenerateLoved {
                let loved = LibraryManager.mergingPlaylistCandidates(
                    manager.getDiscoverFeaturedCandidates(signal: .mostLoved),
                    smart: manager.getDiscoverSmartPlaylistCandidates(
                        for: smartPlaylists, tracksByPlaylist: smartTracks, signal: .mostLoved
                    ),
                    eligibleIds: eligiblePlaylistIds,
                    ranking: .loved
                )
                lovedRows = LibraryManager.selectRoundRobin(loved, target: LibraryManager.mostLovedSlotCount)
                lovedRefs = lovedRows.map(\.ref)
            } else {
                let resolved = manager.resolveDiscoverEntities(
                    cachedLovedRefs, smartPlaylists: smartPlaylists, tracksByPlaylist: smartTracks
                )
                lovedRows = cachedLovedRefs.compactMap { resolved[$0] }
                lovedRefs = lovedRows.map(\.ref)
            }

            // Recently Played: always fresh, minus anything already in Featured.
            let recentCandidates = LibraryManager.mergingPlaylistCandidates(
                manager.getDiscoverRecentlyPlayedCandidates(trackPoolSize: LibraryManager.recentTrackPoolSize),
                smart: manager.getDiscoverRecentSmartPlaylistCandidates(
                    for: smartPlaylists,
                    tracksByPlaylist: smartTracks,
                    recentTrackIds: manager.discoverRecentTrackIds(limit: LibraryManager.recentTrackPoolSize)
                ),
                eligibleIds: eligiblePlaylistIds,
                ranking: .recency
            )
            let recentRows = LibraryManager.selectRoundRobin(
                recentCandidates,
                target: LibraryManager.recentlyPlayedSlotCount,
                excluding: Set(featuredRefs)
            )

            // The by-ids restore preserves the saved order, which a plain IN fetch loses.
            let tracks = regenerateTracks
                ? manager.getDiscoverTracks(limit: trackLimit)
                : manager.getTracksWithArtwork(byIds: cachedTrackIds)

            LibraryManager.warmCategoryArtwork(for: featuredRows + recentRows + lovedRows)

            return DiscoverPayload(
                featuredRefs: featuredRefs,
                featuredRows: featuredRows,
                lovedRefs: lovedRefs,
                lovedRows: lovedRows,
                recentRows: recentRows,
                tracks: tracks,
                smartTracks: smartTracks,
                smart: smart,
                didRegenerateFeatured: regenerateFeatured,
                didRegenerateLoved: regenerateLoved,
                didRegenerateTracks: regenerateTracks,
                didRunScheduled: scheduled
            )
        }.value

        // Re-checked: `isScanning` can turn true after the entry guard, and being per-folder
        // it also flickers false between folders. Publishing then ships a selection read
        // across a moving library.
        guard !isScanning else { return }
        // Reset while this evaluated: restoring pre-reset content, marking a pending request
        // or queueing a retry would all be against the replaced database.
        guard epoch == discoverResetEpoch else { return }

        // A smart playlist moved while this evaluated, so every row derived from it is
        // stale, not just its artwork.
        guard smartSnapshotIsCurrent(payload.smart) else {
            abandonDiscoverLoad(
                forceFeatured: forceFeatured,
                forceTracks: forceTracks,
                attempt: attempt,
                prior: prior
            )
            return
        }

        publish(
            payload,
            stickyGeneration: stickyGeneration,
            recentGeneration: recentGeneration,
            tracksGeneration: tracksGeneration
        )
        guard stickyGeneration == discoverStickyGeneration else { return }

        // Not awaited: the rows are already on screen, and covers fill in behind them.
        Task { @MainActor in
            await warmDiscoverPlaylistArtwork(
                smartTracks: payload.smartTracks,
                smartVersions: payload.smart.versions,
                generation: artworkGeneration
            )
        }
    }


    /// Retry once, which covers the common case where the rewrite has already landed. Past
    /// that, put back whatever the forced sections cleared so nothing sits on a skeleton.
    @MainActor
    private func abandonDiscoverLoad(
        forceFeatured: Bool,
        forceTracks: Bool,
        attempt: Int,
        prior: DiscoverPriorContent
    ) {
        guard attempt < 1 else {
            if forceFeatured {
                featuredSection = prior.featured
                recentlyPlayedSection = prior.recent
            }
            if forceTracks {
                discoverTracks = prior.tracks
                isLoadingDiscoverTracks = false
            }
            // OR'd, so two abandoned refreshes don't lose one's intent.
            discoverPendingRequest = (
                forceFeatured: forceFeatured || (discoverPendingRequest?.forceFeatured ?? false),
                forceTracks: forceTracks || (discoverPendingRequest?.forceTracks ?? false)
            )
            // A completion notification only arrives while something is still persisting.
            // When nothing is, this request has no other way back and a cold load would sit
            // on skeletons forever, so drain it here. Quiescence also means whatever
            // displaced the load has settled, so the replay should land.
            let isQuiescent = AppCoordinator.shared?
                .playlistManager.smartPersistenceToken.isQuiescent ?? true
            if isQuiescent {
                Task { @MainActor in
                    await enqueueDiscoverWork { [self] in await replayPendingDiscoverRequest() }
                }
            }
            return
        }

        Task { @MainActor in
            await enqueueDiscoverWork { [self] in
                await performDiscoverLoad(
                    forceFeatured: forceFeatured,
                    forceTracks: forceTracks,
                    attempt: attempt + 1,
                    prior: prior
                )
            }
        }
    }

    /// Renders genre/decade artwork before `makeEntities` needs it: that runs on the main
    /// actor and `CategoryEntity.init` does its CoreText render inline.
    private static func warmCategoryArtwork(for rows: [DiscoverEntityRow]) {
        for row in rows {
            guard let filterType = row.ref.kind.filterType,
                  row.ref.kind == .genre || row.ref.kind == .decade else { continue }
            CategoryEntity.warmArtwork(name: row.ref.value, filterType: filterType)
        }
    }

    /// Publishes and persists each section group under its own token. A detached task can't
    /// be cancelled from here, so a superseded writer discards its own result. Per group,
    /// because a Recently Played refresh landing mid-load must not stop the sticky rows or
    /// the track list.
    @MainActor
    private func publish(
        _ payload: DiscoverPayload,
        stickyGeneration: Int,
        recentGeneration: Int,
        tracksGeneration: Int
    ) {
        let stickyIsCurrent = stickyGeneration == discoverStickyGeneration
        let recentIsCurrent = recentGeneration == discoverRecentGeneration
        let tracksAreCurrent = tracksGeneration == discoverTracksGeneration

        if stickyIsCurrent {
            featuredSection = .loaded(makeEntities(from: payload.featuredRows))
            mostLovedSection = .loaded(makeEntities(from: payload.lovedRows))
            if payload.didRegenerateFeatured {
                saveFeaturedCache(refs: payload.featuredRefs)
            }
            if payload.didRegenerateLoved {
                saveFeaturedCache(refs: payload.lovedRefs, key: Self.discoverMostLovedCacheKey)
                discoverLovedNeedsRefresh = false
            }
        }
        if tracksAreCurrent {
            discoverTracks = payload.tracks
            isLoadingDiscoverTracks = false
            if payload.didRegenerateTracks {
                userDefaults.set(payload.tracks.compactMap { $0.trackId }, forKey: Self.discoverTrackIdsKey)
            }
        }
        if recentIsCurrent {
            recentlyPlayedSection = .loaded(makeEntities(from: payload.recentRows))
        }

        // The shared clock only advances when a scheduled regeneration actually landed.
        if payload.didRunScheduled, stickyIsCurrent, tracksAreCurrent {
            userDefaults.set(Date(), forKey: Self.discoverLastUpdatedKey)
        }
    }

    // MARK: - Entity Construction

    /// Main actor deliberately: `CategoryEntity.init` runs a CoreText render, and playlists
    /// need `PlaylistManager`'s live state, which `DatabaseManager` can't see.
    @MainActor
    private func makeEntities(from rows: [DiscoverEntityRow]) -> [any Entity] {
        let playlists = AppCoordinator.shared?.playlistManager.playlists ?? []
        let playlistsById = Dictionary(playlists.map { ($0.id, $0) }) { first, _ in first }

        return rows.compactMap { row -> (any Entity)? in
            switch row.ref.kind {
            case .album:
                return AlbumEntity(
                    name: row.ref.value,
                    trackCount: row.trackCount,
                    artworkData: row.artworkData,
                    albumId: row.ref.albumId,
                    year: row.year,
                    artistName: row.artistName
                )

            case .artist:
                return ArtistEntity(
                    name: row.ref.value,
                    trackCount: row.trackCount,
                    artworkData: row.artworkData
                )

            case .genre, .decade:
                guard let filterType = row.ref.kind.filterType else { return nil }
                return CategoryEntity(name: row.ref.value, trackCount: row.trackCount, filterType: filterType)

            case .playlist:
                // A playlist PlaylistManager doesn't know isn't browsable; drop the tile.
                guard let playlistId = row.ref.playlistId,
                      let playlist = playlistsById[playlistId] else { return nil }
                return PlaylistEntity(
                    playlist: playlist,
                    artworkData: discoverPlaylistArtwork[playlistId] ?? playlist.artworkData,
                    trackCount: row.trackCount
                )
            }
        }
    }

    /// Swaps in new artwork for an artist already on a carousel. The sections hold their own
    /// `ArtistEntity` copies, so updating `cachedArtistEntities` leaves them stale until
    /// something rebuilds them.
    func updateDiscoverArtistArtwork(name: String, artworkData: Data?) {
        func applying(_ entities: [any Entity]) -> [any Entity] {
            entities.map { entity in
                guard let artist = entity as? ArtistEntity, artist.name == name else { return entity }
                return ArtistEntity(name: artist.name, trackCount: artist.trackCount, artworkData: artworkData)
            }
        }

        if case .loaded(let entities) = featuredSection {
            featuredSection = .loaded(applying(entities))
        }
        if case .loaded(let entities) = mostLovedSection {
            mostLovedSection = .loaded(applying(entities))
        }
        if case .loaded(let entities) = recentlyPlayedSection {
            recentlyPlayedSection = .loaded(applying(entities))
        }
    }

    @MainActor
    private func captureDiscoverSmartSnapshot(_ eligible: [Playlist]) -> DiscoverSmartSnapshot {
        DiscoverSmartSnapshot(
            versions: Self.smartPlaylistVersions(eligible.filter { $0.type == .smart }),
            persistence: AppCoordinator.shared?.playlistManager.smartPersistenceToken
                ?? SmartPlaylistPersistenceToken(completions: 0, isQuiescent: true)
        )
    }

    /// Whether a snapshot still describes the world. Rows, counts and the sticky caches all
    /// derive from smart-playlist membership, so publishing against a superseded snapshot
    /// persists a selection describing criteria the user has already replaced.
    @MainActor
    private func smartSnapshotIsCurrent(_ snapshot: DiscoverSmartSnapshot) -> Bool {
        let current = currentPlaylistsById()
        guard snapshot.versions.allSatisfy({ current[$0.key]?.dateModified == $0.value }) else {
            return false
        }
        // A rewrite already running when the snapshot was taken can finish before this check
        // without moving `completions`, so both readings have to be quiescent.
        let now = AppCoordinator.shared?.playlistManager.smartPersistenceToken
            ?? SmartPlaylistPersistenceToken(completions: 0, isQuiescent: true)
        return snapshot.persistence.isQuiescent
            && now.isQuiescent
            && now.completions == snapshot.persistence.completions
    }

    /// The version each smart evaluation was made against.
    static func smartPlaylistVersions(_ playlists: [Playlist]) -> [UUID: Date] {
        Dictionary(playlists.map { ($0.id, $0.dateModified) }) { first, _ in first }
    }

    // MARK: - Playlist Candidates

    @MainActor
    private func discoverEligiblePlaylists() -> [Playlist] {
        (AppCoordinator.shared?.playlistManager.playlists ?? []).filter(\.isDiscoverEligible)
    }

    private enum PlaylistRanking {
        case rotation
        case recency
        case random
        case loved
    }

    /// Playlist candidates arrive from two places (SQL for regular and frozen playlists,
    /// in-Swift evaluation for auto-updating smart ones), so they're re-ranked against each
    /// other rather than concatenated. Also drops the built-ins, which SQL can't exclude.
    /// Only the playlist bucket is reordered; the other kinds keep their SQL ranking.
    private static func mergingPlaylistCandidates(
        _ candidates: [DiscoverEntityRow],
        smart: [DiscoverEntityRow],
        eligibleIds: Set<UUID>,
        ranking: PlaylistRanking
    ) -> [DiscoverEntityRow] {
        var others: [DiscoverEntityRow] = []
        var playlists: [DiscoverEntityRow] = []

        for row in candidates + smart {
            guard row.ref.kind == .playlist else {
                others.append(row)
                continue
            }
            guard let playlistId = row.ref.playlistId, eligibleIds.contains(playlistId) else { continue }
            playlists.append(row)
        }

        switch ranking {
        case .rotation:
            playlists.sort { $0.rotationScore > $1.rotationScore }
        case .recency:
            playlists.sort { ($0.lastPlayed ?? .distantPast) > ($1.lastPlayed ?? .distantPast) }
        case .random:
            playlists.shuffle()
        case .loved:
            playlists.sort { $0.lovedScore > $1.lovedScore }
        }

        return others + playlists
    }

    // MARK: - Cache

    private func loadFeaturedCache(key: String? = nil) -> DiscoverFeaturedCache? {
        guard let data = userDefaults.data(forKey: key ?? Self.discoverFeaturedCacheKey),
              let cache = try? JSONDecoder().decode(DiscoverFeaturedCache.self, from: data),
              cache.version == DiscoverFeaturedCache.currentVersion else {
            return nil
        }
        return cache
    }

    private func saveFeaturedCache(refs: [DiscoverEntityRef], key: String? = nil) {
        let cache = DiscoverFeaturedCache(version: DiscoverFeaturedCache.currentVersion, refs: refs)
        guard let data = try? JSONEncoder().encode(cache) else {
            Logger.error("Failed to encode Discover featured cache")
            return
        }
        userDefaults.set(data, forKey: key ?? Self.discoverFeaturedCacheKey)
    }
}
