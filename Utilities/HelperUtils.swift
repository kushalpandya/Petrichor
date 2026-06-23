import Foundation

enum HelperUtils {
    /// Pluralized "N song(s)" label.
    static func songCount(_ count: Int) -> String {
        count == 1 ? String(localized: "1 song") : String(localized: "\(count) songs")
    }

    /// Sanitizes a duration value for safe display, persistence, and numeric conversion.
    /// Converts negative, NaN, and infinite values to zero.
    /// - Parameter seconds: Duration in seconds.
    /// - Returns: A finite, non-negative duration in seconds.
    static func sanitizedDuration(_ seconds: Double) -> Double {
        seconds.isFinite && seconds >= 0 ? seconds : 0
    }

    /// Sanitizes a duration and converts it to whole seconds.
    /// This method is safe to call before `Int` conversion because invalid values are normalized first.
    /// - Parameter seconds: Duration in seconds.
    /// - Returns: A finite, non-negative duration rounded toward zero as whole seconds.
    static func sanitizedWholeDuration(_ seconds: Double) -> Int {
        Int(sanitizedDuration(seconds))
    }

    /// Formats a duration for display, using hours when needed.
    /// Invalid values such as NaN, infinity, and negative durations are displayed as zero.
    /// - Parameter seconds: Duration in seconds.
    /// - Returns: A formatted duration string (`H:MM:SS` when hours are present, otherwise `M:SS`).
    static func formattedDuration(_ seconds: Double) -> String {
        let totalSeconds = sanitizedWholeDuration(seconds)
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let remainingSeconds = totalSeconds % 60

        if hours > 0 {
            return String(format: StringFormat.hhmmss, hours, minutes, remainingSeconds)
        }
        return String(format: StringFormat.mmss, minutes, remainingSeconds)
    }

    /// Formats a duration for compact display without an hours component.
    /// Invalid values such as NaN, infinity, and negative durations are displayed as zero.
    /// - Parameter seconds: Duration in seconds.
    /// - Returns: A formatted duration string (`M:SS`).
    static func formattedShortDuration(_ seconds: Double) -> String {
        let totalSeconds = sanitizedWholeDuration(seconds)
        let minutes = totalSeconds / 60
        let remainingSeconds = totalSeconds % 60
        return String(format: StringFormat.mmss, minutes, remainingSeconds)
    }

    /// Formats a duration as a compact textual summary for stats labels.
    /// Invalid values such as NaN, infinity, and negative durations are displayed as zero.
    /// - Parameter seconds: Duration in seconds.
    /// - Returns: A formatted duration string (`H hr M min` when hours are present, otherwise `M min`).
    static func formattedDurationSummary(_ seconds: Double) -> String {
        let totalSeconds = sanitizedWholeDuration(seconds)
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60

        if hours > 0 {
            return "\(hours) hr \(minutes) min"
        }
        return "\(minutes) min"
    }
}
