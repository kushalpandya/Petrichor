import Foundation

// MARK: - Category

/// The kind of problem being reported. `rawValue` is a stable wire key sent to
/// the Worker (and used as an issue label); `displayName` is the localized UI
/// label. Don't change raw values without coordinating with the Worker.
enum ProblemReportCategory: String, CaseIterable, Identifiable {
    case bug
    case crash
    case feature
    case other

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .bug: return String(localized: "Something isn't working")
        case .crash: return String(localized: "App crashed or froze")
        case .feature: return String(localized: "Feature request")
        case .other: return String(localized: "Something else")
        }
    }

    /// GitHub issue-form template this category maps to (in `.github/ISSUE_TEMPLATE/`).
    var gitHubTemplate: String {
        switch self {
        case .feature: return "feature_request.yml"
        case .bug, .crash, .other: return "bug_report.yml"
        }
    }

    /// Title prefix each GitHub issue form expects.
    var gitHubTitlePrefix: String {
        switch self {
        case .feature: return "Feature Request: "
        case .bug, .crash, .other: return "Bug: "
        }
    }
}

// MARK: - Draft

/// The user-entered contents of a problem report. Everything collected
/// automatically (diagnostics, log, installation id) is added at submit time.
struct ProblemReportDraft {
    var category: ProblemReportCategory = .bug
    var summary: String = ""
    var description: String = ""
    var email: String = ""
    var includeDiagnostics: Bool = true

    var trimmedSummary: String { summary.trimmingCharacters(in: .whitespacesAndNewlines) }
    var trimmedDescription: String { description.trimmingCharacters(in: .whitespacesAndNewlines) }
    var trimmedEmail: String { email.trimmingCharacters(in: .whitespacesAndNewlines) }
}

// MARK: - Errors

enum ProblemReportError: LocalizedError {
    /// The report endpoint isn't configured (`REPORT_ENDPOINT_URL`/`REPORT_APP_KEY` absent).
    case notConfigured
    /// The network request failed or the server returned a non-success status.
    case transportFailed(String)

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            return String(localized: "Automatic sending isn't available yet.")
        case .transportFailed(let detail):
            return detail
        }
    }
}

// MARK: - Manager

/// Coordinates the in-app "Report a Problem" flow: validates input, assembles the
/// multipart payload (user fields + optional diagnostics + recent log), and
/// submits it to the report Worker. Follows the app's manager-singleton pattern
/// (cf. `LyricsManager`); transient form state lives in the view.
final class ProblemReportManager {
    static let shared = ProblemReportManager()

    private init() {}

    // Field size caps, mirrored by the Worker's validation.
    static let maxSummaryLength = 200
    static let maxDescriptionLength = 5000

    /// Report Worker endpoint, read from Info.plist (populated from
    /// `Secrets.xcconfig`). When absent, `submit` throws `.notConfigured`.
    private var reportEndpoint: URL? {
        guard let string = Bundle.main.object(forInfoDictionaryKey: "REPORT_ENDPOINT_URL") as? String,
              !string.isEmpty else {
            return nil
        }
        return URL(string: string)
    }

    /// Embedded app key sent with each report (light anti-spam).
    private var appKey: String? {
        Bundle.main.object(forInfoDictionaryKey: "REPORT_APP_KEY") as? String
    }

    // MARK: - Validation

    /// Basic structural email validation. It can't detect fake or throwaway
    /// addresses; it only rejects obviously malformed input.
    func isValidEmail(_ email: String) -> Bool {
        let trimmed = email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count <= 254 else { return false }
        let pattern = "^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,}$"
        return trimmed.range(of: pattern, options: .regularExpression) != nil
    }

    /// Whether a draft is complete enough to submit (drives the Submit button).
    func isSubmittable(_ draft: ProblemReportDraft) -> Bool {
        !draft.trimmedSummary.isEmpty
            && !draft.trimmedDescription.isEmpty
            && isValidEmail(draft.email)
    }

    // MARK: - Submit

