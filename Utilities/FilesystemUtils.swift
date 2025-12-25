import Foundation
import AVFoundation

enum FilesystemUtils {
    /// Computes a hash for audio files in a folder using `shasum -a 256`, with a timeout failsafe.
    /// - Parameters:
    ///   - folderURL: Folder to scan
    ///   - timeout: Max duration (seconds) to allow the process to run
    ///   - completion: Hash string or nil on failure/timeout
    static func getHash(for folderURL: URL, timeout: TimeInterval = 10, completion: @escaping (String?) -> Void) {
        guard folderURL.isFileURL else {
            DispatchQueue.main.async { completion(nil) }
            return
        }
        
        let path = folderURL.path
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            DispatchQueue.main.async { completion(nil) }
            return
        }
        
        DispatchQueue.global(qos: .utility).async {
            // Audio extensions
            let audioExtensions = AudioFormat.supportedExtensions.map { $0.lowercased() }
            let audioFilter = audioExtensions.map { "-iname '*.\($0)'" }.joined(separator: " -o ")

            // Build artwork filter for specific filenames with supported extensions
            let artworkPatterns: [String] = AlbumArtFormat.knownFilenames.flatMap { filename in
                AlbumArtFormat.supportedExtensions.map { ext in "-iname '\(filename).\(ext)'" }
            }
            let artworkFilter = artworkPatterns.joined(separator: " -o ")
            
            let findExpression = "\\( \(audioFilter) -o \(artworkFilter) \\)"
            
            let command = """
            find "$1" -type f \(findExpression) -exec ls -lT {} + | sort | shasum -a 256
            """
            
            let process = Process()
            process.launchPath = "/bin/sh"
            process.arguments = ["-c", command, "--", path]
            
            let outputPipe = Pipe()
            process.standardOutput = outputPipe
            process.standardError = outputPipe
            
            let timeoutTask = DispatchWorkItem {
                if process.isRunning {
                    process.terminate()
                    Logger.info("Hash process timed out after \(timeout) seconds and was terminated.")
                }
            }
            
            do {
                try process.run()
                DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: timeoutTask)
            } catch {
                Logger.error("Failed to run hash command: \(error.localizedDescription)")
                DispatchQueue.main.async { completion(nil) }
                return
            }
            
            process.waitUntilExit()
            timeoutTask.cancel()
            
            let data = outputPipe.fileHandleForReading.readDataToEndOfFile()
            
            guard process.terminationStatus == 0,
                  let rawOutput = String(data: data, encoding: .utf8),
                  let hash = rawOutput.components(separatedBy: .whitespaces).first,
                  hash.count >= 16 else {
                Logger.warning("Hash command failed or returned malformed output.")
                DispatchQueue.main.async { completion(nil) }
                return
            }
            
            DispatchQueue.main.async {
                completion(hash)
            }
        }
    }
    
    /// Async version of getHash for use with async/await
    static func getHashAsync(for folderURL: URL, timeout: TimeInterval = 10) async -> String? {
        await withCheckedContinuation { continuation in
            getHash(for: folderURL, timeout: timeout) { hash in
                continuation.resume(returning: hash)
            }
        }
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
    
    /// Checks if the URL is on a potentially slow filesystem (FUSE, WebDAV, etc.)
    /// These filesystems may appear as "local" but actually fetch data over the network.
    /// - Parameter url: The URL to check
    /// - Returns: true if the filesystem is potentially slow
    static func isSlowFilesystem(url: URL) -> Bool {
        var statfsInfo = statfs()
        guard statfs(url.path, &statfsInfo) == 0 else {
            return false
        }
        
        let fsType = withUnsafePointer(to: &statfsInfo.f_fstypename) {
            $0.withMemoryRebound(to: CChar.self, capacity: Int(MFSTYPENAMELEN)) {
                String(cString: $0)
            }
        }
        
        // Filesystem types that indicate potentially slow/network-based sources
        let slowFilesystems = [
            "macfuse",      // macFUSE (used by CloudMounter, Mountain Duck, etc.)
            "osxfuse",      // Older FUSE implementation
            "fuse",         // Generic FUSE
            "fusefs",       // FUSE variant
            "smbfs",        // SMB shares
            "nfs",          // NFS mounts
            "afpfs",        // AFP shares
            "webdav",       // WebDAV mounts
        ]
        
        let fsTypeLower = fsType.lowercased()
        return slowFilesystems.contains { fsTypeLower.contains($0) }
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
