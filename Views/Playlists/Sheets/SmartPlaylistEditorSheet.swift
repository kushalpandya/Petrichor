import SwiftUI

// MARK: - Editable Rule

/// Mutable mirror of `SmartPlaylistCriteria.Rule` used while editing in the sheet
/// (the stored model's fields are `let`). Converted back to `Rule` on save.
private struct EditableRule: Identifiable {
    let id = UUID()
    var field: SmartField = .artist
    var condition: SmartPlaylistCriteria.Condition = .contains
    var value: String = ""

    /// A rule is complete (and worth saving) when its value editor always carries a
    /// value (boolean / date) or the user supplied a valid one (text / number / duration).
    var isComplete: Bool {
        switch field.valueKind {
        case .boolean, .date:
            return true
        case .duration:
            return SmartPlaylistDuration.seconds(from: value.trimmingCharacters(in: .whitespacesAndNewlines)) != nil
        case .text, .number:
            return !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }
}

// MARK: - Smart Playlist Editor Sheet

struct SmartPlaylistEditorSheet: View {
    @EnvironmentObject var playlistManager: PlaylistManager
    @Binding var isPresented: Bool

    private let editingPlaylistID: UUID?

    @State private var name: String
    @State private var matchType: SmartPlaylistCriteria.MatchType
    @State private var rules: [EditableRule]
    @State private var limitEnabled: Bool
    @State private var limitValue: Int
    @State private var sortField: SmartField
    @State private var sortAscending: Bool
    @State private var autoUpdate: Bool

    // Live "Matches N songs" count. nil while a count is in flight (debounced).
    @State private var matchCount: Int?
    @State private var countTask: Task<Void, Never>?

    init(isPresented: Binding<Bool>, editingPlaylist: Playlist?) {
        self._isPresented = isPresented
        self.editingPlaylistID = editingPlaylist?.id

        if let playlist = editingPlaylist, let criteria = playlist.smartCriteria {
            _name = State(initialValue: playlist.name)
            _matchType = State(initialValue: criteria.matchType)
            let mapped = criteria.rules.map { rule -> EditableRule in
                let field = SmartField(rawValue: rule.field) ?? .artist
                // Duration is stored as seconds but edited as H:MM:SS.
                var value = rule.value
                if field.valueKind == .duration, let seconds = Double(rule.value) {
                    value = SmartPlaylistDuration.text(fromSeconds: seconds)
                }
                return EditableRule(field: field, condition: rule.condition, value: value)
            }
            _rules = State(initialValue: mapped.isEmpty ? [EditableRule()] : mapped)
            _limitEnabled = State(initialValue: criteria.limit != nil)
            _limitValue = State(initialValue: criteria.limit ?? 25)
            // Fall back to a sortable field so the "selected by" Picker selection is always a valid tag.
            let storedSort = SmartField(rawValue: criteria.sortBy ?? "")
            _sortField = State(initialValue: storedSort.flatMap { SmartField.sortableFields.contains($0) ? $0 : nil } ?? .dateAdded)
            _sortAscending = State(initialValue: criteria.sortAscending)
            _autoUpdate = State(initialValue: criteria.autoUpdate)
        } else {
            _name = State(initialValue: "")
            _matchType = State(initialValue: .all)
            _rules = State(initialValue: [EditableRule()])
            _limitEnabled = State(initialValue: false)
            _limitValue = State(initialValue: 25)
            _sortField = State(initialValue: .dateAdded)
            _sortAscending = State(initialValue: false)
            _autoUpdate = State(initialValue: true)
        }
    }

    private var isEditing: Bool { editingPlaylistID != nil }

    private var headerTitle: String {
        isEditing ? String(localized: "Edit Smart Playlist") : String(localized: "New Smart Playlist")
    }

    private var saveButtonTitle: String {
        isEditing ? String(localized: "Save") : String(localized: "Create")
    }

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        rules.contains { $0.isComplete }
    }

    var body: some View {
        VStack(spacing: 0) {
            PlaylistEditorHeader(title: headerTitle) { isPresented = false }
            Divider()
            PlaylistNameField(name: $name)
            Divider()
            content
            Divider()
            PlaylistEditorFooter(
                summary: matchSummary,
                saveTitle: saveButtonTitle,
                canSave: canSave,
                onCancel: { isPresented = false },
                onSave: { save() }
            )
        }
        .frame(width: 640, height: 560)
        .onAppear { scheduleMatchCount() }
        .onChange(of: criteriaSignature) { scheduleMatchCount() }
        .onDisappear { countTask?.cancel() }
    }

    // MARK: - Content

