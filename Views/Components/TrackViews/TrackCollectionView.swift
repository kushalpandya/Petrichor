import SwiftUI
import AppKit
import Combine

// MARK: - Base Track Collection Item

class TrackCollectionItem: NSCollectionViewItem {
    var onPlay: (() -> Void)?
    var contextMenuProvider: (() -> [ContextMenuItem])?
    var playbackManager: PlaybackManager?
    
    var isCurrentTrack = false
    var isPlaying = false
    var isHovered = false
    var trackingArea: NSTrackingArea?
    
    func configure(with track: Track, isCurrentTrack: Bool, isPlaying: Bool) {
        self.isCurrentTrack = isCurrentTrack
        self.isPlaying = isPlaying
    }
    
    func updatePlaybackState(isCurrentTrack: Bool, isPlaying: Bool) {
        self.isCurrentTrack = isCurrentTrack
        self.isPlaying = isPlaying
    }
    
    func setArtwork(_ image: NSImage) {
        // Base implementation - subclasses should override
    }
    
    @objc func playButtonTapped() {
        if isCurrentTrack {
            playbackManager?.togglePlayPause()
        } else {
            onPlay?()
        }
    }
    
    func updateTrackingAreas() {
        if let trackingArea = trackingArea {
            view.removeTrackingArea(trackingArea)
        }
        
        trackingArea = NSTrackingArea(
            rect: view.bounds,
            options: [.mouseEnteredAndExited, .activeInKeyWindow],
            owner: self,
            userInfo: nil
        )
        
        view.addTrackingArea(trackingArea!)
    }
    
    override func mouseEntered(with event: NSEvent) {
        isHovered = true
    }
    
    override func mouseExited(with event: NSEvent) {
        isHovered = false
    }
    
    func setupContextMenu() {
        view.menu = NSMenu()
        view.menu?.delegate = self
    }
    
    func formatDuration(_ seconds: Double) -> String {
        let totalSeconds = Int(max(0, seconds))
        let minutes = totalSeconds / 60
        let remainingSeconds = totalSeconds % 60
        return String(format: "%d:%02d", minutes, remainingSeconds)
    }
}

// MARK: - NSMenuDelegate

extension TrackCollectionItem: NSMenuDelegate {
    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        
        if let items = contextMenuProvider?() {
            for item in items {
                menu.addItem(createMenuItem(from: item))
            }
        }
    }
    
    private func createMenuItem(from item: ContextMenuItem) -> NSMenuItem {
        switch item {
        case .button(let title, let role, let action):
            let menuItem = NSMenuItem(title: title, action: #selector(menuItemClicked(_:)), keyEquivalent: "")
            menuItem.target = self
            menuItem.representedObject = action
            if role == .destructive {
                menuItem.attributedTitle = NSAttributedString(
                    string: title,
                    attributes: [.foregroundColor: NSColor.systemRed]
                )
            }
            return menuItem
            
        case .menu(let title, let subItems):
            let menuItem = NSMenuItem(title: title, action: nil, keyEquivalent: "")
            let submenu = NSMenu(title: title)
            for subItem in subItems {
                if case .divider = subItem {
                    submenu.addItem(NSMenuItem.separator())
                } else {
                    submenu.addItem(createMenuItem(from: subItem))
                }
            }
            menuItem.submenu = submenu
            return menuItem
            
        case .divider:
            return NSMenuItem.separator()
        }
    }
    
    @objc private func menuItemClicked(_ sender: NSMenuItem) {
        if let action = sender.representedObject as? () -> Void {
            action()
        }
    }
}

// MARK: - List Item

class TrackCollectionListItem: TrackCollectionItem {
    private var containerView: NSView!
    private var hoverView: NSView!
    private var playButtonContainer: NSView!
    private var playButton: NSButton!
    private var playingIndicator: NSImageView!
    private var artworkImageView: NSImageView!
    private var titleLabel: NSTextField!
    private var detailsLabel: NSTextField!
    private var durationLabel: NSTextField!
    
    override func loadView() {
        view = NSView()
        view.wantsLayer = true
        setupViews()
    }
    
