import Foundation
import AVFoundation
import CryptoKit

enum FilesystemUtils {
    /// Computes a SHA256 hash for a folder based on its audio/artwork file paths, modification dates, and sizes.
    /// Uses a single FileManager.enumerator pass instead of spawning shell processes.
    /// - Parameter folderURL: Folder to compute hash for
    /// - Returns: Hex-encoded SHA256 hash string, or nil on failure
    static func computeFolderHash(for folderURL: URL) async -> String? {
        guard folderURL.isFileURL else { return nil }

        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: folderURL.path, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            return nil
        }

        let supportedAudioExtensions = Set(AudioFormat.supportedExtensions.map { $0.lowercased() })
        let artworkFilenames = Set(AlbumArtFormat.knownFilenames.map { $0.lowercased() })
        let artworkExtensions = Set(AlbumArtFormat.supportedExtensions.map { $0.lowercased() })

        guard let enumerator = FileManager.default.enumerator(
            at: folderURL,
            includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else {
            return nil
        }

        let basePath = folderURL.path
        var entries: [(path: String, modDate: TimeInterval, size: Int64)] = []

        while let fileURL = enumerator.nextObject() as? URL {
            let ext = fileURL.pathExtension.lowercased()
            guard !ext.isEmpty else { continue }

            // Check if this is an audio file or artwork file
            let isAudio = supportedAudioExtensions.contains(ext)
            let isArtwork = artworkExtensions.contains(ext)
                && artworkFilenames.contains(fileURL.deletingPathExtension().lastPathComponent.lowercased())

            guard isAudio || isArtwork else { continue }

            // Read file attributes (batched by OS via getattrlistbulk)
            guard let resourceValues = try? fileURL.resourceValues(
                forKeys: [.contentModificationDateKey, .fileSizeKey]
            ) else { continue }

            let relativePath = String(fileURL.path.dropFirst(basePath.count))
            let modDate = resourceValues.contentModificationDate?.timeIntervalSince1970 ?? 0
            let size = Int64(resourceValues.fileSize ?? 0)

            entries.append((relativePath, modDate, size))
        }

        guard !entries.isEmpty else { return nil }

        // Sort by path for deterministic ordering
        entries.sort { $0.path < $1.path }

        // Compute SHA256 from sorted entries
        var hasher = SHA256()
        for entry in entries {
            hasher.update(data: Data(entry.path.utf8))
            withUnsafeBytes(of: entry.modDate) { hasher.update(bufferPointer: $0) }
            withUnsafeBytes(of: entry.size) { hasher.update(bufferPointer: $0) }
        }

        let digest = hasher.finalize()
        return digest.map { String(format: "%02x", $0) }.joined()
    }
    
    /// Checks if folder's filesystem modification date has changed compared to stored date
    /// - Parameters:
    ///   - folderURL: The folder to check
    ///   - storedDate: The previously stored modification date
    ///   - tolerance: Time difference tolerance in seconds (default 1.0)
    /// - Returns: true if modification date has changed beyond tolerance
    static func modificationTimestampChanged(
        for folderURL: URL,
        comparedTo storedDate: Date,
        tolerance: TimeInterval = 1.0
    ) -> Bool {
        do {
            let attributes = try FileManager.default.attributesOfItem(atPath: folderURL.path)
            let currentModDate = attributes[.modificationDate] as? Date ?? Date.distantPast
            
            // Check if the difference exceeds tolerance
            let timeDifference = currentModDate.timeIntervalSince(storedDate)
            let hasChanged = abs(timeDifference) > tolerance
            
            if hasChanged {
                Logger.info("Folder timestamp changed: \(folderURL.lastPathComponent) (diff: \(timeDifference)s)")
            }
            
            return hasChanged
        } catch {
            Logger.warning("Failed to get modification date for \(folderURL.lastPathComponent): \(error)")
            // If we can't check, assume it changed to be safe
            return true
        }
    }

    /// Read the first N bytes of a file as a header
    /// - Parameters:
    ///   - url: The file URL to read from
    ///   - byteCount: Number of bytes to read (default 12, enough for most format magic numbers)
    /// - Returns: Array of bytes, or nil if reading fails
    static func readFileHeader(from url: URL, byteCount: Int = 12) -> [UInt8]? {
        guard let fileHandle = try? FileHandle(forReadingFrom: url) else {
            return nil
        }
        
        defer { try? fileHandle.close() }
        
        guard let headerData = try? fileHandle.read(upToCount: byteCount),
              headerData.count >= 4 else { // At minimum we need 4 bytes for magic numbers
            return nil
        }
        
        return [UInt8](headerData)
    }

