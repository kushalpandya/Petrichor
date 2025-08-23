import SwiftUI
import AppKit
import Combine

class ContextMenuTableView: NSTableView {
    var contextMenuHandler: ((NSEvent) -> NSMenu?)?

    override func menu(for event: NSEvent) -> NSMenu? {
        contextMenuHandler?(event)
    }
}

class ContextMenuHeaderView: NSTableHeaderView {
    var headerContextMenuHandler: (() -> NSMenu?)?
    
    override func menu(for event: NSEvent) -> NSMenu? {
        let point = convert(event.locationInWindow, from: nil)
        if bounds.contains(point) {
            return headerContextMenuHandler?()
        }
        return super.menu(for: event)
    }
}

extension Notification.Name {
    static let playEntityTracks = Notification.Name("playEntityTracks")
    static let playPlaylistTracks = Notification.Name("playPlaylistTracks")
}

struct TrackTableView: NSViewRepresentable {
    let tracks: [Track]
    let playlistID: UUID?
    let entityID: UUID?
    let onPlayTrack: (Track) -> Void
    let contextMenuItems: (Track) -> [ContextMenuItem]

    @EnvironmentObject var playbackManager: PlaybackManager
    @EnvironmentObject var playlistManager: PlaylistManager
    @StateObject private var columnManager = ColumnVisibilityManager.shared

    @State private var sortOrder: [NSSortDescriptor] = []

    @AppStorage("trackTableSortOrder")
    private var sortOrderData = Data()

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        let tableView = ContextMenuTableView()
        let headerView = ContextMenuHeaderView()
        headerView.headerContextMenuHandler = {
            context.coordinator.createColumnMenu()
        }

        tableView.contextMenuHandler = { event in
            context.coordinator.handleContextMenu(for: event, in: tableView)
        }

        tableView.delegate = context.coordinator
        tableView.dataSource = context.coordinator
        tableView.allowsMultipleSelection = false
        tableView.allowsEmptySelection = false
        tableView.doubleAction = #selector(Coordinator.doubleClick(_:))
        tableView.target = context.coordinator
        context.coordinator.setTableView(tableView)
        tableView.rowHeight = 44
        tableView.intercellSpacing = NSSize(width: 0, height: 0)
        tableView.gridStyleMask = []

        tableView.usesAlternatingRowBackgroundColors = false
        tableView.style = .fullWidth
        tableView.selectionHighlightStyle = .none
        tableView.backgroundColor = NSColor.clear

        // Add these settings for better column behavior
        tableView.allowsColumnReordering = true
        tableView.allowsColumnSelection = false
        tableView.allowsColumnResizing = true
        tableView.columnAutoresizingStyle = .uniformColumnAutoresizingStyle

        headerView.tableView = tableView
        tableView.headerView = headerView

        // Set up columns
        setupColumns(tableView: tableView)

        if let playlistID = playlistID {
            // For playlists, load from PlaylistSortManager
            let sortCriteria = PlaylistSortManager.shared.getSortCriteria(for: playlistID)
            let isAscending = PlaylistSortManager.shared.getSortAscending(for: playlistID)
            
            switch sortCriteria {
            case .dateAdded:
                // Don't apply any sort descriptor for date added
                // The tracks should already be in the correct order
                break
            case .title:
                tableView.sortDescriptors = [NSSortDescriptor(key: "title", ascending: isAscending)]
            case .custom:
                if let customColumn = PlaylistSortManager.shared.getCustomSortColumn(for: playlistID) {
                    tableView.sortDescriptors = [NSSortDescriptor(key: customColumn, ascending: isAscending)]
                }
            }
        } else if let savedSort = UserDefaults.standard.dictionary(forKey: "trackTableSortOrder"),
                  let key = savedSort["key"] as? String,
                  let ascending = savedSort["ascending"] as? Bool {
            tableView.sortDescriptors = [NSSortDescriptor(key: key, ascending: ascending)]
        }

        scrollView.documentView = tableView
        scrollView.hasVerticalScroller = true
        scrollView.backgroundColor = NSColor.clear

        DispatchQueue.main.async {
            self.redistributeColumnWidths(tableView: tableView)
        }

        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard let tableView = nsView.documentView as? NSTableView else { return }

        // Store the current playing track info before updates
        let previousPlayingPath = context.coordinator.currentlyPlayingTrackPath

        // Only update if tracks actually changed (by count or IDs)
        let tracksChanged = context.coordinator.tracks.count != tracks.count ||
                           !zip(context.coordinator.tracks, tracks).allSatisfy { $0.id == $1.id }

        if tracksChanged {
            context.coordinator.tracks = tracks
            context.coordinator.sortedTracks = tracks

            // Apply any existing sort descriptors to the new tracks
            if !tableView.sortDescriptors.isEmpty {
                context.coordinator.tableView(tableView, sortDescriptorsDidChange: [])
            } else {
                tableView.reloadData()
            }
        }

        // Always update these properties
        context.coordinator.columnVisibility = columnManager.columnVisibility
        context.coordinator.playbackManager = playbackManager
        context.coordinator.playlistID = playlistID

