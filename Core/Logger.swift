import Foundation
import os.log

// MARK: - Log Level

enum LogLevel: Int, Comparable {
    case info = 0
    case warning = 1
    case error = 2
    case critical = 3
    
    var prefix: String {
        switch self {
        case .info: return "INFO"
        case .warning: return "WARNING"
        case .error: return "ERROR"
        case .critical: return "CRITICAL"
        }
    }
    
    var emoji: String {
        switch self {
        case .info: return "ℹ️"
        case .warning: return "⚠️"
        case .error: return "❌"
        case .critical: return "🔥"
        }
    }
    
    static func < (lhs: LogLevel, rhs: LogLevel) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

// MARK: - Log Entry

struct LogEntry {
    let timestamp: Date
    let level: LogLevel
    let message: String
    let file: String
    let line: Int
    let function: String
    
    var formattedMessage: String {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = StringFormat.logEntryFormat
        
        let context = extractContext(from: file)
        let funcName = extractFunctionName(from: function)
        let timestamp = dateFormatter.string(from: timestamp)
        
        return "[\(timestamp)] [\(level.prefix)] [\(context) > \(funcName):\(line)] \(message)"
    }
    
    var consoleMessage: String {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "HH:mm:ss.SSS"

        let context = extractContext(from: file)
        let funcName = extractFunctionName(from: function)
        let timestamp = dateFormatter.string(from: timestamp)
        
        return "[\(timestamp)] \(level.emoji) [\(level.prefix)] [\(context) > \(funcName):\(line)] \(message)"
    }
    
    private func extractContext(from filePath: String) -> String {
        let fileName = URL(fileURLWithPath: filePath).lastPathComponent
        // Remove .swift extension and common suffixes
        let name = fileName
            .replacingOccurrences(of: ".swift", with: "")
        
        // Truncate very long names
        if name.count > 20 {
            return String(name.prefix(17)) + "..."
        }
        
        return name
    }
    
    private func extractFunctionName(from function: String) -> String {
        // Remove parameter list and return type
        let funcName = function
            .components(separatedBy: "(").first ?? function
        
        // Truncate very long function names
        if funcName.count > 30 {
            return String(funcName.prefix(27)) + "..."
        }
        
        return funcName
    }
}

// MARK: - Logger

final class Logger {
    static let shared = Logger()
    
    private let fileManager = LogFileManager()
    private let logQueue: DispatchQueue
    private var osLog: OSLog
    
    // Configuration
    private(set) var minimumLogLevel: LogLevel = .info
    private let enableConsoleLogging = true
    private let enableFileLogging = true
    
    private init() {
        let bundleIdentifier = Bundle.main.bundleIdentifier ?? About.bundleIdentifier
        
        // Initialize properties that depend on bundle identifier
        self.osLog = OSLog(subsystem: bundleIdentifier, category: "music")
        self.logQueue = DispatchQueue(label: "\(bundleIdentifier).logger", qos: .utility)
        
        // Ensure log directory exists
        fileManager.createLogDirectoryIfNeeded()
        
        // Perform log rotation on init
        logQueue.async { [weak self] in
            self?.fileManager.performLogRotation()
        }
    }
    
    // MARK: - Public API
    
    static func info(
        _ message: String,
        file: String = #file,
        line: Int = #line,
        function: String = #function
    ) {
        shared.log(level: .info, message: message, file: file, line: line, function: function)
    }
    
    static func warning(
        _ message: String,
        file: String = #file,
        line: Int = #line,
        function: String = #function
    ) {
        shared.log(level: .warning, message: message, file: file, line: line, function: function)
    }
    
    static func error(
        _ message: String,
        file: String = #file,
        line: Int = #line,
        function: String = #function
    ) {
        shared.log(level: .error, message: message, file: file, line: line, function: function)
    }
    
    static func critical(
        _ message: String,
        file: String = #file,
        line: Int = #line,
        function: String = #function
    ) {
        shared.log(level: .critical, message: message, file: file, line: line, function: function)
    }
    
    // MARK: - Configuration
    
