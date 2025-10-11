import Foundation
import AppKit
import AVFoundation
import CoreMedia

class MetadataExtractor {
    // MARK: - Metadata Key Mappings
    
    private enum MetadataKeyType {
        case composer, genre, year, albumArtist, trackNumber, discNumber, artwork
        case copyright, bpm, comment
        
        var keys: [String] {
            switch self {
            case .composer:
                return [
                    "composer", "©wrt", "\u{00A9}wrt", "TCOM", "TCM",
                    AVMetadataKey.commonKeyCreator.rawValue,
                    AVMetadataKey.iTunesMetadataKeyComposer.rawValue,
                    AVMetadataKey.id3MetadataKeyComposer.rawValue,
                    AVMetadataKey.quickTimeMetadataKeyProducer.rawValue
                ]
            case .genre:
                return [
                    "genre", "gnre", "©gen", "\u{00A9}gen", "TCON",
                    AVMetadataKey.id3MetadataKeyContentType.rawValue,
                    AVMetadataKey.iTunesMetadataKeyUserGenre.rawValue,
                    AVMetadataKey.quickTimeMetadataKeyGenre.rawValue
                ]
            case .year:
                return [
                    "year", "date", "©day", "\u{00A9}day", "TDRC", "TYER",
                    "TYE", "TDA", "TDRL",
                    AVMetadataKey.id3MetadataKeyYear.rawValue,
                    AVMetadataKey.id3MetadataKeyRecordingTime.rawValue,
                    AVMetadataKey.iTunesMetadataKeyReleaseDate.rawValue,
                    AVMetadataKey.quickTimeMetadataKeyYear.rawValue,
                    AVMetadataKey.commonKeyCreationDate.rawValue
                ]
            case .albumArtist:
                return [
                    "TPE2", "albumartist", "album artist",
                    AVMetadataKey.iTunesMetadataKeyAlbumArtist.rawValue,
                    AVMetadataKey.id3MetadataKeyBand.rawValue
                ]
            case .trackNumber:
                return [
                    "TRCK", "tracknumber", "track", "trkn",
                    AVMetadataKey.id3MetadataKeyTrackNumber.rawValue,
                    AVMetadataKey.iTunesMetadataKeyTrackNumber.rawValue
                ]
            case .discNumber:
                return [
                    "TPOS", "discnumber", "disc", "disk",
                    AVMetadataKey.iTunesMetadataKeyDiscNumber.rawValue
                ]
            case .artwork:
                return [
                    "artwork", "covr", "apic", "pic", "cover", "albumart",
                    AVMetadataKey.commonKeyArtwork.rawValue,
                    AVMetadataKey.iTunesMetadataKeyCoverArt.rawValue,
                    AVMetadataKey.id3MetadataKeyAttachedPicture.rawValue,
                    "APIC", "PIC", "COVR"
                ]
            case .copyright:
                return [
                    "TCOP", "©cpy", "\u{00A9}cpy", "copyright",
                    AVMetadataKey.commonKeyCopyrights.rawValue,
                    AVMetadataKey.id3MetadataKeyCopyright.rawValue,
                    AVMetadataKey.iTunesMetadataKeyCopyright.rawValue
                ]
            case .bpm:
                return [
                    "TBPM", "bpm", "beatsperminute",
                    AVMetadataKey.iTunesMetadataKeyBeatsPerMin.rawValue
                ]
            case .comment:
                return [
                    "COMM", "comment", "©cmt", "\u{00A9}cmt",
                    AVMetadataKey.commonKeyDescription.rawValue,
                    AVMetadataKey.iTunesMetadataKeyUserComment.rawValue
                ]
            }
        }
        
        var searchTerms: [String] {
            switch self {
            case .composer: return ["composer", "tcom", "wrt", "©wrt", "\u{00A9}wrt"]
            case .genre: return ["genre", "gnre", "tcon", "©gen", "\u{00A9}gen"]
            case .year: return ["year", "date", "tyer", "tdrc", "©day", "\u{00A9}day"]
            case .albumArtist: return keys // Use exact matching for album artist
            case .trackNumber: return keys // Use exact matching for track number
            case .discNumber: return keys // Use exact matching for disc number
            case .artwork: return keys // User exact matching for artwork
            case .copyright: return keys // Use exact matching for copyright
            case .bpm: return keys // Use exact matching for BPM
            case .comment: return keys // Use exact matching for comment
            }
        }
    }
    