        // Update column visibility
        updateColumnVisibility(tableView: tableView)

        // Update playing indicator and hover state changes
        let currentPlayingPath = playbackManager.currentTrack?.url.path
        let isCurrentlyPlaying = playbackManager.isPlaying
        let wasPlaying = context.coordinator.isPlaying
        let playbackStateChanged = wasPlaying != isCurrentlyPlaying
        let hoveredRowChanged = context.coordinator.lastHoveredRow != context.coordinator.hoveredRow

        // Check if the playing track changed
        let playingTrackChanged = previousPlayingPath != currentPlayingPath

        if playingTrackChanged || playbackStateChanged || hoveredRowChanged {
            // Update hover state tracking
            context.coordinator.lastHoveredRow = context.coordinator.hoveredRow

            // If the playing track changed, update both old and new tracks
            if playingTrackChanged {
                // Update the previous playing track row (to remove indicator)
                if let oldPath = previousPlayingPath,
                   let oldIndex = context.coordinator.sortedTracks.firstIndex(where: { $0.url.path == oldPath }) {
                    updateRowView(at: oldIndex, in: tableView)
                }

                // Update the new playing track row (to show indicator)
                if let newPath = currentPlayingPath,
                   let newIndex = context.coordinator.sortedTracks.firstIndex(where: { $0.url.path == newPath }) {
                    updateRowView(at: newIndex, in: tableView)
                }

                // Store the new playing track path
                context.coordinator.currentlyPlayingTrackPath = currentPlayingPath
            } else if playbackStateChanged {
                // Just playback state changed (play/pause), update current track
                if let currentPath = currentPlayingPath,
                   let currentIndex = context.coordinator.sortedTracks.firstIndex(where: { $0.url.path == currentPath }) {
                    updateRowView(at: currentIndex, in: tableView)
                }
            }

            // Update hovered row if it changed
            if hoveredRowChanged {
                if let oldHoveredRow = context.coordinator.lastHoveredRow {
                    updateRowView(at: oldHoveredRow, in: tableView)
                }
                if let newHoveredRow = context.coordinator.hoveredRow {
                    updateRowView(at: newHoveredRow, in: tableView)
                }
            }
        }
        
        if tracksChanged && currentPlayingPath != nil {
            if let newIndex = context.coordinator.sortedTracks.firstIndex(where: { $0.url.path == currentPlayingPath }) {
                updateRowView(at: newIndex, in: tableView)
            }
        }