    /// Converts system errors into user-friendly messages
    /// - Parameters:
    ///   - error: The error to convert
    ///   - context: Optional context about what was being done (e.g., "play track", "scan folder")
    ///   - path: Optional file path for more specific messages
    /// - Returns: A user-friendly error message
    static func getMessageForError(
        _ error: Error,
        context: String? = nil,
        path: String? = nil
    ) -> String {
        let fileName = path.map { URL(fileURLWithPath: $0).lastPathComponent } ?? "file"
        
        if let nsError = error as NSError? {
            switch nsError.domain {
            case NSCocoaErrorDomain:
                return getCocoaErrorMessage(nsError, fileName: fileName, context: context)
            case NSPOSIXErrorDomain:
                return getPOSIXErrorMessage(nsError, fileName: fileName, context: context)
            case NSURLErrorDomain:
                return getURLErrorMessage(nsError, fileName: fileName, context: context)
            case AVFoundationErrorDomain:
                return getAVErrorMessage(nsError, fileName: fileName, context: context)
            default:
                // Check if file exists for unknown errors
                if let path = path, !FileManager.default.fileExists(atPath: path) {
                    return "Cannot \(context ?? "access") '\(fileName)': File no longer exists"
                }
                return "Cannot \(context ?? "access") '\(fileName)': \(error.localizedDescription)"
            }
        }
        
        // For non-NSError types
        if let path = path, !FileManager.default.fileExists(atPath: path) {
            return "Cannot \(context ?? "access") '\(fileName)': File no longer exists"
        }
        return "Cannot \(context ?? "access") '\(fileName)': \(error.localizedDescription)"
    }
    
    /// Write M3U playlist content to a file
    /// - Parameters:
    ///   - content: The M3U file content as a string
    ///   - url: The destination file URL
    /// - Throws: File writing errors
    static func writeM3UFile(content: String, to url: URL) throws {
        try content.write(to: url, atomically: true, encoding: .utf8)
    }
    
    /// Sanitize a playlist name for use as a filename
    /// - Parameter name: The playlist name to sanitize
    /// - Returns: A safe filename (without extension)
    static func sanitizeFilename(_ name: String) -> String {
        // Characters that are invalid in filenames on macOS
        let invalidCharacters = CharacterSet(charactersIn: ":/\\?%*|\"<>")
        
        // Replace invalid characters with underscores
        let sanitized = name.components(separatedBy: invalidCharacters).joined(separator: "_")
        
        // Trim whitespace and limit length
        let trimmed = sanitized.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Limit to 255 characters (macOS filename limit)
        if trimmed.count > 255 {
            return String(trimmed.prefix(255))
        }
        
        return trimmed.isEmpty ? "Untitled" : trimmed
    }
    
    /// Checks if the URL is on a potentially slow filesystem (network mounts, FUSE, etc.)
    /// Uses the MNT_LOCAL flag as the primary signal, with filesystem type string matching as fallback.
    /// - Parameter url: The URL to check
    /// - Returns: true if the filesystem is potentially slow
    static func isSlowFilesystem(url: URL) -> Bool {
        var statfsInfo = statfs()
        guard statfs(url.path, &statfsInfo) == 0 else {
            return false
        }

        // Primary check: MNT_LOCAL flag is absent on network mounts (SMB, NFS, AFP, etc.)
        let isRemote = (statfsInfo.f_flags & UInt32(MNT_LOCAL)) == 0
        if isRemote {
            return true
        }

        // Fallback: check filesystem type string for FUSE-based mounts
        // that may incorrectly report MNT_LOCAL
        let fsType = withUnsafePointer(to: &statfsInfo.f_fstypename) {
            $0.withMemoryRebound(to: CChar.self, capacity: Int(MFSTYPENAMELEN)) {
                String(cString: $0)
            }
        }

        let fuseFilesystems = [
            "macfuse",      // macFUSE (CloudMounter, Mountain Duck, etc.)
            "osxfuse",      // Older FUSE implementation
            "fuse",         // Generic FUSE
            "fusefs",       // FUSE variant
            "webdav",       // WebDAV mounts
        ]

        let fsTypeLower = fsType.lowercased()
        return fuseFilesystems.contains { fsTypeLower.contains($0) }
    }
    