    private func setupViews() {
        // Container setup
        containerView = NSView()
        containerView.wantsLayer = true
        containerView.layer?.cornerRadius = 6
        
        // Hover view
        hoverView = NSView()
        hoverView.wantsLayer = true
        hoverView.layer?.cornerRadius = 6
        hoverView.layer?.backgroundColor = NSColor.clear.cgColor
        
        // Play button container
        playButtonContainer = NSView()
        playButtonContainer.wantsLayer = true
        
        // Play button
        playButton = NSButton()
        playButton.isBordered = false
        playButton.bezelStyle = .regularSquare
        playButton.imagePosition = .imageOnly
        playButton.target = self
        playButton.action = #selector(playButtonTapped)
        
        // Playing indicator
        playingIndicator = NSImageView()
        playingIndicator.imageScaling = .scaleProportionallyUpOrDown
        
        // Artwork
        artworkImageView = NSImageView()
        artworkImageView.imageScaling = .scaleProportionallyUpOrDown
        artworkImageView.wantsLayer = true
        artworkImageView.layer?.cornerRadius = 4
        artworkImageView.layer?.masksToBounds = true
        
        // Title label
        titleLabel = NSTextField()
        titleLabel.isBordered = false
        titleLabel.isEditable = false
        titleLabel.backgroundColor = .clear
        titleLabel.font = .systemFont(ofSize: 14)
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.maximumNumberOfLines = 1
        
        // Details label
        detailsLabel = NSTextField()
        detailsLabel.isBordered = false
        detailsLabel.isEditable = false
        detailsLabel.backgroundColor = .clear
        detailsLabel.font = .systemFont(ofSize: 12)
        detailsLabel.textColor = .secondaryLabelColor
        detailsLabel.lineBreakMode = .byTruncatingTail
        detailsLabel.maximumNumberOfLines = 1
        
        // Duration label
        durationLabel = NSTextField()
        durationLabel.isBordered = false
        durationLabel.isEditable = false
        durationLabel.backgroundColor = .clear
        durationLabel.font = .systemFont(ofSize: 12)
        durationLabel.textColor = .secondaryLabelColor
        durationLabel.alignment = .right
        
        // Add subviews
        view.addSubview(containerView)
        containerView.addSubview(hoverView)
        containerView.addSubview(playButtonContainer)
        playButtonContainer.addSubview(playButton)
        playButtonContainer.addSubview(playingIndicator)
        containerView.addSubview(artworkImageView)
        containerView.addSubview(titleLabel)
        containerView.addSubview(detailsLabel)
        containerView.addSubview(durationLabel)
        
        setupConstraints()
        setupContextMenu()
    }
    