        // Store the current playing state
        context.coordinator.isPlaying = isCurrentlyPlaying
    }

    private func updateRowView(at row: Int, in tableView: NSTableView) {
        // Update both play/pause column and title column
        let columnsToUpdate = ["playPause", "title"]

        for columnID in columnsToUpdate {
            let columnIndex = tableView.column(withIdentifier: NSUserInterfaceItemIdentifier(columnID))
            guard columnIndex >= 0 else { continue }

            tableView.reloadData(forRowIndexes: IndexSet(integer: row),
                               columnIndexes: IndexSet(integer: columnIndex))
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(
            tracks: tracks,
            playlistID: playlistID,
            entityID: entityID,
            onPlayTrack: onPlayTrack,
            playbackManager: playbackManager,
            playlistManager: playlistManager,
            contextMenuItems: contextMenuItems,
            columnVisibility: columnManager.columnVisibility
        )
    }

    private func setupColumns(tableView: NSTableView) {
        // Remove any existing columns first
        while !tableView.tableColumns.isEmpty {
            tableView.removeTableColumn(tableView.tableColumns[0])
        }

        // Add play/pause column first
        let playColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("playPause"))
        playColumn.title = ""
        playColumn.width = 32
        playColumn.minWidth = 32
        playColumn.maxWidth = 32
        playColumn.resizingMask = []
        tableView.addTableColumn(playColumn)
        
        // Get the saved column order or use default order
        let savedOrder = columnManager.columnOrder
        let defaultColumns = TrackTableColumn.allColumns
        
        // Create columns in the saved order (if available) or default order
        let orderedColumns: [TrackTableColumn]
        if let savedOrder = savedOrder {
            // Map saved identifiers back to TrackTableColumn instances
            let savedColumns = savedOrder.compactMap { identifier in
                defaultColumns.first { $0.identifier == identifier }
            }
            // Add any new columns that aren't in the saved order
            let newColumns = defaultColumns.filter { column in
                !savedOrder.contains(column.identifier)
            }
            orderedColumns = savedColumns + newColumns
        } else {
            orderedColumns = defaultColumns
        }

        for column in orderedColumns {
            let tableColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(column.identifier))

            if case .special(.trackNumber) = column {
                tableColumn.title = "#"
            } else {
                tableColumn.title = column.displayName
            }

            // Set resizing mask to allow user resizing
            tableColumn.resizingMask = .userResizingMask

            // Add sort descriptor
            switch column {
            case .special(.title):
                tableColumn.sortDescriptorPrototype = NSSortDescriptor(key: "title", ascending: true)
            case .special(.duration):
                tableColumn.sortDescriptorPrototype = NSSortDescriptor(key: "duration", ascending: true)
            case .special(.trackNumber):
                tableColumn.sortDescriptorPrototype = NSSortDescriptor(key: "trackNumber", ascending: true)
            case .libraryFilter(let filterType):
                let sortKey = filterType.databaseColumn
                tableColumn.sortDescriptorPrototype = NSSortDescriptor(key: sortKey, ascending: true)
            }

            switch column {
            case .special(.title):
                tableColumn.minWidth = 150
            case .special(.duration):
                tableColumn.minWidth = 50
            case .special(.trackNumber):
                tableColumn.minWidth = 40
            case .libraryFilter(let filterType):
                switch filterType {
                case .artists, .albums:
                    tableColumn.minWidth = 100
                case .albumArtists, .composers:
                    tableColumn.minWidth = 100
                case .genres:
                    tableColumn.minWidth = 80
                case .decades:
                    tableColumn.minWidth = 60
                case .years:
                    tableColumn.minWidth = 50
                }
            }

            if let savedWidth = columnManager.getColumnWidth(column.identifier) {
                tableColumn.width = savedWidth
            } else {
                // Default widths
                switch column {
                case .special(.title):
                    tableColumn.width = 300
                case .special(.duration):
                    tableColumn.width = 70
                case .special(.trackNumber):
                    tableColumn.width = 30
                case .libraryFilter(let filterType):
                    switch filterType {
                    case .artists, .albums:
                        tableColumn.width = 200
                    case .albumArtists, .composers:
                        tableColumn.width = 150
                    case .genres:
                        tableColumn.width = 120
                    case .decades:
                        tableColumn.width = 80
                    case .years:
                        tableColumn.width = 60
                    }
                }
            }

            tableColumn.isHidden = !columnManager.columnVisibility.isVisible(column)
            tableView.addTableColumn(tableColumn)
        }
    }

    private func updateColumnVisibility(tableView: NSTableView) {
        var visibilityChanged = false

        for column in TrackTableColumn.allColumns {
            if let tableColumn = tableView.tableColumn(withIdentifier: NSUserInterfaceItemIdentifier(column.identifier)) {
                let shouldBeHidden = !columnManager.columnVisibility.isVisible(column)
                if tableColumn.isHidden != shouldBeHidden {
                    tableColumn.isHidden = shouldBeHidden
                    visibilityChanged = true
                }
            }
        }

        if visibilityChanged {
            DispatchQueue.main.async {
                self.redistributeColumnWidths(tableView: tableView)
            }
        }
    }

    private func redistributeColumnWidths(tableView: NSTableView) {
        let visibleColumns = tableView.tableColumns.filter { !$0.isHidden }
        guard !visibleColumns.isEmpty else { return }

        // Get the table view's visible width
        let scrollView = tableView.enclosingScrollView
        let availableWidth = scrollView?.documentVisibleRect.width ?? tableView.bounds.width

        // Calculate current total width of visible columns
        let currentTotalWidth = visibleColumns.reduce(0) { $0 + $1.width }

        // If columns don't fill the space, distribute the difference
        if currentTotalWidth < availableWidth - 20 { // 20px margin for scrollbar
            let difference = availableWidth - currentTotalWidth - 20
            let additionalWidthPerColumn = difference / CGFloat(visibleColumns.count)

            for column in visibleColumns {
                column.width += additionalWidthPerColumn
            }
        }
    }

    class Coordinator: NSObject, NSTableViewDelegate, NSTableViewDataSource {
        var tracks: [Track]
        var sortedTracks: [Track] = []
        var hoveredRow: Int?
        var isPlaying: Bool = false
        var playlistID: UUID?
        let entityID: UUID?
        let playlistSortManager = PlaylistSortManager.shared
        let onPlayTrack: (Track) -> Void
        var playbackManager: PlaybackManager
        let playlistManager: PlaylistManager
        let contextMenuItems: (Track) -> [ContextMenuItem]
        var columnVisibility: TrackTableColumnVisibility
        var currentlyPlayingTrackPath: String?
        var lastHoveredRow: Int?
        var lastMouseLocation: NSPoint = .zero
        
        var columnManager: ColumnVisibilityManager {
            ColumnVisibilityManager.shared
        }

        private var reloadTimer: Timer?
        private var pendingReload = false
        private var cancellables = Set<AnyCancellable>()
        private weak var hostTableView: NSTableView?

        init(
            tracks: [Track],
            playlistID: UUID?,
            entityID: UUID?,
            onPlayTrack: @escaping (Track) -> Void,
            playbackManager: PlaybackManager,
            playlistManager: PlaylistManager,
            contextMenuItems: @escaping (Track) -> [ContextMenuItem],
            columnVisibility: TrackTableColumnVisibility
        ) {
            self.tracks = tracks
            self.sortedTracks = tracks
            self.playlistID = playlistID
            self.entityID = entityID
            self.onPlayTrack = onPlayTrack
            self.playbackManager = playbackManager
            self.playlistManager = playlistManager
            self.contextMenuItems = contextMenuItems
            self.columnVisibility = columnVisibility

            super.init()

            // Observe playback state changes
            playbackManager.$isPlaying
                .receive(on: DispatchQueue.main)
                .sink { [weak self] _ in
                    self?.updatePlayingIndicator()
                }
                .store(in: &cancellables)

            playbackManager.$currentTrack
                .receive(on: DispatchQueue.main)
                .sink { [weak self] _ in
                    self?.updatePlayingIndicator()
                }
                .store(in: &cancellables)
            
            if entityID != nil {
                // Entity view notifications
                NotificationCenter.default.addObserver(
                    self,
                    selector: #selector(handlePlayEntityNotification(_:)),
                    name: .playEntityTracks,
                    object: nil
                )
            } else if playlistID != nil {
                // Playlist view notifications
                NotificationCenter.default.addObserver(
                    self,
                    selector: #selector(handlePlayPlaylistNotification(_:)),
                    name: .playPlaylistTracks,
                    object: nil
                )
            }
        }

        deinit {
            cancellables.removeAll()
            NotificationCenter.default.removeObserver(self)
        }

        // MARK: - NSTableViewDataSource

        func numberOfRows(in tableView: NSTableView) -> Int {
            sortedTracks.count
        }

        func setTableView(_ tableView: NSTableView) {
            self.hostTableView = tableView

            if let scrollView = tableView.enclosingScrollView {
                NotificationCenter.default.addObserver(
                    self,
                    selector: #selector(scrollViewDidScroll(_:)),
                    name: NSView.boundsDidChangeNotification,
                    object: scrollView.contentView
                )
            }
        }

        // MARK: - NSTableViewDelegate

        func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
            guard row < sortedTracks.count else { return nil }
            let track = sortedTracks[row]

            guard let columnID = tableColumn?.identifier.rawValue else { return nil }

            // Handle play/pause column
            if columnID == "playPause" {
                let identifier = NSUserInterfaceItemIdentifier("PlayPauseCell")

                if let hostingView = tableView.makeView(withIdentifier: identifier, owner: nil) as? NSHostingView<PlayPauseCell> {
                    hostingView.rootView = PlayPauseCell(
                        track: track,
                        isHovered: hoveredRow == row,
                        playbackManager: playbackManager
                    ) { [unowned self] in
                            self.handlePlayTrack(track)
                    }
                    return hostingView
                } else {
                    let hostingView = NSHostingView(rootView: PlayPauseCell(
                        track: track,
                        isHovered: hoveredRow == row,
                        playbackManager: playbackManager
                    ) { [unowned self] in
                            self.handlePlayTrack(track)
                    })
                    hostingView.identifier = identifier
                    return hostingView
                }
            }

            // Continue with existing column handling...
            guard let column = TrackTableColumn.allColumns.first(where: { $0.identifier == columnID }) else {
                return nil
            }

            switch column {
            case .special(.title):
                // Keep NSHostingView for title since it's complex
                let identifier = NSUserInterfaceItemIdentifier("TitleCell")

                if let hostingView = tableView.makeView(withIdentifier: identifier, owner: nil) as? NSHostingView<TrackTableTitleCell> {
                    // Update the existing hosting view's content
                    hostingView.rootView = TrackTableTitleCell(
                        track: track,
                        playbackManager: playbackManager
                    )
                    return hostingView
                } else {
                    let hostingView = NSHostingView(rootView: TrackTableTitleCell(
                        track: track,
                        playbackManager: playbackManager
                    ))
                    hostingView.identifier = identifier
                    return hostingView
                }

            case .special(.duration):
                let text = formatDuration(track.duration)
                return makeOrReuseTextCell(
                    in: tableView,
                    column: tableColumn,
                    row: row,
                    text: text,
                    font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .regular),
                    color: NSColor.secondaryLabelColor,
                    alignment: .right
                )
            
            case .special(.trackNumber):
                let trackNumber = track.trackNumber
                
                var displayText = ""
                if let num = trackNumber {
                    displayText = "\(num)"
                }
                
                return makeOrReuseTextCell(
                    in: tableView,
                    column: tableColumn,
                    row: row,
                    text: displayText,
                    font: .systemFont(ofSize: 12),
                    color: .secondaryLabelColor,
                    alignment: .center
                )

            case .libraryFilter(let filterType):
                let value = filterType.getValue(from: track)
                return makeOrReuseTextCell(
                    in: tableView,
                    column: tableColumn,
                    row: row,
                    text: value,
                    font: NSFont.systemFont(ofSize: 13),
                    color: NSColor.labelColor
                )
            }
        }

        func tableView(_ tableView: NSTableView, sortDescriptorsDidChange oldDescriptors: [NSSortDescriptor]) {
            // For playlists with date added sorting, don't apply table sorting
            if let playlistID = playlistID {
                let sortCriteria = playlistSortManager.getSortCriteria(for: playlistID)
                if sortCriteria == .dateAdded {
                    // Clear sort descriptors to show we're not sorting by any column
                    tableView.sortDescriptors = []
                    // Keep the original track order
                    sortedTracks = tracks
                    tableView.reloadData()
                    return
                }
            }
            
            guard let descriptor = tableView.sortDescriptors.first,
                  let key = descriptor.key else {
                sortedTracks = tracks
                tableView.reloadData()
                return
            }

            // Only sort if the descriptors actually changed
            if oldDescriptors.first?.key == key &&
               oldDescriptors.first?.ascending == descriptor.ascending {
                return
            }

            let sortKey = key
            let ascending = descriptor.ascending

            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                guard let self = self else { return }

                let sorted = self.tracks.sorted { track1, track2 in
                    var result: ComparisonResult = .orderedSame

                    switch sortKey {
                    case "title":
                        result = track1.title.localizedCaseInsensitiveCompare(track2.title)
                    case "artist":
                        result = track1.artist.localizedCaseInsensitiveCompare(track2.artist)
                    case "album":
                        result = track1.album.localizedCaseInsensitiveCompare(track2.album)
                    case "album_artist":
                        let albumArtist1 = track1.albumArtist ?? ""
                        let albumArtist2 = track2.albumArtist ?? ""
                        result = albumArtist1.localizedCaseInsensitiveCompare(albumArtist2)
                    case "composer":
                        result = track1.composer.localizedCaseInsensitiveCompare(track2.composer)
                    case "genre":
                        result = track1.genre.localizedCaseInsensitiveCompare(track2.genre)
                    case "year":
                        result = track1.year.localizedCaseInsensitiveCompare(track2.year)
                    case "duration":
                        result = track1.duration < track2.duration ? .orderedAscending :
                                 track1.duration > track2.duration ? .orderedDescending : .orderedSame
                    case "trackNumber":
                        let track1Number = track1.trackNumber ?? Int.max
                        let track2Number = track2.trackNumber ?? Int.max
                        result = track1Number < track2Number ? .orderedAscending :
                                 track1Number > track2Number ? .orderedDescending : .orderedSame
                    default:
                        result = .orderedSame
                    }

                    return ascending ? result == .orderedAscending : result == .orderedDescending
                }

                DispatchQueue.main.async {
                    self.sortedTracks = sorted
                    tableView.reloadData()
                    self.saveSortOrder(key: sortKey, ascending: ascending)
                }
            }
        }

        func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
            let rowView = HoverableTableRowView()
            rowView.coordinator = self
            rowView.row = row
            return rowView
        }

        func tableView(_ tableView: NSTableView, menuFor event: NSEvent) -> NSMenu? {
            Logger.info("Context menu requested")

            let point = tableView.convert(event.locationInWindow, from: nil)
            let row = tableView.row(at: point)

            Logger.info("Row clicked: \(row)")

            guard row >= 0, row < sortedTracks.count else { return nil }

            let track = sortedTracks[row]
            let menuItems = contextMenuItems(track)

            Logger.info("Menu items count: \(menuItems.count)")

            // If the clicked row isn't selected, select it
            if !tableView.selectedRowIndexes.contains(row) {
                tableView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
            }

            // Create NSMenu from ContextMenuItem array
            return createNSMenu(from: menuItems, track: track)
        }
        
        func tableView(_ tableView: NSTableView, didDrag tableColumn: NSTableColumn) {
            let columnOrder = tableView.tableColumns
                .dropFirst()
                .compactMap { $0.identifier.rawValue }
            
            columnManager.updateColumnOrder(columnOrder)
        }
        
        func tableViewColumnDidResize(_ notification: Notification) {
            guard let tableColumn = notification.userInfo?["NSTableColumn"] as? NSTableColumn else { return }
            
            let columnId = tableColumn.identifier.rawValue
            if columnId != "playPause" {
                DispatchQueue.main.async { [weak self] in
                    self?.columnManager.setColumnWidth(columnId, width: tableColumn.width)
                }
            }
        }

        func handleContextMenu(for event: NSEvent, in tableView: NSTableView) -> NSMenu? {
            let point = tableView.convert(event.locationInWindow, from: nil)
            let row = tableView.row(at: point)

            guard row >= 0, row < sortedTracks.count else { return nil }

            let track = sortedTracks[row]
            let menuItems = contextMenuItems(track)

            // If the clicked row isn't selected, select it
            if !tableView.selectedRowIndexes.contains(row) {
                tableView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
            }

            // Create NSMenu from ContextMenuItem array
            return createNSMenu(from: menuItems, track: track)
        }
        
        func createColumnMenu() -> NSMenu {
            let menu = NSMenu()
            
            for column in TrackTableColumn.allColumns {
                let item = NSMenuItem()
                item.title = column.displayName
                item.state = columnManager.isVisible(column) ? .on : .off
                
                if column.isRequired {
                    // For required columns, set action to nil and disable
                    item.action = nil
                    item.target = nil
                    item.isEnabled = false
                } else {
                    // For optional columns, set the action and target
                    item.action = #selector(toggleColumnVisibility(_:))
                    item.target = self
                    item.representedObject = column
                }
                
                menu.addItem(item)
            }
            
            return menu
        }

        @objc
        private func toggleColumnVisibility(_ sender: NSMenuItem) {
            guard let column = sender.representedObject as? TrackTableColumn else { return }
            
            if !column.isRequired {
                columnManager.toggleVisibility(column)

                if let tableView = hostTableView {
                    updateColumnVisibility(tableView: tableView)
                }
            }
        }

        @objc
        private func scrollViewDidScroll(_ notification: Notification) {
            // Clear hover state immediately when scrolling starts
            if let previousHoveredRow = hoveredRow {
                hoveredRow = nil
                
                // Update the row to remove hover effects
                if let tableView = hostTableView {
                    // Update play/pause column for the previously hovered row
                    let playPauseColumnIndex = tableView.column(withIdentifier: NSUserInterfaceItemIdentifier("playPause"))
                    if playPauseColumnIndex >= 0 && previousHoveredRow < tableView.numberOfRows {
                        tableView.reloadData(
                            forRowIndexes: IndexSet(integer: previousHoveredRow),
                            columnIndexes: IndexSet(integer: playPauseColumnIndex)
                        )
                    }
                }
            }
        }

        @objc
        func doubleClick(_ sender: NSTableView) {
            let clickedRow = sender.clickedRow
            guard clickedRow >= 0, clickedRow < tracks.count else { return }

            let track = sortedTracks[clickedRow]
            handlePlayTrack(track)
        }
        
        private func handlePlayTrack(_ track: Track) {
            let previousTrack = playbackManager.currentTrack
            
            // Check if this is a playlist context
            if let playlistID = playlistID,
               let playlist = playlistManager.playlists.first(where: { $0.id == playlistID }) {
                if let originalIndex = playlist.tracks.firstIndex(where: { $0.id == track.id }) {
                    playlistManager.playTrackFromPlaylist(playlist, at: originalIndex)
                }
            } else {
                playlistManager.playTrack(track, fromTracks: sortedTracks)
                playlistManager.currentQueueSource = .library
            }
            
            if previousTrack == nil {
                DispatchQueue.main.async { [weak self] in
                    self?.updatePlayingIndicator()
                }
            }
        }

        private func createNSMenu(from items: [ContextMenuItem], track: Track) -> NSMenu {
            let menu = NSMenu()

            for item in items {
                switch item {
                case .button(let title, let role, let action):
                    let menuItem = NSMenuItem(title: title, action: #selector(contextMenuAction(_:)), keyEquivalent: "")
                    menuItem.target = self
                    menuItem.representedObject = ContextMenuAction(action: action, track: track)

                    // Set attributes for destructive role
                    if role == .destructive {
                        menuItem.attributedTitle = NSAttributedString(
                            string: title,
                            attributes: [.foregroundColor: NSColor.systemRed]
                        )
                    }

                    menu.addItem(menuItem)

                case .menu(let title, let subItems):
                    let submenuItem = NSMenuItem(title: title, action: nil, keyEquivalent: "")
                    let submenu = createNSMenu(from: subItems, track: track)
                    submenu.title = title
                    submenuItem.submenu = submenu
                    menu.addItem(submenuItem)

                case .divider:
                    menu.addItem(NSMenuItem.separator())
                }
            }

            return menu
        }

        // Helper class to store the action closure
        private class ContextMenuAction {
            let action: () -> Void
            let track: Track

            init(action: @escaping () -> Void, track: Track) {
                self.action = action
                self.track = track
            }
        }

        private func saveSortOrder(key: String, ascending: Bool) {
            if let playlistID = playlistID {
                // For playlists, update the sort manager
                if key == "title" {
                    playlistSortManager.setSortCriteria(.title, for: playlistID)
                } else {
                    // Any other column triggers custom sorting
                    playlistSortManager.setCustomSortColumn(key, for: playlistID)
                }
                playlistSortManager.setSortAscending(ascending, for: playlistID)
            } else {
                // For non-playlist views, use the existing behavior
                let storage = ["key": key, "ascending": ascending] as [String: Any]
                UserDefaults.standard.set(storage, forKey: "trackTableSortOrder")
            }
        }

        private func formatDuration(_ seconds: Double) -> String {
            let totalSeconds = Int(max(0, seconds))
            let minutes = totalSeconds / 60
            let remainingSeconds = totalSeconds % 60
            return String(format: StringFormat.mmss, minutes, remainingSeconds)
        }

        @objc
        private func contextMenuAction(_ sender: NSMenuItem) {
            guard let action = sender.representedObject as? ContextMenuAction else { return }
            action.action()
        }

        private func updatePlayingIndicator() {
            guard let tableView = hostTableView else { return }
            
            // Clear any stale hover states first
            if let currentHoveredRow = hoveredRow {
                let windowPoint = NSEvent.mouseLocation
                let viewPoint = tableView.window?.convertPoint(fromScreen: windowPoint) ?? .zero
                let localPoint = tableView.convert(viewPoint, from: nil)
                let actualRow = tableView.row(at: localPoint)
                
                // If the mouse is not actually over the hovered row, clear it
                if actualRow != currentHoveredRow {
                    hoveredRow = nil
                    
                    // Update the stale hovered row
                    let playPauseColumnIndex = tableView.column(withIdentifier: NSUserInterfaceItemIdentifier("playPause"))
                    if playPauseColumnIndex >= 0 {
                        tableView.reloadData(
                            forRowIndexes: IndexSet(integer: currentHoveredRow),
                            columnIndexes: IndexSet(integer: playPauseColumnIndex)
                        )
                    }
                }
            }

            // Find and update the currently playing track row
            if let currentTrack = playbackManager.currentTrack,
               let index = sortedTracks.firstIndex(where: { $0.url.path == currentTrack.url.path }) {
                // Update both the play/pause column and title column
                let columnsToUpdate = ["playPause", "title"]

                for columnID in columnsToUpdate {
                    let columnIndex = tableView.column(withIdentifier: NSUserInterfaceItemIdentifier(columnID))
                    if columnIndex >= 0 {
                        tableView.reloadData(
                            forRowIndexes: IndexSet(integer: index),
                            columnIndexes: IndexSet(integer: columnIndex)
                        )
                    }
                }
            }
        }

        private func makeOrReuseTextCell(
            in tableView: NSTableView,
            column: NSTableColumn?,
            row: Int,
            text: String,
            font: NSFont,
            color: NSColor,
            alignment: NSTextAlignment = .left
        ) -> NSTableCellView {
            let identifier = NSUserInterfaceItemIdentifier("TextCell")

            let cellView: NSTableCellView
            if let reusedCell = tableView.makeView(withIdentifier: identifier, owner: nil) as? NSTableCellView {
                cellView = reusedCell
                // Update existing text field
                if let textField = cellView.textField {
                    textField.stringValue = text
                    textField.font = font
                    textField.textColor = color
                    textField.alignment = alignment
                }
            } else {
                // Create new cell
                cellView = NSTableCellView()
                let textField = NSTextField(labelWithString: text)
                textField.font = font
                textField.textColor = color
                textField.alignment = alignment
                textField.lineBreakMode = .byTruncatingTail
                textField.translatesAutoresizingMaskIntoConstraints = false

                cellView.addSubview(textField)
                cellView.textField = textField

                NSLayoutConstraint.activate([
                    textField.leadingAnchor.constraint(equalTo: cellView.leadingAnchor, constant: 8),
                    textField.trailingAnchor.constraint(equalTo: cellView.trailingAnchor, constant: -8),
                    textField.centerYAnchor.constraint(equalTo: cellView.centerYAnchor)
                ])
            }

            return cellView
        }

        private func scheduleReload(for tableView: NSTableView) {
            pendingReload = true

            // Cancel existing timer
            reloadTimer?.invalidate()

            // Schedule new reload after a short delay
            reloadTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: false) { [weak self] _ in
                guard let self = self, self.pendingReload else { return }
                self.pendingReload = false
                tableView.reloadData()
            }
        }
        
        private func updateColumnVisibility(tableView: NSTableView) {
            for column in TrackTableColumn.allColumns {
                if let tableColumn = tableView.tableColumn(withIdentifier: NSUserInterfaceItemIdentifier(column.identifier)) {
                    tableColumn.isHidden = !columnManager.isVisible(column)
                }
            }
        }
        
        @objc
        private func handlePlayEntityNotification(_ notification: Notification) {
            guard !sortedTracks.isEmpty,
              let notificationEntityId = notification.userInfo?["entityId"] as? String,
              entityID?.uuidString == notificationEntityId else { return }
            
            let shuffle = notification.userInfo?["shuffle"] as? Bool ?? false
            playlistManager.isShuffleEnabled = shuffle
            
            var tracksForPlayback = sortedTracks
            if shuffle {
                tracksForPlayback.shuffle()
            }
            
            if let firstTrack = tracksForPlayback.first {
                playlistManager.playTrack(firstTrack, fromTracks: tracksForPlayback)
                playlistManager.currentQueueSource = .library
            }
        }

        @objc
        private func handlePlayPlaylistNotification(_ notification: Notification) {
            guard let notificationPlaylistID = notification.userInfo?["playlistID"] as? UUID,
                  notificationPlaylistID == playlistID,
                  !sortedTracks.isEmpty,
                  let playlist = playlistManager.playlists.first(where: { $0.id == playlistID }) else { return }
            
            let shuffle = notification.userInfo?["shuffle"] as? Bool ?? false
            playlistManager.isShuffleEnabled = shuffle
            
            var tracksForPlayback = sortedTracks
            if shuffle {
                tracksForPlayback.shuffle()
            }
            
            if let firstTrack = tracksForPlayback.first {
                playlistManager.playTrack(firstTrack, fromTracks: tracksForPlayback)
                playlistManager.currentPlaylist = playlist
                playlistManager.currentQueueSource = .playlist
            }
        }
    }

    class HoverableTableRowView: NSTableRowView {
        weak var coordinator: TrackTableView.Coordinator?
        var row: Int = -1
        private var trackingArea: NSTrackingArea?

        override init(frame frameRect: NSRect) {
            super.init(frame: frameRect)
        }

        required init?(coder: NSCoder) {
            super.init(coder: coder)
        }

        private func isMouseOverThisRow() -> Bool {
            guard let window = window,
                  let tableView = superview as? NSTableView else { return false }
            
            let mouseLocation = window.mouseLocationOutsideOfEventStream
            let localPoint = tableView.convert(mouseLocation, from: nil)
            let mouseRow = tableView.row(at: localPoint)
            
            return mouseRow == row
        }

        override func updateTrackingAreas() {
            super.updateTrackingAreas()

            if let trackingArea = trackingArea {
                removeTrackingArea(trackingArea)
            }

            let options: NSTrackingArea.Options = [.mouseEnteredAndExited, .activeInKeyWindow]
            trackingArea = NSTrackingArea(rect: bounds, options: options, owner: self, userInfo: nil)
            addTrackingArea(trackingArea!)
        }

        override func mouseEntered(with event: NSEvent) {
            guard let tableView = superview as? NSTableView,
                  row >= 0,
                  row < tableView.numberOfRows else {
                return
            }
            
            guard isMouseOverThisRow() else { return }
            
            let previousHoveredRow = coordinator?.hoveredRow
            coordinator?.hoveredRow = row
            
            let playPauseColumnIndex = tableView.column(withIdentifier: NSUserInterfaceItemIdentifier("playPause"))
            
            if playPauseColumnIndex >= 0 {
                if let previousRow = previousHoveredRow, previousRow != row {
                    tableView.reloadData(
                        forRowIndexes: IndexSet(integer: previousRow),
                        columnIndexes: IndexSet(integer: playPauseColumnIndex)
                    )
                }
                
                tableView.reloadData(
                    forRowIndexes: IndexSet(integer: row),
                    columnIndexes: IndexSet(integer: playPauseColumnIndex)
                )
            }
        }

        override func mouseExited(with event: NSEvent) {
            if coordinator?.hoveredRow == row {
                coordinator?.hoveredRow = nil
                
                // Update play button
                if let tableView = superview as? NSTableView,
                   row >= 0 && row < tableView.numberOfRows {
                    let playPauseColumnIndex = tableView.column(withIdentifier: NSUserInterfaceItemIdentifier("playPause"))
                    if playPauseColumnIndex >= 0 {
                        tableView.reloadData(
                            forRowIndexes: IndexSet(integer: row),
                            columnIndexes: IndexSet(integer: playPauseColumnIndex)
                        )
                    }
                }
            }
        }
    }
}