    private var content: some View {
        VStack(alignment: .leading, spacing: 16) {
            matchSelector

            // Only the rules list scrolls, so the name/match controls stay pinned at the
            // top and the limit/auto-update options stay pinned above the footer no matter
            // how many condition rows the user adds.
            ScrollView {
                rulesList
                    // Reserve room for the overlay scrollbar so it never draws on top of
                    // the per-row remove (-) button and block clicks.
                    .padding(.trailing, 16)
                    // Top inset so the first row's text-field focus ring isn't clipped by
                    // the scroll container's edge.
                    .padding(.top, 4)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

            Divider()

            optionsSection
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var matchSelector: some View {
        HStack(spacing: 6) {
            Text("Match")
            Picker("", selection: $matchType) {
                Text("all").tag(SmartPlaylistCriteria.MatchType.all)
                Text("any").tag(SmartPlaylistCriteria.MatchType.any)
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .fixedSize()
            Text("of the following rules")
            Spacer()
        }
        .font(.subheadline)
    }

    private var rulesList: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach($rules) { $rule in
                SmartRuleRow(
                    rule: $rule,
                    canRemove: rules.count > 1,
                    onAdd: { addRule(after: rule) },
                    onRemove: { removeRule(rule) }
                )
            }
        }
    }

    private var optionsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                Toggle(isOn: $limitEnabled) {
                    Text("Limit to")
                }
                .toggleStyle(.checkbox)

                TextField("", value: $limitValue, format: .number)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 60)
                    .disabled(!limitEnabled)

                Text("tracks")
                    .foregroundColor(limitEnabled ? .primary : .secondary)
            }

            // Selection sort, only meaningful when limiting (it decides which tracks survive)
            if limitEnabled {
                HStack(spacing: 10) {
                    Text("selected by")
                        .foregroundColor(.secondary)

                    Picker("", selection: $sortField) {
                        ForEach(SmartField.sortableFields) { field in
                            Text(field.displayName).tag(field)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .frame(width: RuleLayout.fieldWidth)

                    Picker("", selection: $sortAscending) {
                        Text("Ascending").tag(true)
                        Text("Descending").tag(false)
                    }
                    .labelsHidden()
                    .pickerStyle(.radioGroup)
                    .horizontalRadioGroupLayout()
                }
                .font(.subheadline)
                .padding(.leading, 20)
            }

            Toggle(isOn: $autoUpdate) {
                Text("Update automatically on library changes")
            }
            .toggleStyle(.checkbox)
        }
    }

    // MARK: - Actions

    private func addRule(after rule: EditableRule) {
        guard let index = rules.firstIndex(where: { $0.id == rule.id }) else {
            rules.append(EditableRule())
            return
        }
        rules.insert(EditableRule(), at: index + 1)
    }

    private func removeRule(_ rule: EditableRule) {
        guard rules.count > 1 else { return }
        rules.removeAll { $0.id == rule.id }
    }

    /// Converts the in-progress editor rows into persisted rules, dropping incomplete ones.
    private func buildValidRules() -> [SmartPlaylistCriteria.Rule] {
        rules.compactMap { rule -> SmartPlaylistCriteria.Rule? in
            guard rule.isComplete else { return nil }
            var value = rule.value.trimmingCharacters(in: .whitespacesAndNewlines)
            // Duration is edited as H:MM:SS but persisted (and compared) as seconds.
            if rule.field.valueKind == .duration, let seconds = SmartPlaylistDuration.seconds(from: value) {
                value = String(Int(seconds))
            }
            return SmartPlaylistCriteria.Rule(field: rule.field.rawValue, condition: rule.condition, value: value)
        }
    }

    private func save() {
        let validRules = buildValidRules()
        guard !validRules.isEmpty else { return }

        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let criteria = SmartPlaylistCriteria(
            matchType: matchType,
            rules: validRules,
            limit: limitEnabled ? max(1, limitValue) : nil,
            sortBy: limitEnabled ? sortField.rawValue : "dateAdded",
            sortAscending: limitEnabled ? sortAscending : true,
            autoUpdate: autoUpdate
        )

        if let editingID = editingPlaylistID {
            playlistManager.updateSmartPlaylistCriteria(playlistID: editingID, name: trimmedName, criteria: criteria)
        } else {
            playlistManager.createSmartPlaylist(name: trimmedName, criteria: criteria)
        }

        isPresented = false
    }

    // MARK: - Live Match Count

    /// Cheap signature of the rule-defining inputs so the count only re-runs on real edits
    /// (the limit/sort/auto-update options don't change how many tracks match).
    private var criteriaSignature: String {
        matchType.rawValue + "|" + rules
            .map { "\($0.field.rawValue):\($0.condition.rawValue):\($0.value)" }
            .joined(separator: ";")
    }

    /// Footer text: nil when there are no complete rules to count, a placeholder while the
    /// debounced query is in flight, otherwise "Matches N songs".
    private var matchSummary: String? {
        guard rules.contains(where: { $0.isComplete }) else { return nil }
        guard let count = matchCount else { return String(localized: "Checking matches…") }
        return String(localized: "Matches \(HelperUtils.songCount(count))")
    }