    private func setupConstraints() {
        containerView.translatesAutoresizingMaskIntoConstraints = false
        hoverView.translatesAutoresizingMaskIntoConstraints = false
        playButtonContainer.translatesAutoresizingMaskIntoConstraints = false
        playButton.translatesAutoresizingMaskIntoConstraints = false
        playingIndicator.translatesAutoresizingMaskIntoConstraints = false
        artworkImageView.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        detailsLabel.translatesAutoresizingMaskIntoConstraints = false
        durationLabel.translatesAutoresizingMaskIntoConstraints = false
        
        NSLayoutConstraint.activate([
            // Container
            containerView.topAnchor.constraint(equalTo: view.topAnchor),
            containerView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            containerView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            containerView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            
            // Hover view
            hoverView.topAnchor.constraint(equalTo: containerView.topAnchor),
            hoverView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            hoverView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
            hoverView.bottomAnchor.constraint(equalTo: containerView.bottomAnchor),
            
            // Play button container
            playButtonContainer.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: 8),
            playButtonContainer.centerYAnchor.constraint(equalTo: containerView.centerYAnchor),
            playButtonContainer.widthAnchor.constraint(equalToConstant: 40),
            playButtonContainer.heightAnchor.constraint(equalToConstant: 40),
            
            // Play button (centered in container)
            playButton.centerXAnchor.constraint(equalTo: playButtonContainer.centerXAnchor),
            playButton.centerYAnchor.constraint(equalTo: playButtonContainer.centerYAnchor),
            playButton.widthAnchor.constraint(equalToConstant: 24),
            playButton.heightAnchor.constraint(equalToConstant: 24),
            
            // Playing indicator (centered in container)
            playingIndicator.centerXAnchor.constraint(equalTo: playButtonContainer.centerXAnchor),
            playingIndicator.centerYAnchor.constraint(equalTo: playButtonContainer.centerYAnchor),
            playingIndicator.widthAnchor.constraint(equalToConstant: 16),
            playingIndicator.heightAnchor.constraint(equalToConstant: 16),
            
            // Artwork
            artworkImageView.leadingAnchor.constraint(equalTo: playButtonContainer.trailingAnchor, constant: 8),
            artworkImageView.centerYAnchor.constraint(equalTo: containerView.centerYAnchor),
            artworkImageView.widthAnchor.constraint(equalToConstant: 44),
            artworkImageView.heightAnchor.constraint(equalToConstant: 44),
            
            // Title label
            titleLabel.leadingAnchor.constraint(equalTo: artworkImageView.trailingAnchor, constant: 12),
            titleLabel.topAnchor.constraint(equalTo: containerView.topAnchor, constant: 10),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: durationLabel.leadingAnchor, constant: -8),
            
            // Details label
            detailsLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            detailsLabel.bottomAnchor.constraint(equalTo: containerView.bottomAnchor, constant: -10),
            detailsLabel.trailingAnchor.constraint(lessThanOrEqualTo: durationLabel.leadingAnchor, constant: -8),
            
            // Duration label
            durationLabel.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -16),
            durationLabel.centerYAnchor.constraint(equalTo: containerView.centerYAnchor),
            durationLabel.widthAnchor.constraint(equalToConstant: 45),
        ])
    }
    
    override func configure(with track: Track, isCurrentTrack: Bool, isPlaying: Bool) {
        super.configure(with: track, isCurrentTrack: isCurrentTrack, isPlaying: isPlaying)
        
        // Configure labels
        titleLabel.stringValue = track.title
        titleLabel.textColor = isCurrentTrack ? .controlAccentColor : .labelColor
        titleLabel.font = .systemFont(ofSize: 14, weight: isCurrentTrack ? .medium : .regular)
        
        // Build details string
        var details = [track.artist]
        if !track.album.isEmpty && track.album != "Unknown Album" {
            details.append(track.album)
        }
        if !track.year.isEmpty && track.year != "Unknown Year" {
            details.append(track.year)
        }
        detailsLabel.stringValue = details.joined(separator: " • ")
        
        // Duration
        durationLabel.stringValue = formatDuration(track.duration)
        
        // Set placeholder artwork
        if track.isMetadataLoaded {
            artworkImageView.image = NSImage(systemSymbolName: "music.note", accessibilityDescription: "Album Art")
            artworkImageView.layer?.backgroundColor = NSColor.systemGray.withAlphaComponent(0.2).cgColor
        } else {
            artworkImageView.image = nil
            artworkImageView.layer?.backgroundColor = NSColor.systemGray.withAlphaComponent(0.1).cgColor
        }
        
        // Update icons
        playingIndicator.image = NSImage(systemSymbolName: "speaker.wave.3.fill", accessibilityDescription: "Playing")
        playingIndicator.contentTintColor = .controlAccentColor
        
        updatePlaybackState(isCurrentTrack: isCurrentTrack, isPlaying: isPlaying)
        updateTrackingAreas()
    }
    
    override func setArtwork(_ image: NSImage) {
        artworkImageView.image = image
        artworkImageView.layer?.backgroundColor = NSColor.clear.cgColor
    }
    
    override func updatePlaybackState(isCurrentTrack: Bool, isPlaying: Bool) {
        super.updatePlaybackState(isCurrentTrack: isCurrentTrack, isPlaying: isPlaying)
        
        // Update title color
        titleLabel.textColor = isCurrentTrack ? .controlAccentColor : .labelColor
        titleLabel.font = .systemFont(ofSize: 14, weight: isCurrentTrack ? .medium : .regular)
        
        // Update play button visibility
        updateButtonVisibility()
        
        // Update background
        updateBackground()
    }
    
    private func updateButtonVisibility() {
        let shouldShowPlayButton = isHovered || (isCurrentTrack && !isPlaying)
        let shouldShowIndicator = isCurrentTrack && isPlaying && !isHovered
        
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.15
            context.allowsImplicitAnimation = true
            
            // Show play/pause button when hovering or when it's the current track but paused
            self.playButton.animator().alphaValue = shouldShowPlayButton ? 1 : 0
            
            // Show playing indicator only when playing and not hovering
            self.playingIndicator.animator().alphaValue = shouldShowIndicator ? 1 : 0
        }
        
        // Update play button icon
        let icon = isCurrentTrack && isPlaying ? "pause.fill" : "play.fill"
        playButton.image = NSImage(systemSymbolName: icon, accessibilityDescription: isCurrentTrack && isPlaying ? "Pause" : "Play")
        playButton.contentTintColor = isCurrentTrack ? .controlAccentColor : .labelColor
    }
    
    private func updateBackground() {
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.1
            context.allowsImplicitAnimation = true
            
            if isPlaying {
                hoverView.layer?.backgroundColor = isHovered ?
                    NSColor.selectedContentBackgroundColor.withAlphaComponent(0.08).cgColor :
                    NSColor.clear.cgColor
            } else if isHovered {
                hoverView.layer?.backgroundColor = NSColor.selectedContentBackgroundColor.withAlphaComponent(0.15).cgColor
            } else {
                hoverView.layer?.backgroundColor = NSColor.clear.cgColor
            }
        }
    }
    
    override func mouseEntered(with event: NSEvent) {
        super.mouseEntered(with: event)
        updateButtonVisibility()
        updateBackground()
    }
    
    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        updateButtonVisibility()
        updateBackground()
    }
}