struct TrackTableTitleCell: View {
    let track: Track
    @ObservedObject var playbackManager: PlaybackManager
    @State private var artworkImage: NSImage?

    private var isCurrentTrack: Bool {
        guard let currentTrack = playbackManager.currentTrack else { return false }
        return currentTrack.url.path == track.url.path
    }

    private var isPlaying: Bool {
        isCurrentTrack && playbackManager.isPlaying
    }

    var body: some View {
        HStack(spacing: 8) {
            // Album artwork
            if let image = artworkImage {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 30, height: 30)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
            } else {
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.gray.opacity(0.2))
                    .frame(width: 30, height: 30)
                    .overlay(
                        Image(systemName: Icons.musicNote)
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                    )
            }

            Text(track.title)
                .font(.system(size: 13, weight: isCurrentTrack ? .medium : .regular))
                .foregroundColor(textColor)
                .lineLimit(1)

            Spacer()
        }
        .padding(.horizontal, 8)
        .frame(height: 44)
        .task(id: track.id) {
            artworkImage = nil

            await loadTrackArtworkAsync(
                from: track.albumArtworkMedium,
                into: $artworkImage,
                delay: TimeConstants.oneHundredMilliseconds
            )
        }
    }

    private var textColor: Color {
        if isCurrentTrack && isPlaying {
            return .accentColor
        } else {
            return .primary
        }
    }
}

// MARK: - Play/Pause Cell

struct PlayPauseCell: View {
    let track: Track
    let isHovered: Bool
    let playbackManager: PlaybackManager
    let onPlay: () -> Void

    private var isCurrentTrack: Bool {
        guard let currentTrack = playbackManager.currentTrack else { return false }
        return currentTrack.url.path == track.url.path
    }

    private var isPlaying: Bool {
        isCurrentTrack && playbackManager.isPlaying
    }

    var body: some View {
        ZStack {
            if isHovered || (isCurrentTrack && !playbackManager.isPlaying) {
                // Show button on hover OR when it's the current track but paused
                Button(action: {
                    if isCurrentTrack {
                        playbackManager.togglePlayPause()
                    } else {
                        onPlay()
                    }
                }) {
                    Image(systemName: isPlaying ? Icons.pauseFill : Icons.playFill)
                        .font(.system(size: 14))
                        .foregroundColor(.primary)
                }
                .buttonStyle(.plain)
                .frame(width: 32, height: 32)
            } else if isPlaying {
                PlayingIndicator()
                    .frame(width: 16)
            }
        }
        .frame(width: 32, height: 44)
        .contentShape(Rectangle())
    }
}