    /// Submits the report and returns a client-generated `reportId` the user can
    /// quote when following up. `diagnostics` is the pre-serialized snapshot JSON
    /// (gathered by the view on the main actor) or nil when the user opted out.
    @discardableResult
    func submit(_ draft: ProblemReportDraft, diagnostics: String?) async throws -> String {
        guard let endpoint = reportEndpoint, let appKey, !appKey.isEmpty else {
            throw ProblemReportError.notConfigured
        }

        let reportId = UUID().uuidString
        let boundary = "petrichor.\(UUID().uuidString)"

        var body = Data()
        func field(_ name: String, _ value: String) {
            body.append("--\(boundary)\r\n")
            body.append("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n")
            body.append(value)
            body.append("\r\n")
        }

        // Required fields (mirror the Worker's validation).
        field("reportId", reportId)
        field("installationId", DiagnosticSnapshot.installationId)
        field("category", draft.category.rawValue)
        field("summary", draft.trimmedSummary)
        field("description", draft.trimmedDescription)
        field("email", draft.trimmedEmail)
        field("appVersion", AppInfo.versionWithBuild)
        field("osVersion", AppInfo.osVersion)

        // Optional diagnostics: the snapshot as a `metadata` field and the recent
        // log as a plain-text `attachment`.
        if let diagnostics, !diagnostics.isEmpty {
            field("metadata", diagnostics)
            if let log = recentLogTail() {
                body.append("--\(boundary)\r\n")
                body.append("Content-Disposition: form-data; name=\"attachment\"; filename=\"petrichor-log.txt\"\r\n")
                body.append("Content-Type: text/plain; charset=utf-8\r\n\r\n")
                body.append(log)
                body.append("\r\n")
            }
        }

        body.append("--\(boundary)--\r\n")

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.setValue(appKey, forHTTPHeaderField: "X-Report-Key")
        request.setValue(AppInfo.userAgent, forHTTPHeaderField: "User-Agent")
        request.httpBody = body

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await AppInfo.urlSession.data(for: request)
        } catch {
            throw ProblemReportError.transportFailed(error.localizedDescription)
        }

        guard let http = response as? HTTPURLResponse else {
            throw ProblemReportError.transportFailed(String(localized: "No response from the server."))
        }
        guard (200...299).contains(http.statusCode) else {
            throw ProblemReportError.transportFailed(
                String(localized: "The server returned an error (\(http.statusCode)).")
            )
        }
        // Response is { ok, reportId, duplicate }; treat ok:false as a failure.
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let ok = json["ok"] as? Bool, !ok {
            let detail = (json["error"] as? String) ?? "unknown error"
            throw ProblemReportError.transportFailed(
                String(localized: "The server rejected the report (\(detail)).")
            )
        }

        return reportId
    }

    /// The tail of the current log file (capped) with the diagnostic-snapshot
    /// blocks removed, since the snapshot is already sent as `metadata`. Reads a
    /// copy; the log file on disk is left unchanged.
    private func recentLogTail(maxBytes: Int = 1024 * 1024) -> Data? {
        guard let url = Logger.logFileURL,
              let raw = try? String(contentsOf: url, encoding: .utf8),
              !raw.isEmpty else {
            return nil
        }
        let cleaned = stripDiagnosticBlocks(from: raw)
        guard let data = cleaned.data(using: .utf8), !data.isEmpty else { return nil }
        if data.count <= maxBytes { return data }
        // Start the tail at a line boundary so it doesn't begin mid-line or split
        // a UTF-8 sequence.
        let tail = data.suffix(maxBytes)
        if let newline = tail.firstIndex(of: 0x0A) {
            return Data(tail[tail.index(after: newline)...])
        }
        return Data(tail)
    }

    /// Drops "DIAGNOSTIC SNAPSHOT" blocks (the header line plus the JSON body
    /// under it) from a copy of the log. Real log lines start with a
    /// `[timestamp]` prefix; a snapshot's JSON body lines don't, so once a
    /// snapshot header is seen we skip lines until the next real entry.
    private func stripDiagnosticBlocks(from text: String) -> String {
        var kept: [Substring] = []
        var skipping = false
        for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let isEntry = line.first == "[" && (line.dropFirst().first?.isNumber ?? false)
            if skipping && !isEntry { continue }
            skipping = false
            if isEntry && line.contains("DIAGNOSTIC SNAPSHOT") {
                skipping = true
                continue
            }
            kept.append(line)
        }
        return kept.joined(separator: "\n")
    }

    // MARK: - GitHub hand-off

    /// Builds a GitHub "new issue" URL that pre-selects the issue form for the
    /// draft's category and pre-fills the title and description. Email and
    /// diagnostics are deliberately omitted (issues are public). Falls back to
    /// the template chooser if URL assembly fails.
    func gitHubIssueURL(for draft: ProblemReportDraft) -> URL {
        let fallback = URL(string: About.reportIssue) ?? URL(fileURLWithPath: "/")
        guard var components = URLComponents(string: "\(About.appWebsite)/issues/new") else {
            return fallback
        }

        var items = [URLQueryItem(name: "template", value: draft.category.gitHubTemplate)]

        let summary = draft.trimmedSummary
        if !summary.isEmpty {
            items.append(URLQueryItem(name: "title", value: draft.category.gitHubTitlePrefix + summary))
        }

        let description = draft.trimmedDescription
        if !description.isEmpty {
            items.append(URLQueryItem(name: "description", value: description))
        }

        if draft.category != .feature {
            items.append(URLQueryItem(name: "version", value: AppInfo.versionWithBuild))
        }

        components.queryItems = items
        return components.url ?? fallback
    }
}

private extension Data {
    /// Append a string's UTF-8 bytes (for multipart/form-data body assembly).
    mutating func append(_ string: String) {
        if let data = string.data(using: .utf8) { append(data) }
    }
}
