import SwiftUI
import AppKit

/// Contents of the dedicated "Report a Problem" window, opened from the Help
/// menu. Collects a problem description plus a required contact email, and
/// (optionally) attaches the diagnostic snapshot and recent log. Submitting
/// hands off to `ProblemReportManager`; on failure it suggests reporting on
/// GitHub.
struct ReportProblemView: View {
    @Environment(\.dismiss)
    private var dismiss

    private let manager = ProblemReportManager.shared

    @State private var draft = ProblemReportDraft()
    @State private var phase: Phase = .editing
    @State private var showDiagnosticDetails = true
    @State private var diagnosticPreview = ""
    @State private var showSendFailure = false

    private enum Phase: Equatable {
        case editing
        case submitting
        case sent(reportId: String)
    }

    var body: some View {
        Group {
            switch phase {
            case .editing, .submitting:
                formContent
            case .sent(let reportId):
                sentContent(reportId: reportId)
            }
        }
        .frame(
            minWidth: 480,
            idealWidth: 560,
            maxWidth: 780,
            minHeight: 560,
            idealHeight: 680,
            maxHeight: 940
        )
        // On failure we keep the user on the form (their input is preserved) and
        // nudge them toward filing on GitHub.
        .alert(
            String(localized: "Couldn't send your report"),
            isPresented: $showSendFailure
        ) {
            Button("Report on GitHub") {
                NSWorkspace.shared.open(manager.gitHubIssueURL(for: draft))
            }
            Button("Not Now", role: .cancel) { }
        } message: {
            Text("Try again, or report it on GitHub.")
        }
    }

    // MARK: - Form

    private var formContent: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("What went wrong?")
                            .font(.headline)

                        labeledField("Type") {
                            Picker("", selection: $draft.category) {
                                ForEach(ProblemReportCategory.allCases) { category in
                                    Text(category.displayName).tag(category)
                                }
                            }
                            .labelsHidden()
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }

                        labeledField("Summary") {
                            TextField("", text: $draft.summary, prompt: Text("A brief summary of the issue"))
                                .textFieldStyle(.plain)
                                .font(.body)
                                .fieldBox()
                                .onChange(of: draft.summary) { _, value in
                                    draft.summary = String(value.prefix(ProblemReportManager.maxSummaryLength))
                                }
                        }