    static func setMinimumLogLevel(_ level: LogLevel) {
        shared.minimumLogLevel = level
    }
    
    // MARK: - Crash Handling
    
    static func installCrashHandler() {
        // Install exception handler
        NSSetUncaughtExceptionHandler { exception in
            Logger.critical("UNCAUGHT EXCEPTION: \(exception.name.rawValue)")
            if let reason = exception.reason {
                Logger.critical("Reason: \(reason)")
            }
            Logger.critical("Call Stack:\n\(exception.callStackSymbols.joined(separator: "\n"))")
            
            // Force synchronous write
            Logger.shared.flush()
            
            // Give a moment for the write to complete
            Thread.sleep(forTimeInterval: 0.5)
        }
        
        // Install signal handlers for crashes that don't throw exceptions
        let signals = [SIGABRT, SIGILL, SIGSEGV, SIGFPE, SIGBUS, SIGPIPE, SIGTRAP]
        
        for sig in signals {
            Darwin.signal(sig) { signum in
                Logger.critical("SIGNAL CRASH: Received signal \(signum)")
                
                // Try to get signal name
                let signalName: String
                switch signum {
                case SIGABRT: signalName = "SIGABRT"
                case SIGILL: signalName = "SIGILL"
                case SIGSEGV: signalName = "SIGSEGV"
                case SIGFPE: signalName = "SIGFPE"
                case SIGBUS: signalName = "SIGBUS"
                case SIGPIPE: signalName = "SIGPIPE"
                case SIGTRAP: signalName = "SIGTRAP"
                default: signalName = "Unknown"
                }
                Logger.critical("Signal name: \(signalName)")
                
                // Try to capture some stack trace
                let callstack = Thread.callStackSymbols
                Logger.critical("Call Stack:\n\(callstack.joined(separator: "\n"))")
                
                // Force flush
                Logger.shared.flush()
                Thread.sleep(forTimeInterval: 0.5)
                
                // Re-raise the signal to ensure proper termination
                Darwin.signal(signum, SIG_DFL)
                raise(signum)
            }
        }
        
        Logger.info("Crash handlers installed successfully")
    }
    
    // MARK: - Private Methods
    
    private func log(
        level: LogLevel,
        message: String,
        file: String,
        line: Int,
        function: String
    ) {
        // Check if we should log this level
        guard level >= minimumLogLevel else { return }
        
        let entry = LogEntry(
            timestamp: Date(),
            level: level,
            message: message,
            file: file,
            line: line,
            function: function
        )
        
        // Console logging (using os_log for better Xcode integration)
        if enableConsoleLogging {
            logToConsole(entry)
        }
        
        // File logging (async to avoid blocking)
        if enableFileLogging {
            logQueue.async { [weak self] in
                self?.fileManager.write(entry)
            }
        }
    }
    
    // Force synchronous flush of pending logs
    private func flush() {
        logQueue.sync {
            // This ensures all pending async writes are completed
            // The sync call blocks until all previously submitted tasks finish
        }
    }
    
    private func logToConsole(_ entry: LogEntry) {
        // Use os_log for better integration with Xcode console
        let type: OSLogType
        switch entry.level {
        case .info:
            type = .info
        case .warning:
            type = .default
        case .error:
            type = .error
        case .critical:
            type = .fault
        }
        
        os_log("%{public}@", log: osLog, type: type, entry.consoleMessage)
    }
}

// MARK: - Log File Manager

private final class LogFileManager {
    private let maxLogAge: TimeInterval = 7 * 24 * 60 * 60 // 7 days
    private let logFileName: String = {
        let bundleID = Bundle.main.bundleIdentifier ?? About.bundleIdentifier
        return bundleID.hasSuffix(".debug") ? "petrichor-debug.log" : "petrichor.log"
    }()
    
    private var logFileURL: URL? {
        guard let supportDirectory = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first else { return nil }
        
        let bundleID = Bundle.main.bundleIdentifier ?? About.bundleIdentifier
        let appDirectory = supportDirectory.appendingPathComponent(bundleID)
        let logsDirectory = appDirectory.appendingPathComponent("Logs")
        
        return logsDirectory.appendingPathComponent(logFileName)
    }
    