    // MARK: - Extended Field Mappings
    
    private struct ExtendedFieldMapping {
        let conditions: [(String) -> Bool]
        let action: (String, inout TrackMetadata) -> Void
        
        static let mappings: [ExtendedFieldMapping] = [
            // Label
            ExtendedFieldMapping(
                conditions: [
                    { $0.contains("label") || $0 == "tpub" }
                ]
            ) { value, metadata in metadata.extended.label = value },
            
            // ISRC
            ExtendedFieldMapping(
                conditions: [
                    { $0 == "tsrc" || $0.contains("isrc") }
                ]
            ) { value, metadata in metadata.extended.isrc = value },
            
            // Lyrics
            ExtendedFieldMapping(
                conditions: [
                    { $0 == "uslt" || $0.contains("lyrics") }
                ]
            ) { value, metadata in metadata.extended.lyrics = value },
            
            // Original Artist
            ExtendedFieldMapping(
                conditions: [
                    { $0 == "tope" || $0.contains("originalartist") }
                ]
            ) { value, metadata in metadata.extended.originalArtist = value },
            
            // Musical Key
            ExtendedFieldMapping(
                conditions: [
                    { $0 == "tkey" || $0.contains("initialkey") || $0.contains("musicalkey") }
                ]
            ) { value, metadata in metadata.extended.key = value },
            
            // Personnel
            ExtendedFieldMapping(
                conditions: [{ $0 == "tpe3" || $0.contains("conductor") }]
            ) { value, metadata in metadata.extended.conductor = value },
            ExtendedFieldMapping(
                conditions: [{ $0 == "tpe4" || $0.contains("remixer") }]
            ) { value, metadata in metadata.extended.remixer = value },
            ExtendedFieldMapping(
                conditions: [{ $0 == "tpro" || $0.contains("producer") }]
            ) { value, metadata in metadata.extended.producer = value },
            ExtendedFieldMapping(
                conditions: [{ $0.contains("engineer") }]
            ) { value, metadata in metadata.extended.engineer = value },
            ExtendedFieldMapping(
                conditions: [{ $0 == "text" || $0.contains("lyricist") }]
            ) { value, metadata in metadata.extended.lyricist = value },
            
            // Descriptive fields
            ExtendedFieldMapping(
                conditions: [{ $0.contains("subtitle") || $0 == "tit3" }]
            ) { value, metadata in metadata.extended.subtitle = value },
            ExtendedFieldMapping(
                conditions: [{ $0.contains("grouping") || $0 == "tit1" || $0 == "grp1" }]
            ) { value, metadata in metadata.extended.grouping = value },
            ExtendedFieldMapping(
                conditions: [{ $0.contains("movement") }]
            ) { value, metadata in metadata.extended.movement = value },
            ExtendedFieldMapping(
                conditions: [{ $0.contains("mood") }]
            ) { value, metadata in metadata.extended.mood = value },
            ExtendedFieldMapping(
                conditions: [{ $0 == "tlan" || $0.contains("language") }]
            ) { value, metadata in metadata.extended.language = value },
            
            // Publisher
            ExtendedFieldMapping(
                conditions: [{ $0 == "tpub" || $0.contains("publisher") }]
            ) { value, metadata in metadata.extended.publisher = value },
            
            // Identifiers
            ExtendedFieldMapping(
                conditions: [{ $0.contains("barcode") || $0.contains("upc") }]
            ) { value, metadata in metadata.extended.barcode = value },
            ExtendedFieldMapping(
                conditions: [{ $0.contains("catalog") }]
            ) { value, metadata in metadata.extended.catalogNumber = value },
            
            // Encoding
            ExtendedFieldMapping(
                conditions: [{ $0 == "tenc" || $0.contains("encodedby") }]
            ) { value, metadata in metadata.extended.encodedBy = value },
            ExtendedFieldMapping(
                conditions: [{ $0 == "tsse" || $0.contains("encodersettings") }]
            ) { value, metadata in metadata.extended.encoderSettings = value }
        ]
    }
    
    // MARK: - Public Methods
    