                        labeledField("Description") {
                            VStack(alignment: .leading, spacing: 4) {
                                TextEditor(text: $draft.description)
                                    .font(.body)
                                    .frame(minHeight: 120)
                                    .scrollContentBackground(.hidden)
                                    .fieldBox()
                                    .onChange(of: draft.description) { _, value in
                                        draft.description = String(value.prefix(ProblemReportManager.maxDescriptionLength))
                                    }
                                Text("What happened, and what steps lead to it?")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }

                    Divider()

                    VStack(alignment: .leading, spacing: 12) {
                        Text("How can we reach you?")
                            .font(.headline)

                        labeledField("Email") {
                            VStack(alignment: .leading, spacing: 4) {
                                TextField("", text: $draft.email, prompt: Text("you@example.com"))
                                    .textFieldStyle(.plain)
                                    .textContentType(.emailAddress)
                                    .disableAutocorrection(true)
                                    .font(.body)
                                    .fieldBox()
                                // swiftlint:disable:next line_length
                                Text("A real address lets us follow up if we need more detail to fix your issue. It's used only for that. Your email is never shared, sold, or published anywhere.")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }

                    Divider()

                    VStack(alignment: .leading, spacing: 12) {
                        Text("Diagnostics")
                            .font(.headline)
                        Toggle("Include diagnostic info and recent logs", isOn: $draft.includeDiagnostics)
                        if draft.includeDiagnostics {
                            diagnosticsDisclosure
                        }
                    }
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            // Built after first paint (not in .onAppear) so gathering the
            // snapshot doesn't hitch the window's appearance.
            .task {
                if diagnosticPreview.isEmpty {
                    diagnosticPreview = DiagnosticSnapshot.prettyJSON(phase: "report")
                }
            }

            Divider()
            footer
        }
    }

    /// A field label above its content, left-aligned and full width.
    @ViewBuilder
    private func labeledField<Content: View>(
        _ title: LocalizedStringKey,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.subheadline)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var diagnosticsDisclosure: some View {
        Group {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) { showDiagnosticDetails.toggle() }
            } label: {
                HStack {
                    Text("What's included?")
                    Spacer()
                    Image(systemName: Icons.chevronRight)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .rotationEffect(.degrees(showDiagnosticDetails ? 90 : 0))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if showDiagnosticDetails {
                VStack(alignment: .leading, spacing: 8) {
                    // swiftlint:disable:next line_length
                    Text("App and macOS version, your Mac's hardware, library statistics, and your app settings. No file names, no account passwords, and no personal content. Only whether integrations are connected, never their credentials.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    Text("The exact diagnostic data attached to your report:")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    ScrollView {
                        Text(diagnosticPreview)
                            .font(.caption.monospaced())
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(8)
                    }
                    .frame(height: 180)
                    .background(Color(nsColor: .textBackgroundColor))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Color.secondary.opacity(0.25), lineWidth: 1)
                    )

                    Label(
                        "Your most recent app log is attached as well, so we can see what happened around the issue.",
                        systemImage: "doc.text"
                    )
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private var footer: some View {
        HStack {
            Button("Report on GitHub instead") {
                NSWorkspace.shared.open(manager.gitHubIssueURL(for: draft))
            }
            .buttonStyle(.link)
            // swiftlint:disable:next line_length
            .help("Opens a pre-filled GitHub issue with your summary and description. Your email and diagnostics are not included, since GitHub issues are public.")

            Spacer()
            Button("Cancel") { dismiss() }
                .keyboardShortcut(.cancelAction)

            Button {
                submit()
            } label: {
                if phase == .submitting {
                    ProgressView()
                        .controlSize(.small)
                        .frame(width: 60)
                } else {
                    Text("Send Report")
                        .frame(minWidth: 60)
                }
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.defaultAction)
            .disabled(phase == .submitting || !manager.isSubmittable(draft))
        }
        .padding(16)
    }

    // MARK: - Sent

    private func sentContent(reportId: String) -> some View {
        resultContent(
            symbol: "checkmark.circle.fill",
            tint: .green,
            title: "Report sent",
            message: "Thanks for helping improve Petrichor. If we need more detail, we'll reach out to the email you provided."
        ) {
            Text("Reference: \(reportId)")
                .font(.caption.monospaced())
                .foregroundColor(.secondary)
                .textSelection(.enabled)

            Button("Close") { dismiss() }
                .keyboardShortcut(.defaultAction)
        }
    }

    @ViewBuilder
    private func resultContent<Actions: View>(
        symbol: String,
        tint: Color,
        title: LocalizedStringKey,
        message: LocalizedStringKey,
        @ViewBuilder actions: () -> Actions
    ) -> some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: symbol)
                .font(.system(size: 48))
                .foregroundColor(tint)
            Text(title)
                .font(.title2.bold())
            Text(message)
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 380)
            actions()
            Spacer()
        }
        .padding(24)
    }

    // MARK: - Actions

    private func submit() {
        phase = .submitting
        showSendFailure = false
        // Gather diagnostics on the main actor (the snapshot reads app managers);
        // reuse the cached preview, computing only if the .task hasn't run yet.
        let diagnostics = draft.includeDiagnostics
            ? (diagnosticPreview.isEmpty ? DiagnosticSnapshot.prettyJSON(phase: "report") : diagnosticPreview)
            : nil
        Task {
            do {
                let reportId = try await manager.submit(draft, diagnostics: diagnostics)
                phase = .sent(reportId: reportId)
            } catch {
                // Stay on the form (input preserved); the alert suggests GitHub.
                Logger.error("Report submission failed: \(error.localizedDescription)")
                phase = .editing
                showSendFailure = true
            }
        }
    }
}

private extension View {
    /// Wraps a field control in the report form's standard bordered input box
    /// (padding + text background + subtle rounded border).
    func fieldBox() -> some View {
        self
            .padding(6)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color(nsColor: .textBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color.secondary.opacity(0.25), lineWidth: 1)
            )
    }
}