    private func scheduleMatchCount() {
        countTask?.cancel()

        let validRules = buildValidRules()
        guard !validRules.isEmpty else {
            matchCount = 0
            return
        }

        matchCount = nil // mark in flight so the footer shows the placeholder
        let criteria = SmartPlaylistCriteria(matchType: matchType, rules: validRules)

        countTask = Task {
            try? await Task.sleep(nanoseconds: TimeConstants.searchDebounceDuration)
            guard !Task.isCancelled else { return }

            let count = await playlistManager.countMatches(for: criteria)

            await MainActor.run {
                guard !Task.isCancelled else { return }
                matchCount = count
            }
        }
    }
}

// MARK: - Rule Row Layout

/// Shared widths/spacing so every control in a rule row lines up across rows. The widths
/// are kept small enough that a full row fits inside the sheet without overflowing, which
/// is what previously compressed the dropdowns and ate the side padding.
private enum RuleLayout {
    static let fieldWidth: CGFloat = 150
    static let operatorWidth: CGFloat = 150
    static let valueWidth: CGFloat = 150
    static let spacing: CGFloat = 8
}

// MARK: - Smart Rule Row

private struct SmartRuleRow: View {
    @Binding var rule: EditableRule
    let canRemove: Bool
    let onAdd: () -> Void
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: RuleLayout.spacing) {
            Picker("", selection: $rule.field) {
                ForEach(SmartField.allCases) { field in
                    Text(field.displayName).tag(field)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .frame(width: RuleLayout.fieldWidth)
            .onChange(of: rule.field) { _, newField in
                // Keep operator/value valid for the newly-selected field.
                if !newField.operators.contains(rule.condition) {
                    rule.condition = newField.operators.first ?? .equals
                }
                rule.value = newField.defaultValue
            }

            Picker("", selection: conditionBinding) {
                ForEach(rule.field.operators, id: \.self) { condition in
                    Text(condition.displayName(for: rule.field.valueKind)).tag(condition)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .frame(width: RuleLayout.operatorWidth)

            valueEditor

            Spacer(minLength: 0)

            Button(action: onRemove) {
                Image(systemName: "minus")
                    .frame(width: 14, height: 14)
            }
            .buttonStyle(.bordered)
            .disabled(!canRemove)
            .help("Remove rule")

            Button(action: onAdd) {
                Image(systemName: "plus")
                    .frame(width: 14, height: 14)
            }
            .buttonStyle(.bordered)
            .help("Add rule")
        }
    }

    @ViewBuilder private var valueEditor: some View {
        switch rule.field.valueKind {
        case .text:
            TextField("Value", text: $rule.value)
                .textFieldStyle(.roundedBorder)
                .frame(width: RuleLayout.valueWidth)

        case .number:
            TextField("Value", text: $rule.value)
                .textFieldStyle(.roundedBorder)
                .frame(width: RuleLayout.valueWidth)
                .onChange(of: rule.value) { _, newValue in
                    let digits = newValue.filter { $0.isNumber }
                    if digits != newValue { rule.value = digits }
                }

        case .duration:
            TextField("H:MM:SS", text: $rule.value)
                .textFieldStyle(.roundedBorder)
                .frame(width: RuleLayout.valueWidth)
                .onChange(of: rule.value) { _, newValue in
                    let allowed = newValue.filter { $0.isNumber || $0 == ":" }
                    if allowed != newValue { rule.value = allowed }
                }

        case .date:
            DatePicker("", selection: dateBinding, displayedComponents: [.date])
                .labelsHidden()
                .datePickerStyle(.field)
                .frame(width: RuleLayout.valueWidth)

        case .boolean:
            Picker("", selection: boolBinding) {
                Text("Yes").tag(true)
                Text("No").tag(false)
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .frame(width: RuleLayout.valueWidth)
        }
    }

    /// Coerces the operator selection to always be one of the current field's valid
    /// operators. Without this, switching to a field whose operator set excludes the
    /// previously-selected condition leaves the menu holding a value that is no longer
    /// an option.
    private var conditionBinding: Binding<SmartPlaylistCriteria.Condition> {
        Binding(
            get: {
                let operators = rule.field.operators
                return operators.contains(rule.condition) ? rule.condition : (operators.first ?? .equals)
            },
            set: { rule.condition = $0 }
        )
    }

    /// Bridges the stored "yyyy-MM-dd" value string to the Date the picker edits.
    private var dateBinding: Binding<Date> {
        Binding(
            get: { SmartPlaylistDate.date(from: rule.value) ?? Date() },
            set: { rule.value = SmartPlaylistDate.string(from: $0) }
        )
    }

    /// Bridges the stored "true"/"false" value string to a Bool the picker edits.
    private var boolBinding: Binding<Bool> {
        Binding(
            get: { rule.value.lowercased() == "true" },
            set: { rule.value = $0 ? "true" : "false" }
        )
    }
}