// MARK: - Grid Item

class TrackCollectionGridItem: TrackCollectionItem {
    private var containerView: NSView!
    private var imageContainerView: NSView!
    private var artworkImageView: NSImageView!
    private var hoverView: NSView!
    private var playButton: NSButton!
    private var playingIndicator: NSImageView!
    private var titleLabel: NSTextField!
    private var artistLabel: NSTextField!
    private var albumLabel: NSTextField!
    
    override func loadView() {
        view = NSView()
        view.wantsLayer = true
        setupViews()
    }
    
    private func setupViews() {
        // Container
        containerView = NSView()
        containerView.wantsLayer = true
        containerView.layer?.cornerRadius = 10
        
        // Image container
        imageContainerView = NSView()
        imageContainerView.wantsLayer = true
        imageContainerView.layer?.cornerRadius = 8
        imageContainerView.layer?.masksToBounds = true
        imageContainerView.layer?.backgroundColor = NSColor.systemGray.withAlphaComponent(0.2).cgColor
        
        // Image view
        artworkImageView = NSImageView()
        artworkImageView.imageScaling = .scaleProportionallyUpOrDown
        artworkImageView.wantsLayer = true
        
        // Hover view
        hoverView = NSView()
        hoverView.wantsLayer = true
        hoverView.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.4).cgColor
        hoverView.layer?.cornerRadius = 8
        hoverView.alphaValue = 0
        
        // Play button
        playButton = NSButton()
        playButton.isBordered = false
        playButton.bezelStyle = .regularSquare
        playButton.image = NSImage(systemSymbolName: "play.fill", accessibilityDescription: "Play")?.withSymbolConfiguration(.init(pointSize: 24, weight: .medium))
        playButton.contentTintColor = .white
        playButton.alphaValue = 0
        playButton.target = self
        playButton.action = #selector(playButtonTapped)
        