    // MARK: - Private Helpers
    
    private static func getCocoaErrorMessage(_ error: NSError, fileName: String, context: String?) -> String {
        switch error.code {
        case NSFileNoSuchFileError,
        NSFileReadNoSuchFileError:
            return "Cannot \(context ?? "access") '\(fileName)': File not found"
            
        case NSFileReadNoPermissionError,
        NSFileWriteNoPermissionError:
            return "Cannot \(context ?? "access") '\(fileName)': Permission denied"
            
        case NSFileReadCorruptFileError:
            return "Cannot \(context ?? "access") '\(fileName)': File appears to be corrupted"
            
        case NSFileReadUnknownError:
            return "Cannot \(context ?? "access") '\(fileName)': Unknown file error"
            
        case NSFileReadInvalidFileNameError:
            return "Cannot \(context ?? "access") '\(fileName)': Invalid file name"
            
        case NSFileReadInapplicableStringEncodingError:
            return "Cannot \(context ?? "access") '\(fileName)': File encoding not supported"
            
        case NSFileReadUnsupportedSchemeError:
            return "Cannot \(context ?? "access") '\(fileName)': Unsupported file type"
            
        default:
            return "Cannot \(context ?? "access") '\(fileName)': \(error.localizedDescription)"
        }
    }
    
    private static func getPOSIXErrorMessage(_ error: NSError, fileName: String, context: String?) -> String {
        switch error.code {
        case Int(ENOENT):  // No such file or directory
            return "Cannot \(context ?? "access") '\(fileName)': File not found"
            
        case Int(EACCES),  // Permission denied
            Int(EPERM):   // Operation not permitted
            return "Cannot \(context ?? "access") '\(fileName)': Permission denied"
            
        case Int(ENOTDIR): // Not a directory
            return "Cannot \(context ?? "access") '\(fileName)': Not a valid folder"
            
        case Int(EISDIR):  // Is a directory
            return "Cannot \(context ?? "access") '\(fileName)': This is a folder, not a file"
            
        case Int(ENOMEM):  // Out of memory
            return "Cannot \(context ?? "access") '\(fileName)': Insufficient memory"
            
        case Int(ENOSPC):  // No space left on device
            return "Cannot \(context ?? "access") '\(fileName)': Insufficient disk space"
            
        case Int(EROFS):   // Read-only file system
            return "Cannot \(context ?? "access") '\(fileName)': File system is read-only"
            
        default:
            return "Cannot \(context ?? "access") '\(fileName)': System error \(error.code)"
        }
    }
    
    private static func getURLErrorMessage(_ error: NSError, fileName: String, context: String?) -> String {
        switch error.code {
        case NSURLErrorFileDoesNotExist:
            return "Cannot \(context ?? "access") '\(fileName)': File not found"
            
        case NSURLErrorFileIsDirectory:
            return "Cannot \(context ?? "access") '\(fileName)': This is a folder, not a file"
            
        case NSURLErrorNoPermissionsToReadFile:
            return "Cannot \(context ?? "access") '\(fileName)': Permission denied"
            
        case NSURLErrorDataLengthExceedsMaximum:
            return "Cannot \(context ?? "access") '\(fileName)': File too large"
            
        default:
            return "Cannot \(context ?? "access") '\(fileName)': \(error.localizedDescription)"
        }
    }
    
    private static func getAVErrorMessage(_ error: NSError, fileName: String, context: String?) -> String {
        switch error.code {
        case AVError.fileFormatNotRecognized.rawValue:
            return "Cannot \(context ?? "play") '\(fileName)': Unrecognized audio format"
            
        case AVError.fileFailedToParse.rawValue:
            return "Cannot \(context ?? "play") '\(fileName)': Invalid or corrupted audio file"
            
        case AVError.undecodableMediaData.rawValue:
            return "Cannot \(context ?? "play") '\(fileName)': Audio data cannot be decoded"
            
        case AVError.fileTypeDoesNotSupportSampleReferences.rawValue:
            return "Cannot \(context ?? "play") '\(fileName)': Unsupported audio format"
            
        default:
            if error.code == 2003334207 { // Common "file not found" code in AVFoundation
                return "Cannot \(context ?? "play") '\(fileName)': File not found"
            }
            return "Cannot \(context ?? "play") '\(fileName)': Playback error"
        }
    }
}

// MARK: - Error Domain Constants
private let AVFoundationErrorDomain = "AVFoundationErrorDomain"