    @available(macOS, deprecated: 13.0)
    static func extractMetadata(from url: URL, completion: @escaping (TrackMetadata) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            let metadata = extractMetadataSync(from: url)
            DispatchQueue.main.async {
                completion(metadata)
            }
        }
    }
    
    @available(macOS, deprecated: 13.0)
    static func extractMetadataSync(from url: URL, externalArtwork: Data? = nil) -> TrackMetadata {
        let asset = AVURLAsset(url: url)
        var metadata = TrackMetadata(url: url)
        
        let semaphore = DispatchSemaphore(value: 0)
        
        asset.loadValuesAsynchronously(forKeys: ["commonMetadata", "metadata", "availableMetadataFormats", "duration", "tracks"]) {
            defer { semaphore.signal() }
            
            var error: NSError?
            let metadataStatus = asset.statusOfValue(forKey: "commonMetadata", error: &error)
            let durationStatus = asset.statusOfValue(forKey: "duration", error: &error)
            
            guard metadataStatus == .loaded && durationStatus == .loaded else { return }
            
            // Process metadata
            processMetadataItems(asset.commonMetadata, into: &metadata)
            
            for format in asset.availableMetadataFormats {
                let formatMetadata = asset.metadata(forFormat: format)
                if !formatMetadata.isEmpty {
                    processMetadataItems(formatMetadata, into: &metadata)
                }
            }
            
            // Duration
            metadata.duration = CMTimeGetSeconds(asset.duration)
            
            // Audio format info
            extractAudioFormatInfo(from: asset, into: &metadata)
        }
        
        let timeout = DispatchTime.now() + .seconds(5)
        if semaphore.wait(timeout: timeout) == .timedOut {
            Logger.error("Timeout loading metadata for \(url.lastPathComponent)")
        }
        
        if metadata.artworkData == nil, let externalArtwork = externalArtwork {
            metadata.artworkData = externalArtwork
        }
        
        return metadata
    }
    
    // MARK: - Folder-level Artwork Scanning

    /// Scans a folder and returns a map of directory URLs to their artwork data
    static func scanFolderForArtwork(at folderURL: URL) -> [URL: Data] {
        var artworkMap: [URL: Data] = [:]
        let fileManager = FileManager.default
        
        if let enumerator = fileManager.enumerator(
            at: folderURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) {
            var foundArtworkInCurrentDir = false
            var lastDirectory: URL?
            
            for case let url as URL in enumerator {
                let isDirectory = (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
                
                if isDirectory {
                    continue
                }
                
                // Get the directory containing this file
                let directory = url.deletingLastPathComponent()
                
                // Reset the flag when we move to a new directory
                if directory != lastDirectory {
                    foundArtworkInCurrentDir = false
                    lastDirectory = directory
                }
                
                // Skip if we already found artwork in this directory
                if foundArtworkInCurrentDir {
                    continue
                }
                
                // Check if this is an artwork file
                let filename = url.deletingPathExtension().lastPathComponent
                let ext = url.pathExtension
                
                if AlbumArtFormat.knownFilenames.contains(filename) && AlbumArtFormat.isSupported(ext) {
                    if let data = try? Data(contentsOf: url) {
                        artworkMap[directory] = data
                        foundArtworkInCurrentDir = true
                    }
                }
            }
        }
        
        return artworkMap
    }
    
    // MARK: - Private Methods
    
    @available(macOS, deprecated: 13.0)
    private static func processMetadataItems(_ items: [AVMetadataItem], into metadata: inout TrackMetadata) {
        for item in items {
            let keyString = getKeyString(from: item)
            let identifier = item.identifier?.rawValue ?? ""
            let commonKey = item.commonKey?.rawValue ?? ""
            
            // Special handling for track/disc numbers which might be stored as binary data
            if keyString == "trkn" || keyString.lowercased() == "track" ||
                identifier.contains("iTunesMetadataKeyTrackNumber") {
                if let data = item.dataValue, data.count >= 8 {
                    // M4A stores track numbers as binary:
                    // bytes 2-3: track number (big endian)
                    // bytes 4-5: total tracks (big endian)
                    let trackNumber = Int(data[2]) << 8 | Int(data[3])
                    let totalTracks = Int(data[4]) << 8 | Int(data[5])
                    
                    if trackNumber > 0 && metadata.trackNumber == nil {
                        metadata.trackNumber = trackNumber
                        if totalTracks > 0 {
                            metadata.totalTracks = totalTracks
                        }
                        continue  // Skip normal processing for this item
                    }
                }
            }
            
            // Similar handling for disc numbers
            if keyString == "disk" || keyString.lowercased() == "disc" ||
                identifier.contains("iTunesMetadataKeyDiscNumber") {
                if let data = item.dataValue, data.count >= 6 {
                    let discNumber = Int(data[2]) << 8 | Int(data[3])
                    let totalDiscs = Int(data[4]) << 8 | Int(data[5])
                    
                    if discNumber > 0 && metadata.discNumber == nil {
                        metadata.discNumber = discNumber
                        if totalDiscs > 0 {
                            metadata.totalDiscs = totalDiscs
                        }
                        continue
                    }
                }
            }
            
            // Continue with normal string processing
            if let stringValue = getStringValue(from: item) {
                // Process common keys
                processCommonKey(item.commonKey, value: stringValue, into: &metadata)
                
                // Process core metadata
                processCoreMetadata(
                    keyString: keyString,
                    identifier: identifier,
                    commonKey: commonKey,
                    value: stringValue,
                    into: &metadata
                )
                
                // Process extended fields
                extractExtendedFields(keyString, identifier, stringValue, into: &metadata)
            }
            
            // Handle artwork
            if isKeyOfType(.artwork, keyString, identifier, commonKey) {
                extractArtwork(from: item, into: &metadata)
            }
        }
    }
    
    private static func processCommonKey(_ commonKey: AVMetadataKey?, value: String, into metadata: inout TrackMetadata) {
        guard let commonKey = commonKey else { return }
        
        switch commonKey {
        case .commonKeyTitle where metadata.title == nil:
            metadata.title = value
        case .commonKeyArtist where metadata.artist == nil:
            metadata.artist = value
        case .commonKeyAlbumName where metadata.album == nil:
            metadata.album = value
        case .commonKeyCreator where metadata.composer == nil:
            metadata.composer = value
        default:
            break
        }
    }
    
    private static func processCoreMetadata(
        keyString: String,
        identifier: String,
        commonKey: String,
        value: String,
        into metadata: inout TrackMetadata
    ) {
        // Composer
        if metadata.composer == nil && isKeyOfType(.composer, keyString, identifier, commonKey) {
            metadata.composer = value
        }
        
        // Genre
        if metadata.genre == nil && isKeyOfType(.genre, keyString, identifier, commonKey) {
            metadata.genre = value
        }
        
        // Year
        if (metadata.year == nil || metadata.year?.isEmpty == true) &&
            isKeyOfType(.year, keyString, identifier, commonKey) {
            metadata.year = extractYear(from: value)
        }
        
        // Album Artist
        if metadata.albumArtist == nil && isKeyOfType(.albumArtist, keyString, identifier, commonKey) {
            metadata.albumArtist = value
        }
        
        // Track Number - Add special handling for simple "track" key
        if metadata.trackNumber == nil {
            let keyLower = keyString.lowercased()

            // Strict match for known valid track number fields
            let validTrackKeys = ["tracknumber", "trck", "trkn", "track"]
            let invalidTrackKeys = ["tracktotal", "totaltracks", "trackc", "totaltrackcount"]

            if validTrackKeys.contains(where: { keyLower == $0 }) {
                let (track, total) = parseNumbering(value)
                metadata.trackNumber = track.flatMap { Int($0) }
                metadata.totalTracks = total.flatMap { Int($0) }
            }
        }
        
        // Disc Number - Add special handling for simple "disc" key
        if metadata.discNumber == nil {
            let isDiscField = isKeyOfType(.discNumber, keyString, identifier, commonKey) ||
            keyString.lowercased() == "disc" ||
            keyString.lowercased() == "disk"
            
            if isDiscField {
                let (disc, total) = parseNumbering(value)
                metadata.discNumber = disc.flatMap { Int($0) }
                metadata.totalDiscs = total.flatMap { Int($0) }
            }
        }
        
        // Copyright
        if metadata.extended.copyright == nil && isKeyOfType(.copyright, keyString, identifier, commonKey) {
            metadata.extended.copyright = value
        }
        
        // BPM
        if metadata.bpm == nil && isKeyOfType(.bpm, keyString, identifier, commonKey) {
            metadata.bpm = Int(value)
        }
        
        // Comment
        if metadata.extended.comment == nil && isKeyOfType(.comment, keyString, identifier, commonKey) {
            metadata.extended.comment = value
        }
    }
    
    private static func extractExtendedFields(
        _ keyString: String,
        _ identifier: String,
        _ value: String,
        into metadata: inout TrackMetadata
    ) {
        let lowercaseKey = keyString.lowercased()
        let lowercaseIdentifier = identifier.lowercased()
        
        // Handle release dates specially
        if lowercaseKey.contains("releasedate") || lowercaseKey == "tdrl" {
            metadata.releaseDate = value
            if metadata.year == nil || metadata.year?.isEmpty == true {
                let extractedYear = extractYear(from: value)
                if !extractedYear.isEmpty {
                    metadata.year = extractedYear
                }
            }
        } else if lowercaseKey.contains("originaldate") || lowercaseKey == "tdor" {
            metadata.originalReleaseDate = value
            if metadata.year == nil || metadata.year?.isEmpty == true {
                let extractedYear = extractYear(from: value)
                if !extractedYear.isEmpty {
                    metadata.year = extractedYear
                }
            }
        }
        
        // Apply extended field mappings
        for mapping in ExtendedFieldMapping.mappings {
            if mapping.conditions.contains(where: { $0(lowercaseKey) || $0(lowercaseIdentifier) }) {
                mapping.action(value, &metadata)
                break // Only apply first matching mapping
            }
        }
        
        // Handle special tag groups
        if lowercaseKey.contains("musicbrainz") || identifier.contains("MusicBrainz") {
            parseMusicBrainzTag(keyString, value, into: &metadata)
        }
        
        if lowercaseKey.contains("sort") || identifier.contains("sort") {
            parseSortingTag(keyString, value, into: &metadata)
        }
        
        if lowercaseKey.contains("replaygain") || identifier.contains("replaygain") {
            parseReplayGainTag(keyString, value, into: &metadata)
        }
        
        if lowercaseKey.contains("itunes") || identifier.contains("iTunes") {
            parseITunesTag(keyString, value, into: &metadata)
        }
    }
    
    // MARK: - Helper Methods
    
    private static func isKeyOfType(
        _ type: MetadataKeyType,
        _ key: String,
        _ identifier: String,
        _ commonKey: String
    ) -> Bool {
        // Special handling for year - exclude TDAT
        if type == .year && key.lowercased() == "tdat" {
            return false
        }
        
        let keyLower = key.lowercased()
        let identifierLower = identifier.lowercased()
        let commonKeyLower = commonKey.lowercased()
        
        // Check if the key exactly matches any of our known keys
        if type.keys.contains(where: {
            $0.lowercased() == keyLower ||
            $0.lowercased() == identifierLower ||
            $0.lowercased() == commonKeyLower
        }) {
            return true
        }
        
        // For some fields, also check if any part contains our search terms
        let combined = (key + identifier + commonKey).lowercased()
        
        // Check search terms
        return type.searchTerms.contains { searchTerm in
            combined.contains(searchTerm.lowercased())
        }
    }
    
    @available(macOS, deprecated: 13.0)
    private static func extractAudioFormatInfo(from asset: AVURLAsset, into metadata: inout TrackMetadata) {
        guard let audioTrack = asset.tracks(withMediaType: .audio).first else { return }
        
        let formatDescriptions = audioTrack.formatDescriptions as? [CMFormatDescription] ?? []
        
        if let formatDescription = formatDescriptions.first {
            if let streamBasicDesc = CMAudioFormatDescriptionGetStreamBasicDescription(formatDescription) {
                metadata.sampleRate = Int(streamBasicDesc.pointee.mSampleRate)
                metadata.channels = Int(streamBasicDesc.pointee.mChannelsPerFrame)
                
                if streamBasicDesc.pointee.mBitsPerChannel > 0 {
                    metadata.bitDepth = Int(streamBasicDesc.pointee.mBitsPerChannel)
                }
            }
            
            let audioCodec = CMFormatDescriptionGetMediaSubType(formatDescription)
            metadata.codec = fourCCToString(audioCodec)
        }
        
        let dataRate = audioTrack.estimatedDataRate
        if dataRate > 0 {
            metadata.bitrate = Int(dataRate / 1000)
        }
    }
    
    @available(macOS, deprecated: 13.0)
    private static func extractArtwork(from item: AVMetadataItem, into metadata: inout TrackMetadata) {
        if let data = item.dataValue {
            metadata.artworkData = data
        } else if let value = item.value {
            if let data = value as? Data {
                metadata.artworkData = data
            } else if let data = value as? NSData {
                metadata.artworkData = data as Data
            }
        }
    }
    
    // MARK: - Specialized Parsers
    
    private static func parseMusicBrainzTag(_ key: String, _ value: String, into metadata: inout TrackMetadata) {
        let lowercaseKey = key.lowercased()
        
        switch true {
        case lowercaseKey.contains("artist") && lowercaseKey.contains("id"):
            metadata.extended.musicBrainzArtistId = value
        case lowercaseKey.contains("album") && lowercaseKey.contains("id"):
            metadata.extended.musicBrainzAlbumId = value
        case lowercaseKey.contains("track") && lowercaseKey.contains("id"):
            metadata.extended.musicBrainzTrackId = value
        case lowercaseKey.contains("release") && lowercaseKey.contains("group"):
            metadata.extended.musicBrainzReleaseGroupId = value
        case lowercaseKey.contains("work") && lowercaseKey.contains("id"):
            metadata.extended.musicBrainzWorkId = value
        default:
            break
        }
    }
    
    private static func parseSortingTag(_ key: String, _ value: String, into metadata: inout TrackMetadata) {
        let lowercaseKey = key.lowercased()
        
        switch true {
        case lowercaseKey.contains("albumsort") || lowercaseKey == "tsoa":
            metadata.sortAlbum = value
        case lowercaseKey.contains("albumartistsort") || lowercaseKey == "tso2":
            metadata.sortAlbumArtist = value
        case lowercaseKey.contains("artistsort") || lowercaseKey == "tsop":
            metadata.sortArtist = value
        case lowercaseKey.contains("titlesort") || lowercaseKey == "tsot":
            metadata.sortTitle = value
        case lowercaseKey.contains("composersort") || lowercaseKey == "tsoc":
            metadata.extended.sortComposer = value
        default:
            break
        }
    }
    
    private static func parseReplayGainTag(_ key: String, _ value: String, into metadata: inout TrackMetadata) {
        let lowercaseKey = key.lowercased()
        
        if lowercaseKey.contains("album") {
            metadata.extended.replayGainAlbum = value
        } else if lowercaseKey.contains("track") {
            metadata.extended.replayGainTrack = value
        }
    }
    
    private static func parseITunesTag(_ key: String, _ value: String, into metadata: inout TrackMetadata) {
        let lowercaseKey = key.lowercased()
        
        switch true {
        case lowercaseKey.contains("compilation"):
            metadata.compilation = (value == "1" || value.lowercased() == "true")
        case lowercaseKey.contains("gapless"):
            metadata.extended.gaplessData = value
        case lowercaseKey.contains("mediatype") || lowercaseKey.contains("stik"):
            metadata.mediaType = value
        case lowercaseKey.contains("rating"):
            if let ratingValue = Int(value) {
                metadata.rating = ratingValue / 20 // Convert 0-100 to 0-5
            }
        case lowercaseKey.contains("advisory"):
            metadata.extended.itunesAdvisory = value
        case lowercaseKey.contains("account"):
            metadata.extended.itunesAccount = value
        case lowercaseKey.contains("purchasedate"):
            metadata.extended.itunesPurchaseDate = value
        default:
            break
        }
    }
    
    // MARK: - Utility Methods
    
    @available(macOS, deprecated: 13.0)
    private static func getStringValue(from item: AVMetadataItem) -> String? {
        if let stringValue = item.stringValue {
            return stringValue
        }
        
        if let value = item.value {
            if let stringValue = value as? String {
                return stringValue
            } else if let numberValue = value as? NSNumber {
                return numberValue.stringValue
            } else if let dataValue = value as? Data {
                return String(data: dataValue, encoding: .utf8)
            }
        }
        
        if let dataValue = item.dataValue {
            return String(data: dataValue, encoding: .utf8)
        }
        
        return nil
    }
    
    private static func getKeyString(from item: AVMetadataItem) -> String {
        guard let key = item.key else { return "" }
        
        if let stringKey = key as? String {
            return stringKey
        } else if let numberKey = key as? NSNumber {
            let intValue = numberKey.uint32Value
            
            // Check if this is "trkn" (0x74726b6e in hex)
            if intValue == 0x74726b6e {
                return "trkn"
            }
            
            // Check if this is "disk" (0x6469736b in hex)
            if intValue == 0x6469736b {
                return "disk"
            }
            
            // Convert ID3 numeric keys to string
            let id3Key = String(format: "%c%c%c%c",
                                (intValue >> 24) & 0xFF,
                                (intValue >> 16) & 0xFF,
                                (intValue >> 8) & 0xFF,
                                intValue & 0xFF)
            return id3Key
        } else {
            return String(describing: key)
        }
    }
    
    private static func parseNumbering(_ value: String) -> (String?, String?) {
        let components = value.split(separator: "/").map { String($0).trimmingCharacters(in: .whitespaces) }
        
        switch components.count {
        case 0: return (nil, nil)
        case 1: return (components[0], nil)
        default: return (components[0], components[1])
        }
    }
    
    private static func extractYear(from dateString: String) -> String {
        let trimmed = dateString.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Validate if already a 4-digit year
        if trimmed.count == 4, let yearInt = Int(trimmed) {
            let currentYear = Calendar.current.component(.year, from: Date())
            if yearInt >= 1900 && yearInt <= currentYear + 10 {
                return trimmed
            }
            return ""
        }
        
        // Try regex for years 1900-2099
        let pattern = #"\b(19\d{2}|20\d{2})\b"#
        if let regex = try? NSRegularExpression(pattern: pattern),
           let match = regex.firstMatch(in: trimmed, range: NSRange(trimmed.startIndex..., in: trimmed)),
           let yearRange = Range(match.range(at: 1), in: trimmed) {
            return String(trimmed[yearRange])
        }
        
        // Try date formatters
        let dateFormatters = [
            "yyyy-MM-dd", "yyyy/MM/dd", "yyyy.MM.dd", "yyyy",
            "dd-MM-yyyy", "dd/MM/yyyy", "MM-dd-yyyy", "MM/dd/yyyy",
            "yyyy-MM-dd'T'HH:mm:ssZ", "yyyy-MM-dd HH:mm:ss"
        ]
        
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        
        for format in dateFormatters {
            formatter.dateFormat = format
            if let date = formatter.date(from: trimmed) {
                let year = Calendar.current.component(.year, from: date)
                let currentYear = Calendar.current.component(.year, from: Date())
                if year >= 1900 && year <= currentYear + 10 {
                    return String(year)
                }
            }
        }
        
        return ""
    }
    
    private static func fourCCToString(_ fourCC: FourCharCode) -> String {
        // Check common audio formats first
        switch fourCC {
        case kAudioFormatMPEG4AAC: return "AAC"
        case kAudioFormatMPEGLayer3: return "MP3"
        case kAudioFormatAppleLossless: return "ALAC"
        case kAudioFormatFLAC: return "FLAC"
        case kAudioFormatLinearPCM: return "PCM"
        case kAudioFormatAC3: return "AC-3"
        case kAudioFormatMPEG4AAC_HE: return "HE-AAC"
        case kAudioFormatMPEG4AAC_HE_V2: return "HE-AACv2"
        default:
            // Convert FourCC bytes to string
            let bytes: [UInt8] = [
                UInt8((fourCC >> 24) & 0xFF),
                UInt8((fourCC >> 16) & 0xFF),
                UInt8((fourCC >> 8) & 0xFF),
                UInt8(fourCC & 0xFF)
            ]
            return String(bytes: bytes, encoding: .ascii)?
                .trimmingCharacters(in: .whitespaces) ?? "Unknown"
        }
    }
}

// MARK: - TrackMetadata

struct TrackMetadata {
    let url: URL
    var title: String?
    var artist: String?
    var album: String?
    var composer: String?
    var genre: String?
    var year: String?
    var duration: Double = 0
    var artworkData: Data?
    var albumArtist: String?
    var trackNumber: Int?
    var totalTracks: Int?
    var discNumber: Int?
    var totalDiscs: Int?
    var rating: Int?
    var compilation: Bool = false
    var releaseDate: String?
    var originalReleaseDate: String?
    var bpm: Int?
    var mediaType: String?
    var bitrate: Int?
    var sampleRate: Int?
    var channels: Int?
    var codec: String?
    var bitDepth: Int?
    
    var sortTitle: String?
    var sortArtist: String?
    var sortAlbum: String?
    var sortAlbumArtist: String?
    
    var extended: ExtendedMetadata
    
    init(url: URL) {
        self.url = url
        self.extended = ExtendedMetadata()
    }
}