        // Configure button background
        playButton.wantsLayer = true
        playButton.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.6).cgColor
        playButton.layer?.cornerRadius = 22
        
        // Playing indicator
        playingIndicator = NSImageView()
        playingIndicator.imageScaling = .scaleProportionallyUpOrDown
        playingIndicator.image = NSImage(systemSymbolName: "speaker.wave.3.fill", accessibilityDescription: "Playing")
        playingIndicator.contentTintColor = .controlAccentColor
        playingIndicator.wantsLayer = true
        playingIndicator.alphaValue = 0
        
        // Title label
        titleLabel = NSTextField()
        titleLabel.isBordered = false
        titleLabel.isEditable = false
        titleLabel.backgroundColor = .clear
        titleLabel.font = .systemFont(ofSize: 14)
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.maximumNumberOfLines = 2
        
        // Artist label
        artistLabel = NSTextField()
        artistLabel.isBordered = false
        artistLabel.isEditable = false
        artistLabel.backgroundColor = .clear
        artistLabel.font = .systemFont(ofSize: 12)
        artistLabel.textColor = .secondaryLabelColor
        artistLabel.lineBreakMode = .byTruncatingTail
        artistLabel.maximumNumberOfLines = 1
        
        // Album label
        albumLabel = NSTextField()
        albumLabel.isBordered = false
        albumLabel.isEditable = false
        albumLabel.backgroundColor = .clear
        albumLabel.font = .systemFont(ofSize: 11)
        albumLabel.textColor = .secondaryLabelColor
        albumLabel.lineBreakMode = .byTruncatingTail
        albumLabel.maximumNumberOfLines = 1
        
        // Add subviews
        view.addSubview(containerView)
        containerView.addSubview(imageContainerView)
        imageContainerView.addSubview(artworkImageView)
        imageContainerView.addSubview(hoverView)
        imageContainerView.addSubview(playButton)
        imageContainerView.addSubview(playingIndicator)
        containerView.addSubview(titleLabel)
        containerView.addSubview(artistLabel)
        containerView.addSubview(albumLabel)
        
        setupConstraints()
        setupContextMenu()
    }
    
    private func setupConstraints() {
        containerView.translatesAutoresizingMaskIntoConstraints = false
        imageContainerView.translatesAutoresizingMaskIntoConstraints = false
        artworkImageView.translatesAutoresizingMaskIntoConstraints = false
        hoverView.translatesAutoresizingMaskIntoConstraints = false
        playButton.translatesAutoresizingMaskIntoConstraints = false
        playingIndicator.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        artistLabel.translatesAutoresizingMaskIntoConstraints = false
        albumLabel.translatesAutoresizingMaskIntoConstraints = false
        
        NSLayoutConstraint.activate([
            // Container
            containerView.topAnchor.constraint(equalTo: view.topAnchor),
            containerView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            containerView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            containerView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            
            // Image container
            imageContainerView.topAnchor.constraint(equalTo: containerView.topAnchor),
            imageContainerView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            imageContainerView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
            imageContainerView.heightAnchor.constraint(equalToConstant: 160),
            
            // Artwork image
            artworkImageView.topAnchor.constraint(equalTo: imageContainerView.topAnchor),
            artworkImageView.leadingAnchor.constraint(equalTo: imageContainerView.leadingAnchor),
            artworkImageView.trailingAnchor.constraint(equalTo: imageContainerView.trailingAnchor),
            artworkImageView.bottomAnchor.constraint(equalTo: imageContainerView.bottomAnchor),
            
            // Hover view
            hoverView.topAnchor.constraint(equalTo: imageContainerView.topAnchor),
            hoverView.leadingAnchor.constraint(equalTo: imageContainerView.leadingAnchor),
            hoverView.trailingAnchor.constraint(equalTo: imageContainerView.trailingAnchor),
            hoverView.bottomAnchor.constraint(equalTo: imageContainerView.bottomAnchor),
            
            // Play button (centered)
            playButton.centerXAnchor.constraint(equalTo: imageContainerView.centerXAnchor),
            playButton.centerYAnchor.constraint(equalTo: imageContainerView.centerYAnchor),
            playButton.widthAnchor.constraint(equalToConstant: 44),
            playButton.heightAnchor.constraint(equalToConstant: 44),
            
            // Playing indicator (top right)
            playingIndicator.topAnchor.constraint(equalTo: imageContainerView.topAnchor, constant: 8),
            playingIndicator.trailingAnchor.constraint(equalTo: imageContainerView.trailingAnchor, constant: -8),
            playingIndicator.widthAnchor.constraint(equalToConstant: 16),
            playingIndicator.heightAnchor.constraint(equalToConstant: 16),
            
            // Title label
            titleLabel.topAnchor.constraint(equalTo: imageContainerView.bottomAnchor, constant: 8),
            titleLabel.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            titleLabel.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
            
            // Artist label
            artistLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 4),
            artistLabel.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            artistLabel.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
            
            // Album label
            albumLabel.topAnchor.constraint(equalTo: artistLabel.bottomAnchor, constant: 2),
            albumLabel.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            albumLabel.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
        ])
    }
    
    override func configure(with track: Track, isCurrentTrack: Bool, isPlaying: Bool) {
        super.configure(with: track, isCurrentTrack: isCurrentTrack, isPlaying: isPlaying)
        
        // Configure labels
        titleLabel.stringValue = track.title
        titleLabel.textColor = isCurrentTrack ? .controlAccentColor : .labelColor
        titleLabel.font = .systemFont(ofSize: 14, weight: isCurrentTrack ? .medium : .regular)
        
        artistLabel.stringValue = track.artist
        
        // Only show album if it's not "Unknown Album"
        if !track.album.isEmpty && track.album != "Unknown Album" {
            albumLabel.stringValue = track.album
            albumLabel.isHidden = false
        } else {
            albumLabel.isHidden = true
        }
        
        // Set placeholder image
        if track.isMetadataLoaded {
            artworkImageView.image = NSImage(systemSymbolName: "music.note", accessibilityDescription: "Album Art")
        } else {
            artworkImageView.image = nil
        }
        
        updatePlaybackState(isCurrentTrack: isCurrentTrack, isPlaying: isPlaying)
        updateTrackingAreas()
    }
    
    override func setArtwork(_ image: NSImage) {
        artworkImageView.image = image
        artworkImageView.layer?.backgroundColor = NSColor.clear.cgColor
    }
    
    override func updatePlaybackState(isCurrentTrack: Bool, isPlaying: Bool) {
        super.updatePlaybackState(isCurrentTrack: isCurrentTrack, isPlaying: isPlaying)
        
        // Update title color
        titleLabel.textColor = isCurrentTrack ? .controlAccentColor : .labelColor
        titleLabel.font = .systemFont(ofSize: 14, weight: isCurrentTrack ? .medium : .regular)
        
        // Update play button visibility
        updateButtonVisibility()
        
        // Update background
        updateBackground()
    }
    
    private func updateButtonVisibility() {
        let shouldShowPlayButton = isHovered || (isCurrentTrack && !isPlaying)
        let shouldShowIndicator = isCurrentTrack && isPlaying && !isHovered
        
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.15
            context.allowsImplicitAnimation = true
            
            self.playButton.animator().alphaValue = shouldShowPlayButton ? 1 : 0
            self.playingIndicator.animator().alphaValue = shouldShowIndicator ? 1 : 0
            self.hoverView.animator().alphaValue = self.isHovered ? 1 : 0
        }
        
        // Update play button icon
        let icon = isCurrentTrack && isPlaying ? "pause.fill" : "play.fill"
        playButton.image = NSImage(systemSymbolName: icon, accessibilityDescription: isCurrentTrack && isPlaying ? "Pause" : "Play")?.withSymbolConfiguration(.init(pointSize: 24, weight: .medium))
    }
    
    private func updateBackground() {
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.1
            context.allowsImplicitAnimation = true
            
            if isPlaying {
                containerView.layer?.backgroundColor = isHovered ?
                    NSColor.selectedContentBackgroundColor.withAlphaComponent(0.08).cgColor :
                    NSColor.clear.cgColor
            } else if isHovered {
                containerView.layer?.backgroundColor = NSColor.selectedContentBackgroundColor.withAlphaComponent(0.15).cgColor
            } else {
                containerView.layer?.backgroundColor = NSColor.clear.cgColor
            }
        }
    }
    
    override func mouseEntered(with event: NSEvent) {
        super.mouseEntered(with: event)
        updateButtonVisibility()
        updateBackground()
    }
    
    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        updateButtonVisibility()
        updateBackground()
    }
}