    func createLogDirectoryIfNeeded() {
        guard let logFileURL = logFileURL else { return }
        
        let logsDirectory = logFileURL.deletingLastPathComponent()
        
        if !FileManager.default.fileExists(atPath: logsDirectory.path) {
            do {
                try FileManager.default.createDirectory(
                    at: logsDirectory,
                    withIntermediateDirectories: true,
                    attributes: nil
                )
            } catch {
                // Can't use Logger here as it would cause recursion
                // Using os_log directly to avoid print statement
                os_log(
                    "Failed to create logs directory: %{public}@",
                    log: .default,
                    type: .error,
                    error.localizedDescription
                )
            }
        }
    }
    
    func write(_ entry: LogEntry) {
        guard let logFileURL = logFileURL else { return }
        
        let logMessage = entry.formattedMessage + "\n"
        
        guard let data = logMessage.data(using: .utf8) else { return }
        
        // Create file if it doesn't exist
        if !FileManager.default.fileExists(atPath: logFileURL.path) {
            FileManager.default.createFile(
                atPath: logFileURL.path,
                contents: data,
                attributes: nil
            )
        } else {
            // Append to existing file
            do {
                let fileHandle = try FileHandle(forWritingTo: logFileURL)
                defer { try? fileHandle.close() }
                
                fileHandle.seekToEndOfFile()
                fileHandle.write(data)
            } catch {
                // Can't use Logger here as it would cause recursion
                // Using os_log directly to avoid print statement
                os_log(
                    "Failed to write to log file: %{public}@",
                    log: .default,
                    type: .error,
                    error.localizedDescription
                )
            }
        }
    }
    
    func performLogRotation() {
        guard let logFileURL = logFileURL else { return }
        
        // Read the current log file
        guard FileManager.default.fileExists(atPath: logFileURL.path),
              let logContent = try? String(contentsOf: logFileURL, encoding: .utf8) else {
            return
        }
        
        let lines = logContent.components(separatedBy: .newlines)
        let cutoffDate = Date().addingTimeInterval(-maxLogAge)
        
        var filteredLines: [String] = []
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        
        for line in lines {
            // Skip empty lines
            guard !line.isEmpty else { continue }
            
            // Extract timestamp from log line
            let pattern = #"\[([\d-]+ [\d:.]+)\]"#
            if let match = line.range(of: pattern, options: .regularExpression),
               let dateString = line[match]
                   .dropFirst()
                   .dropLast()
                   .split(separator: "]")
                   .first,
               let date = dateFormatter.date(from: String(dateString)) {
                // Keep lines newer than cutoff date
                if date > cutoffDate {
                    filteredLines.append(line)
                }
            }
        }
        
        // Write filtered content back
        let newContent = filteredLines.joined(separator: "\n") + "\n"
        do {
            try newContent.write(to: logFileURL, atomically: true, encoding: .utf8)
        } catch {
            // Using os_log directly to avoid print statement
            os_log(
                "Failed to perform log rotation: %{public}@",
                log: .default,
                type: .error,
                error.localizedDescription
            )
        }
    }
    
    // Utility method to get log file location
    static func getLogFileURL() -> URL? {
        LogFileManager().logFileURL
    }
}

// MARK: - Convenience Extensions

extension Logger {
    /// Get the URL of the current log file
    static var logFileURL: URL? {
        LogFileManager.getLogFileURL()
    }
    
    /// Clear all logs
    static func clearLogs() {
        guard let url = logFileURL else { return }
        try? FileManager.default.removeItem(at: url)
    }
    
    /// Debug print for use in SwiftUI Previews and tests
    /// This bypasses the logging system and uses regular print
    static func debugPrint(_ items: Any..., separator: String = " ", terminator: String = "\n") {
        // swiftlint:disable:next no_print_statements
        print(items.map { "\($0)" }.joined(separator: separator), terminator: terminator)
    }
}