// MARK: - TrackCollectionView

struct TrackCollectionView: NSViewRepresentable {
    let tracks: [Track]
    let viewType: LibraryViewType
    let onPlayTrack: (Track) -> Void
    let contextMenuItems: (Track) -> [ContextMenuItem]
    
    @EnvironmentObject var playbackManager: PlaybackManager
    @EnvironmentObject var playlistManager: PlaylistManager
    
    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        let collectionView = NSCollectionView()
        
        // Configure collection view
        collectionView.delegate = context.coordinator
        collectionView.dataSource = context.coordinator
        collectionView.isSelectable = true
        collectionView.allowsMultipleSelection = false
        collectionView.backgroundColors = [.clear]
        
        // Set layout based on view type
        collectionView.collectionViewLayout = viewType == .list ? createListLayout() : createGridLayout()
        
        // Register item classes
        collectionView.register(TrackCollectionListItem.self, forItemWithIdentifier: NSUserInterfaceItemIdentifier("ListItem"))
        collectionView.register(TrackCollectionGridItem.self, forItemWithIdentifier: NSUserInterfaceItemIdentifier("GridItem"))
        
        scrollView.documentView = collectionView
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = false
        scrollView.backgroundColor = .clear
        
        return scrollView
    }
    
    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let collectionView = scrollView.documentView as? NSCollectionView else { return }
        
        context.coordinator.tracks = tracks
        context.coordinator.playbackManager = playbackManager
        context.coordinator.playlistManager = playlistManager
        context.coordinator.viewType = viewType
        
        // Update layout if view type changed
        if context.coordinator.lastViewType != viewType {
            // Set layout based on view type
            collectionView.collectionViewLayout = viewType == .list ? createListLayout() : createGridLayout()
            context.coordinator.lastViewType = viewType

            // Force complete reload on layout change
            collectionView.reloadData()
        } else if context.coordinator.hasDataChanged {
            // Smart reload
            collectionView.reloadData()
            context.coordinator.hasDataChanged = false
        } else {
            // Update only visible items for playback state changes
            context.coordinator.updateVisibleItems(in: collectionView)
        }
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    // MARK: - Layouts
    
    private func createListLayout() -> NSCollectionViewLayout {
        let itemSize = NSCollectionLayoutSize(
            widthDimension: .fractionalWidth(1.0),
            heightDimension: .absolute(60)
        )
        let item = NSCollectionLayoutItem(layoutSize: itemSize)
        
        let groupSize = NSCollectionLayoutSize(
            widthDimension: .fractionalWidth(1.0),
            heightDimension: .absolute(60)
        )
        let group = NSCollectionLayoutGroup.horizontal(layoutSize: groupSize, subitems: [item])
        
        let section = NSCollectionLayoutSection(group: group)
        section.interGroupSpacing = 0
        
        return NSCollectionViewCompositionalLayout(section: section)
    }
    
    private func createGridLayout() -> NSCollectionViewLayout {
        let flowLayout = NSCollectionViewFlowLayout()
        flowLayout.itemSize = NSSize(width: 180, height: 240)
        flowLayout.minimumLineSpacing = 16
        flowLayout.minimumInteritemSpacing = 16
        flowLayout.sectionInset = NSEdgeInsets(top: 16, left: 16, bottom: 16, right: 16)
        return flowLayout
    }
    
    // MARK: - Coordinator
    
    class Coordinator: NSObject, NSCollectionViewDataSource, NSCollectionViewDelegate {
        let parent: TrackCollectionView
        var tracks: [Track] = []
        var playbackManager: PlaybackManager?
        var playlistManager: PlaylistManager?
        var viewType: LibraryViewType = .list
        var lastViewType: LibraryViewType = .list
        var hasDataChanged = true
        
        // Track playback state
        private var currentlyPlayingPath: String?
        private var isPlaying: Bool = false
        private var playbackCancellable: AnyCancellable?
        
        // Cache for album artwork
        private let artworkCache = NSCache<NSString, NSImage>()
        
        init(_ parent: TrackCollectionView) {
            self.parent = parent
            super.init()
            artworkCache.countLimit = 500
            
            // Observe playback changes
            playbackCancellable = NotificationCenter.default.publisher(for: NSNotification.Name("PlaybackStateChanged"))
                .receive(on: DispatchQueue.main)
                .sink { [weak self] _ in
                    self?.handlePlaybackStateChanged()
                }
        }
        
        private func handlePlaybackStateChanged() {
            guard let playbackManager = playbackManager else { return }
            currentlyPlayingPath = playbackManager.currentTrack?.url.path
            isPlaying = playbackManager.isPlaying
            
            // Update visible cells immediately when playback state changes
            if let collectionView = NSApp.windows.first?.contentView?.subviews.compactMap({ $0 as? NSScrollView }).first?.documentView as? NSCollectionView {
                updateVisibleItems(in: collectionView)
            }
        }
        
        // MARK: - DataSource
        
        func collectionView(_ collectionView: NSCollectionView, numberOfItemsInSection section: Int) -> Int {
            tracks.count
        }
        
        func collectionView(_ collectionView: NSCollectionView, itemForRepresentedObjectAt indexPath: IndexPath) -> NSCollectionViewItem {
            let track = tracks[indexPath.item]
            let isCurrentTrack = playbackManager?.currentTrack?.url.path == track.url.path
            let isPlaying = isCurrentTrack && (playbackManager?.isPlaying ?? false)
            
            // Create the appropriate item type
            let item: TrackCollectionItem = viewType == .grid
                ? collectionView.makeItem(withIdentifier: NSUserInterfaceItemIdentifier("GridItem"), for: indexPath) as! TrackCollectionGridItem
                : collectionView.makeItem(withIdentifier: NSUserInterfaceItemIdentifier("ListItem"), for: indexPath) as! TrackCollectionListItem
            
            // Configure the item
            item.configure(with: track, isCurrentTrack: isCurrentTrack, isPlaying: isPlaying)
            item.playbackManager = self.playbackManager
            item.onPlay = { [weak self] in
                guard let self = self else { return }
                if isCurrentTrack && isPlaying {
                    self.playbackManager?.togglePlayPause()
                } else {
                    self.parent.onPlayTrack(track)
                }
            }
            item.contextMenuProvider = { [weak self] in
                guard let self = self,
                      let playbackManager = self.playbackManager,
                      let playlistManager = self.playlistManager else { return [] }
                
                return TrackContextMenu.createMenuItems(
                    for: track,
                    playbackManager: playbackManager,
                    playlistManager: playlistManager,
                    currentContext: .library
                )
            }
            
            // Load artwork
            loadArtwork(for: item, track: track, at: indexPath, in: collectionView)
            
            return item
        }
        
        // MARK: - Delegate
        
        func collectionView(_ collectionView: NSCollectionView, didSelectItemsAt indexPaths: Set<IndexPath>) {
            guard let indexPath = indexPaths.first else { return }
            let track = tracks[indexPath.item]
            let isCurrentTrack = playbackManager?.currentTrack?.url.path == track.url.path
            
            if viewType == .list || (viewType == .grid && !isCurrentTrack) {
                parent.onPlayTrack(track)
            }
            
            // Deselect immediately to allow re-selection
            collectionView.deselectItems(at: indexPaths)
        }
        
        // MARK: - Artwork Loading
        
        private func loadArtwork(for item: TrackCollectionItem, track: Track, at indexPath: IndexPath, in collectionView: NSCollectionView) {
            if let cachedImage = artworkCache.object(forKey: track.id.uuidString as NSString) {
                item.setArtwork(cachedImage)
            } else if let artworkData = track.artworkData {
                DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                    if let image = NSImage(data: artworkData) {
                        self?.artworkCache.setObject(image, forKey: track.id.uuidString as NSString)
                        DispatchQueue.main.async {
                            if let currentItem = collectionView.item(at: indexPath) as? TrackCollectionItem {
                                currentItem.setArtwork(image)
                            }
                        }
                    }
                }
            }
        }
        
        // MARK: - Update Visible Items
        
        func updateVisibleItems(in collectionView: NSCollectionView) {
            let visibleIndexPaths = collectionView.indexPathsForVisibleItems()
            
            for indexPath in visibleIndexPaths {
                guard let item = collectionView.item(at: indexPath) as? TrackCollectionItem else { continue }
                let track = tracks[indexPath.item]
                let isCurrentTrack = playbackManager?.currentTrack?.url.path == track.url.path
                let isPlaying = isCurrentTrack && (playbackManager?.isPlaying ?? false)
                
                item.updatePlaybackState(isCurrentTrack: isCurrentTrack, isPlaying: isPlaying)
            }
        }
    }
}
