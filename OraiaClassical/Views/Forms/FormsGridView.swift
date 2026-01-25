import SwiftUI

struct FormsGridView: View {
    let lemmaID: Int64
    let lemmaHeadword: String
    let posCode: String

    @State private var studyMode: StudyMode = .reference
    @State private var showVerbFilters = false

    var body: some View {
        VStack(spacing: 16) {
            header

            switch posCode {
            case "noun":
                NounFormsView(lemmaID: lemmaID, studyMode: $studyMode)
            case "verb":
                VerbFormsView(lemmaID: lemmaID, studyMode: $studyMode)
            default:
                Text("No forms available for this part of speech.")
                    .foregroundColor(.secondary)
                    .padding(.top, 40)
            }
        }
        .padding(.top, 16)
        .navigationTitle("Forms")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if posCode == "verb" {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        showVerbFilters = true
                    } label: {
                        Image(systemName: "slider.horizontal.3")
                    }
                    .accessibilityLabel("Verb Filters")
                }
            }
        }
        .sheet(isPresented: $showVerbFilters) {
            VerbGridFilterSettingsView()
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(lemmaHeadword)
                .font(.title2.weight(.semibold))

            if let description = posDescription {
                Text(description)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }

            Picker("Study Mode", selection: $studyMode) {
                ForEach(StudyMode.allCases) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .pickerStyle(.segmented)
        }
        .padding(.horizontal, 20)
    }

    private var posDescription: String? {
        switch posCode {
        case "noun":
            return "Declined by number and case (singular, dual, plural; nominative, genitive, dative, accusative, vocative)."
        case "verb":
            return "Conjugated by person, number, tense, voice, and mood."
        default:
            return nil
        }
    }
}

enum StudyMode: String, CaseIterable, Identifiable {
    case reference = "Reference"
    case quiz = "Quiz"

    var id: String { rawValue }
}

struct QuizEntryState: Equatable {
    var input: String = ""
    var isCorrect: Bool = false
    var isRevealed: Bool = false
}

struct QuizProgress: Equatable {
    let correct: Int
    let total: Int

    var percentage: Double {
        guard total > 0 else { return 0 }
        return Double(correct) / Double(total)
    }

    var displayText: String {
        guard total > 0 else { return "0 / 0 correct" }
        return "\(correct) / \(total) correct"
    }
}

private struct QuizToolbar: View {
    let progress: QuizProgress
    let revealed: Bool
    let onReset: () -> Void
    let onReveal: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(progress.displayText)
                    .font(.subheadline.weight(.semibold))

                ProgressView(value: progress.percentage)
                    .progressViewStyle(.linear)
            }

            HStack(spacing: 12) {
                Button("Reset Quiz") {
                    onReset()
                }
                .buttonStyle(.bordered)

                Button(revealed ? "Hide Answers" : "Reveal Answers") {
                    if revealed {
                        onReset()
                    } else {
                        onReveal()
                    }
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(.horizontal, 20)
    }
}

// MARK: - Noun Forms

private struct NounFormsView: View {
    let lemmaID: Int64
    @Binding var studyMode: StudyMode

    @StateObject private var viewModel: NounFormsViewModel
    @State private var quizEntries: [Int64: QuizEntryState] = [:]

    init(lemmaID: Int64, studyMode: Binding<StudyMode>) {
        self.lemmaID = lemmaID
        _studyMode = studyMode
        _viewModel = StateObject(wrappedValue: NounFormsViewModel(lemmaID: lemmaID))
    }

    var body: some View {
        VStack(spacing: 16) {
            switch viewModel.isLoading {
            case true:
                ProgressView()
                    .padding(.top, 40)
            case false:
                if let error = viewModel.errorMessage {
                    Text(error)
                        .foregroundColor(.secondary)
                        .padding(.top, 40)
                } else {
                    if studyMode == .quiz {
                        QuizToolbar(progress: quizProgress, revealed: allAnswersRevealed, onReset: resetQuiz, onReveal: revealAllAnswers)
                            .transition(.opacity)
                    }
                    nounContent
                }
            }
        }
        .padding(.bottom, 32)
        .onAppear {
            viewModel.load()
        }
        .onChange(of: studyMode) { _ in
            if studyMode == .quiz { synchronizeQuizEntries() }
        }
        .onChange(of: viewModel.forms) { _ in
            synchronizeQuizEntries()
        }
    }

    private var nounContent: some View {
        let dialectSections = NounDialectSection.build(from: viewModel.forms)
        return Group {
            if dialectSections.isEmpty {
                EmptyFormsPlaceholder(message: "No nominal forms available yet.")
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        ForEach(dialectSections) { section in
                            VStack(alignment: .leading, spacing: 16) {
                                Text(section.title)
                                    .font(.title3.weight(.semibold))
                                ForEach(section.numberSections) { numberSection in
                                    VStack(alignment: .leading, spacing: 12) {
                                        Text(numberSection.title)
                                            .font(.headline)
                                            .foregroundColor(.secondary)
                                        ForEach(numberSection.rows) { row in
                                            NounCaseCard(row: row, mode: studyMode, quizBinding: quizBinding)
                                        }
                                    }
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                }
            }
        }
    }

    private func synchronizeQuizEntries() {
        let currentIDs = Set(viewModel.forms.map(\.id))
        var updated: [Int64: QuizEntryState] = [:]
        for id in currentIDs {
            updated[id] = quizEntries[id] ?? QuizEntryState()
        }
        quizEntries = updated
    }

    private func quizBinding(for id: Int64, answer: String) -> Binding<QuizEntryState> {
        Binding(
            get: { quizEntries[id] ?? QuizEntryState() },
            set: { newValue in
                var evaluated = newValue
                let trimmed = evaluated.input.trimmed()
                evaluated.isCorrect = evaluated.isRevealed || trimmed.equalsMorph(answer)
                quizEntries[id] = evaluated
            }
        )
    }

    private var quizProgress: QuizProgress {
        let total = quizEntries.count
        guard total > 0 else { return .init(correct: 0, total: 0) }
        let correct = quizEntries.values.filter { $0.isCorrect }.count
        return QuizProgress(correct: correct, total: total)
    }

    private var allAnswersRevealed: Bool {
        quizEntries.values.allSatisfy { $0.isRevealed }
    }

    private func resetQuiz() {
        for key in Array(quizEntries.keys) {
            quizEntries[key] = QuizEntryState()
        }
    }

    private func revealAllAnswers() {
        for form in viewModel.forms {
            quizEntries[form.id] = QuizEntryState(input: form.form, isCorrect: true, isRevealed: true)
        }
    }
}

private struct NounDialectSection: Identifiable {
    let id: String
    let title: String
    let numberSections: [NounNumberSection]

    static func build(from forms: [NounForm]) -> [NounDialectSection] {
        guard !forms.isEmpty else { return [] }
        let grouped = Dictionary(grouping: forms) { $0.dialect.lowercased() }
        let orderedDialects = dialectOrder

        return grouped
            .sorted { lhs, rhs in
                orderedDialects.index(of: lhs.key) < orderedDialects.index(of: rhs.key)
            }
            .map { key, forms in
                let sections = NounNumberSection.build(from: forms)
                return NounDialectSection(id: key, title: key.displayTitle(defaultTitle: key), numberSections: sections)
            }
    }
}

private struct NounNumberSection: Identifiable {
    let id: String
    let title: String
    let rows: [NounCaseRow]

    static func build(from forms: [NounForm]) -> [NounNumberSection] {
        let grouped = Dictionary(grouping: forms) { $0.number?.lowercased() ?? "unspecified" }
        let order = ["singular", "dual", "plural", "unspecified"]

        return grouped
            .sorted { lhs, rhs in
                order.index(of: lhs.key) < order.index(of: rhs.key)
            }
            .map { key, forms in
                let rows = NounCaseRow.build(from: forms)
                return NounNumberSection(id: key, title: key.displayTitle(defaultTitle: "Mixed Number"), rows: rows)
            }
            .filter { !$0.rows.isEmpty }
    }
}

private struct NounCaseRow: Identifiable {
    let id: String
    let caseLabel: String
    let entries: [NounEntry]

    static func build(from forms: [NounForm]) -> [NounCaseRow] {
        let grouped = Dictionary(grouping: forms) { $0.grammaticalCase?.lowercased() ?? "unspecified" }
        let order = ["nominative", "genitive", "dative", "accusative", "vocative", "unspecified"]

        return grouped
            .sorted { lhs, rhs in
                order.index(of: lhs.key) < order.index(of: rhs.key)
            }
            .map { key, forms in
                let entries = forms.sorted { $0.id < $1.id }.map { NounEntry(form: $0) }
                return NounCaseRow(id: key, caseLabel: key.displayTitle(defaultTitle: "Other Case"), entries: entries)
            }
    }
}

private struct NounEntry: Identifiable {
    let id: Int64
    let display: String
    let genderLabel: String?
    let answer: String

    init(form: NounForm) {
        id = form.id
        display = form.form
        answer = form.form
        if let gender = form.gender, !gender.isEmpty {
            genderLabel = gender.displayTitle(defaultTitle: gender)
        } else {
            genderLabel = nil
        }
    }
}

private struct NounCaseCard: View {
    let row: NounCaseRow
    let mode: StudyMode
    let quizBinding: (Int64, String) -> Binding<QuizEntryState>

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(row.caseLabel)
                .font(.headline)

            VStack(spacing: 10) {
                ForEach(row.entries) { entry in
                    switch mode {
                    case .reference:
                        NounReferenceRow(entry: entry)
                    case .quiz:
                        NounQuizRow(entry: entry, state: quizBinding(entry.id, entry.answer))
                    }
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(.secondarySystemBackground))
        )
    }
}

private struct NounReferenceRow: View {
    let entry: NounEntry

    var body: some View {
        HStack(spacing: 12) {
            if let gender = entry.genderLabel {
                TagPill(text: gender, color: Color.blue.opacity(0.15), foreground: .blue)
            }

            Text(entry.display)
                .font(.body)

            Spacer()
        }
    }
}

private struct NounQuizRow: View {
    let entry: NounEntry
    @Binding var state: QuizEntryState

    private var borderColor: Color {
        if state.isCorrect { return .green }
        if state.input.isEmpty { return Color.secondary.opacity(0.25) }
        return Color.orange.opacity(0.8)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let gender = entry.genderLabel {
                TagPill(text: gender, color: Color.blue.opacity(0.15), foreground: .blue)
            }

            TextField("Enter form", text: Binding(
                get: { state.input },
                set: { newValue in
                    state.input = newValue
                    if !state.isRevealed {
                        state.isCorrect = newValue.trimmed().equalsMorph(entry.answer)
                    }
                }
            ))
            .textInputAutocapitalization(.never)
            .disableAutocorrection(true)
            .padding(.vertical, 10)
            .padding(.horizontal, 12)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color(.systemBackground))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(borderColor, lineWidth: 1.5)
            )
            .overlay(alignment: .trailing) {
                if state.isCorrect {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                        .padding(.trailing, 12)
                }
            }

            if state.isRevealed && !state.input.equalsMorph(entry.answer) {
                Text(entry.answer)
                    .font(.footnote)
                    .foregroundColor(.secondary)
            }
        }
    }
}

// MARK: - Verb Forms

private struct VerbFormsView: View {
    let lemmaID: Int64
    @Binding var studyMode: StudyMode

    @StateObject private var viewModel: VerbFormsViewModel
    @State private var quizEntries: [Int64: QuizEntryState] = [:]

    @AppStorage(VerbGridFilterKeys.personFirst) private var includeFirstPerson = true
    @AppStorage(VerbGridFilterKeys.personSecond) private var includeSecondPerson = true
    @AppStorage(VerbGridFilterKeys.personThird) private var includeThirdPerson = true
    @AppStorage(VerbGridFilterKeys.personOther) private var includeOtherPerson = true

    @AppStorage(VerbGridFilterKeys.numberSingular) private var includeSingular = true
    @AppStorage(VerbGridFilterKeys.numberDual) private var includeDual = true
    @AppStorage(VerbGridFilterKeys.numberPlural) private var includePlural = true
    @AppStorage(VerbGridFilterKeys.numberOther) private var includeOtherNumber = true

    @AppStorage(VerbGridFilterKeys.dialectAttic) private var includeAttic = true
    @AppStorage(VerbGridFilterKeys.dialectDoric) private var includeDoric = true
    @AppStorage(VerbGridFilterKeys.dialectIonic) private var includeIonic = true
    @AppStorage(VerbGridFilterKeys.dialectAeolic) private var includeAeolic = true
    @AppStorage(VerbGridFilterKeys.dialectEpic) private var includeEpic = true
    @AppStorage(VerbGridFilterKeys.dialectKoine) private var includeKoine = true
    @AppStorage(VerbGridFilterKeys.dialectByzantine) private var includeByzantine = true
    @AppStorage(VerbGridFilterKeys.dialectUnspecified) private var includeUnspecifiedDialect = true

    init(lemmaID: Int64, studyMode: Binding<StudyMode>) {
        self.lemmaID = lemmaID
        _studyMode = studyMode
        _viewModel = StateObject(wrappedValue: VerbFormsViewModel(lemmaID: lemmaID))
    }

    var body: some View {
        VStack(spacing: 16) {
            switch viewModel.isLoading {
            case true:
                ProgressView()
                    .padding(.top, 40)
            case false:
                if let error = viewModel.errorMessage {
                    Text(error)
                        .foregroundColor(.secondary)
                        .padding(.top, 40)
                } else {
                    if studyMode == .quiz {
                        QuizToolbar(progress: quizProgress, revealed: allAnswersRevealed, onReset: resetQuiz, onReveal: revealAllAnswers)
                            .transition(.opacity)
                    }
                    verbContent
                }
            }
        }
        .padding(.bottom, 32)
        .onAppear {
            viewModel.load()
        }
        .onChange(of: studyMode) { _ in
            if studyMode == .quiz { synchronizeQuizEntries() }
        }
        .onChange(of: viewModel.forms) { _ in
            synchronizeQuizEntries()
        }
        .onChange(of: filterToken) { _ in
            synchronizeQuizEntries()
        }
    }

    private var verbContent: some View {
        let dialectSections = VerbDialectSection.build(from: filteredForms)
        return Group {
            if dialectSections.isEmpty {
                EmptyFormsPlaceholder(message: "No verbal forms match your filters.")
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        ForEach(dialectSections) { section in
                            VStack(alignment: .leading, spacing: 16) {
                                Text(section.title)
                                    .font(.title3.weight(.semibold))
                                ForEach(section.moodSections) { moodSection in
                                    VStack(alignment: .leading, spacing: 16) {
                                        Text(moodSection.title)
                                            .font(.headline)
                                            .foregroundColor(.secondary)
                                        ForEach(moodSection.groups) { group in
                                            VerbGroupCard(group: group, mode: studyMode, quizBinding: quizBinding)
                                        }
                                    }
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                }
            }
        }
    }

    private func synchronizeQuizEntries() {
        let currentIDs = Set(filteredForms.map(\.id))
        var updated: [Int64: QuizEntryState] = [:]
        for id in currentIDs {
            updated[id] = quizEntries[id] ?? QuizEntryState()
        }
        quizEntries = updated
    }

    private func quizBinding(for id: Int64, answer: String) -> Binding<QuizEntryState> {
        Binding(
            get: { quizEntries[id] ?? QuizEntryState() },
            set: { newValue in
                var evaluated = newValue
                let trimmed = evaluated.input.trimmed()
                evaluated.isCorrect = evaluated.isRevealed || trimmed.equalsMorph(answer)
                quizEntries[id] = evaluated
            }
        )
    }

    private var quizProgress: QuizProgress {
        let total = quizEntries.count
        guard total > 0 else { return .init(correct: 0, total: 0) }
        let correct = quizEntries.values.filter { $0.isCorrect }.count
        return QuizProgress(correct: correct, total: total)
    }

    private var allAnswersRevealed: Bool {
        quizEntries.values.allSatisfy { $0.isRevealed }
    }

    private func resetQuiz() {
        for key in Array(quizEntries.keys) {
            quizEntries[key] = QuizEntryState()
        }
    }

    private func revealAllAnswers() {
        for form in filteredForms {
            quizEntries[form.id] = QuizEntryState(input: form.form, isCorrect: true, isRevealed: true)
        }
    }

    private var filteredForms: [VerbForm] {
        let settings = VerbGridFilterSettings(
            includeFirstPerson: includeFirstPerson,
            includeSecondPerson: includeSecondPerson,
            includeThirdPerson: includeThirdPerson,
            includeOtherPerson: includeOtherPerson,
            includeSingular: includeSingular,
            includeDual: includeDual,
            includePlural: includePlural,
            includeOtherNumber: includeOtherNumber,
            includeAttic: includeAttic,
            includeDoric: includeDoric,
            includeIonic: includeIonic,
            includeAeolic: includeAeolic,
            includeEpic: includeEpic,
            includeKoine: includeKoine,
            includeByzantine: includeByzantine,
            includeUnspecifiedDialect: includeUnspecifiedDialect
        )
        return viewModel.forms.filter { settings.matches($0) }
    }

    private var filterToken: String {
        [
            includeFirstPerson,
            includeSecondPerson,
            includeThirdPerson,
            includeOtherPerson,
            includeSingular,
            includeDual,
            includePlural,
            includeOtherNumber,
            includeAttic,
            includeDoric,
            includeIonic,
            includeAeolic,
            includeEpic,
            includeKoine,
            includeByzantine,
            includeUnspecifiedDialect
        ]
        .map { $0 ? "1" : "0" }
        .joined()
    }
}

private enum VerbGridFilterKeys {
    static let personFirst = "verbGrid.filter.person.first"
    static let personSecond = "verbGrid.filter.person.second"
    static let personThird = "verbGrid.filter.person.third"
    static let personOther = "verbGrid.filter.person.other"

    static let numberSingular = "verbGrid.filter.number.singular"
    static let numberDual = "verbGrid.filter.number.dual"
    static let numberPlural = "verbGrid.filter.number.plural"
    static let numberOther = "verbGrid.filter.number.other"

    static let dialectAttic = "verbGrid.filter.dialect.attic"
    static let dialectDoric = "verbGrid.filter.dialect.doric"
    static let dialectIonic = "verbGrid.filter.dialect.ionic"
    static let dialectAeolic = "verbGrid.filter.dialect.aeolic"
    static let dialectEpic = "verbGrid.filter.dialect.epic"
    static let dialectKoine = "verbGrid.filter.dialect.koine"
    static let dialectByzantine = "verbGrid.filter.dialect.byzantine"
    static let dialectUnspecified = "verbGrid.filter.dialect.unspecified"
}

private struct VerbGridFilterSettings {
    let includeFirstPerson: Bool
    let includeSecondPerson: Bool
    let includeThirdPerson: Bool
    let includeOtherPerson: Bool

    let includeSingular: Bool
    let includeDual: Bool
    let includePlural: Bool
    let includeOtherNumber: Bool

    let includeAttic: Bool
    let includeDoric: Bool
    let includeIonic: Bool
    let includeAeolic: Bool
    let includeEpic: Bool
    let includeKoine: Bool
    let includeByzantine: Bool
    let includeUnspecifiedDialect: Bool

    func matches(_ form: VerbForm) -> Bool {
        matchesPerson(form) && matchesNumber(form) && matchesDialect(form)
    }

    private func matchesPerson(_ form: VerbForm) -> Bool {
        if let normalized = MorphologyNormalizer.normalizePerson(form.person) {
            switch normalized.key {
            case "first":
                return includeFirstPerson
            case "second":
                return includeSecondPerson
            case "third":
                return includeThirdPerson
            default:
                return includeOtherPerson
            }
        }
        return includeOtherPerson
    }

    private func matchesNumber(_ form: VerbForm) -> Bool {
        if let normalized = MorphologyNormalizer.normalizeNumber(form.number) {
            switch normalized.key {
            case "singular":
                return includeSingular
            case "dual":
                return includeDual
            case "plural":
                return includePlural
            default:
                return includeOtherNumber
            }
        }
        return includeOtherNumber
    }

    private func matchesDialect(_ form: VerbForm) -> Bool {
        let raw = form.dialect.trimmingCharacters(in: .whitespacesAndNewlines)
        let key = raw.isEmpty ? "unspecified" : raw.lowercased()
        switch key {
        case "attic":
            return includeAttic
        case "doric":
            return includeDoric
        case "ionic":
            return includeIonic
        case "aeolic":
            return includeAeolic
        case "epic":
            return includeEpic
        case "koine":
            return includeKoine
        case "byzantine":
            return includeByzantine
        default:
            return includeUnspecifiedDialect
        }
    }
}

private struct VerbGridFilterSettingsView: View {
    @Environment(\.dismiss) private var dismiss

    @AppStorage(VerbGridFilterKeys.personFirst) private var includeFirstPerson = true
    @AppStorage(VerbGridFilterKeys.personSecond) private var includeSecondPerson = true
    @AppStorage(VerbGridFilterKeys.personThird) private var includeThirdPerson = true
    @AppStorage(VerbGridFilterKeys.personOther) private var includeOtherPerson = true

    @AppStorage(VerbGridFilterKeys.numberSingular) private var includeSingular = true
    @AppStorage(VerbGridFilterKeys.numberDual) private var includeDual = true
    @AppStorage(VerbGridFilterKeys.numberPlural) private var includePlural = true
    @AppStorage(VerbGridFilterKeys.numberOther) private var includeOtherNumber = true

    @AppStorage(VerbGridFilterKeys.dialectAttic) private var includeAttic = true
    @AppStorage(VerbGridFilterKeys.dialectDoric) private var includeDoric = true
    @AppStorage(VerbGridFilterKeys.dialectIonic) private var includeIonic = true
    @AppStorage(VerbGridFilterKeys.dialectAeolic) private var includeAeolic = true
    @AppStorage(VerbGridFilterKeys.dialectEpic) private var includeEpic = true
    @AppStorage(VerbGridFilterKeys.dialectKoine) private var includeKoine = true
    @AppStorage(VerbGridFilterKeys.dialectByzantine) private var includeByzantine = true
    @AppStorage(VerbGridFilterKeys.dialectUnspecified) private var includeUnspecifiedDialect = true

    var body: some View {
        NavigationStack {
            Form {
                Section("Person") {
                    Toggle("First Person", isOn: $includeFirstPerson)
                    Toggle("Second Person", isOn: $includeSecondPerson)
                    Toggle("Third Person", isOn: $includeThirdPerson)
                    Toggle("Other / Unspecified", isOn: $includeOtherPerson)
                }

                Section("Number") {
                    Toggle("Singular", isOn: $includeSingular)
                    Toggle("Dual", isOn: $includeDual)
                    Toggle("Plural", isOn: $includePlural)
                    Toggle("Other / Unspecified", isOn: $includeOtherNumber)
                }

                Section("Dialect") {
                    Toggle("Attic", isOn: $includeAttic)
                    Toggle("Doric", isOn: $includeDoric)
                    Toggle("Ionic", isOn: $includeIonic)
                    Toggle("Aeolic", isOn: $includeAeolic)
                    Toggle("Epic", isOn: $includeEpic)
                    Toggle("Koine", isOn: $includeKoine)
                    Toggle("Byzantine", isOn: $includeByzantine)
                    Toggle("Unspecified / Other", isOn: $includeUnspecifiedDialect)
                }
            }
            .navigationTitle("Verb Grid Filters")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
}

private struct VerbDialectSection: Identifiable {
    let id: String
    let title: String
    let moodSections: [VerbMoodSection]

    static func build(from forms: [VerbForm]) -> [VerbDialectSection] {
        guard !forms.isEmpty else { return [] }
        let grouped = Dictionary(grouping: forms) { $0.dialect.lowercased() }
        let orderedDialects = dialectOrder

        return grouped
            .sorted { lhs, rhs in
                orderedDialects.index(of: lhs.key) < orderedDialects.index(of: rhs.key)
            }
            .map { key, forms in
                let sections = VerbMoodSection.build(from: forms)
                return VerbDialectSection(id: key, title: key.displayTitle(defaultTitle: key), moodSections: sections)
            }
    }
}

private struct VerbMoodSection: Identifiable {
    let id: String
    let title: String
    let groups: [VerbGroup]

    static func build(from forms: [VerbForm]) -> [VerbMoodSection] {
        let grouped = Dictionary(grouping: forms) { $0.mood?.lowercased() ?? "unspecified" }
        let order = ["indicative", "subjunctive", "optative", "imperative", "infinitive", "participle", "gerundive", "supine", "unspecified"]

        return grouped
            .sorted { lhs, rhs in
                order.index(of: lhs.key) < order.index(of: rhs.key)
            }
            .map { key, forms in
                VerbMoodSection(id: key, title: key.displayTitle(defaultTitle: "Other Mood"), groups: VerbGroup.build(from: forms))
            }
    }
}

private struct VerbGroup: Identifiable {
    let id: String
    let title: String
    let entries: [VerbEntry]

    static func build(from forms: [VerbForm]) -> [VerbGroup] {
        let grouped = Dictionary(grouping: forms) { form in
            let tense = form.tense?.lowercased() ?? "unspecified"
            let voice = form.voice?.lowercased() ?? "unspecified"
            return "\(tense)|\(voice)"
        }

        let tenseOrder = ["present", "imperfect", "future", "aorist", "perfect", "pluperfect", "future perfect", "unspecified"]
        let voiceOrder = ["active", "middle", "passive", "middle-passive", "unspecified"]

        return grouped
            .sorted { lhs, rhs in
                let lhsParts = lhs.key.split(separator: "|").map(String.init)
                let rhsParts = rhs.key.split(separator: "|").map(String.init)
                let lhsTense = lhsParts.first ?? ""
                let rhsTense = rhsParts.first ?? ""
                if tenseOrder.index(of: lhsTense) != tenseOrder.index(of: rhsTense) {
                    return tenseOrder.index(of: lhsTense) < tenseOrder.index(of: rhsTense)
                }
                let lhsVoice = lhsParts.dropFirst().first ?? ""
                let rhsVoice = rhsParts.dropFirst().first ?? ""
                return voiceOrder.index(of: lhsVoice) < voiceOrder.index(of: rhsVoice)
            }
            .map { key, forms in
                let parts = key.split(separator: "|").map(String.init)
                let titleParts = parts.enumerated().map { index, value in
                    value.displayTitle(defaultTitle: index == 0 ? "Other Tense" : "Other Voice")
                }
                return VerbGroup(
                    id: key,
                    title: titleParts.joined(separator: " • "),
                    entries: VerbEntry.buildOthers(from: forms, excluding: [])
                )
            }
    }
}

private struct VerbGroupCard: View {
    let group: VerbGroup
    let mode: StudyMode
    let quizBinding: (Int64, String) -> Binding<QuizEntryState>

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(group.title)
                .font(.headline)

            if !group.entries.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(group.entries) { entry in
                        switch mode {
                        case .reference:
                            VerbReferenceRow(entry: entry, showMorphology: true)
                        case .quiz:
                            VerbQuizRow(entry: entry, state: quizBinding(entry.id, entry.answer), showMorphology: true)
                        }
                    }
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(.secondarySystemBackground))
        )
    }
}


private struct VerbReferenceRow: View {
    let entry: VerbEntry
    let showMorphology: Bool

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            Text(entry.display)
                .font(.body)

            Spacer(minLength: 0)

            HStack(spacing: 6) {
                if showMorphology, let person = entry.personLabel {
                    TagPill(text: person, color: Color.blue.opacity(0.12), foreground: .blue)
                }

                if showMorphology, let number = entry.numberLabel {
                    TagPill(text: number, color: Color.blue.opacity(0.12), foreground: .blue)
                }

            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(.systemBackground))
        )
    }
}

private struct VerbQuizRow: View {
    let entry: VerbEntry
    @Binding var state: QuizEntryState
    let showMorphology: Bool

    private var borderColor: Color {
        if state.isCorrect { return .green }
        if state.input.isEmpty { return Color.secondary.opacity(0.25) }
        return Color.orange.opacity(0.8)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if showMorphology {
                HStack(spacing: 6) {
                    if let person = entry.personLabel {
                        TagPill(text: person, color: Color.blue.opacity(0.12), foreground: .blue)
                    }

                    if let number = entry.numberLabel {
                        TagPill(text: number, color: Color.blue.opacity(0.12), foreground: .blue)
                    }
                }
            }

            TextField(entry.placeholder, text: Binding(
                get: { state.input },
                set: { newValue in
                    state.input = newValue
                    if !state.isRevealed {
                        state.isCorrect = newValue.trimmed().equalsMorph(entry.answer)
                    }
                }
            ))
            .textInputAutocapitalization(.never)
            .disableAutocorrection(true)
            .padding(.vertical, 10)
            .padding(.horizontal, 12)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color(.systemBackground))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(borderColor, lineWidth: 1.5)
            )
            .overlay(alignment: .trailing) {
                if state.isCorrect {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                        .padding(.trailing, 12)
                }
            }

            HStack(spacing: 6) {
                if let tense = entry.tenseLabel {
                    TagPill(text: tense, color: Color.green.opacity(0.12), foreground: .green)
                }

                if let mood = entry.moodLabel {
                    TagPill(text: mood, color: Color.green.opacity(0.12), foreground: .green)
                }

                if let voice = entry.voiceLabel {
                    TagPill(text: voice, color: Color.orange.opacity(0.15), foreground: .orange)
                }
            }

            if state.isRevealed && !state.input.equalsMorph(entry.answer) {
                Text(entry.answer)
                    .font(.footnote)
                    .foregroundColor(.secondary)
            }
        }
    }
}

private struct NormalizedMorph: Identifiable {
    let key: String
    let label: String
    let order: Int

    var id: String { key }
}

private enum MorphologyNormalizer {
    static func normalizeNumber(_ value: String?) -> NormalizedMorph? {
        guard let cleaned = cleanedValue(from: value) else { return nil }

        if cleaned.contains("sing") || ["sg", "s"].contains(cleaned) {
            return NormalizedMorph(key: "singular", label: "Singular", order: 0)
        }

        if cleaned.contains("dual") || ["du", "d"].contains(cleaned) {
            return NormalizedMorph(key: "dual", label: "Dual", order: 1)
        }

        if cleaned.contains("plur") || ["pl", "p"].contains(cleaned) {
            return NormalizedMorph(key: "plural", label: "Plural", order: 2)
        }

        return nil
    }

    static func normalizePerson(_ value: String?) -> NormalizedMorph? {
        guard let cleaned = cleanedValue(from: value) else { return nil }

        if cleaned.contains("first") || ["1st", "1", "i"].contains(cleaned) {
            return NormalizedMorph(key: "first", label: "First", order: 0)
        }

        if cleaned.contains("second") || ["2nd", "2", "ii"].contains(cleaned) {
            return NormalizedMorph(key: "second", label: "Second", order: 1)
        }

        if cleaned.contains("third") || ["3rd", "3", "iii"].contains(cleaned) {
            return NormalizedMorph(key: "third", label: "Third", order: 2)
        }

        return nil
    }

    static func normalizeTense(_ value: String?) -> NormalizedMorph? {
        guard let cleaned = cleanedValue(from: value) else { return nil }
        let compact = cleaned.replacingOccurrences(of: " ", with: "")

        let mappings: [(Set<String>, String, Int)] = [
            (["present", "pres"], "Present", 0),
            (["imperfect", "impf"], "Imperfect", 1),
            (["future", "fut"], "Future", 2),
            (["aorist", "aor"], "Aorist", 3),
            (["perfect", "perf"], "Perfect", 4),
            (["pluperfect", "plup", "pluperf"], "Pluperfect", 5),
            (["futureperfect", "futperf"], "Future Perfect", 6)
        ]

        for (keys, label, order) in mappings {
            if keys.contains(compact) {
                return NormalizedMorph(key: label.lowercased(), label: label, order: order)
            }
        }

        return NormalizedMorph(key: compact, label: cleaned.displayTitle(defaultTitle: cleaned), order: Int.max)
    }

    private static func cleanedValue(from raw: String?) -> String? {
        guard let raw = raw?
            .trimmingCharacters(in: .whitespacesAndNewlines),
              !raw.isEmpty else { return nil }

        let simplified = raw
            .replacingOccurrences(of: ".", with: "")
            .replacingOccurrences(of: "person", with: "")
            .replacingOccurrences(of: "pers", with: "")
            .replacingOccurrences(of: "number", with: "")
            .replacingOccurrences(of: "tense", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        return simplified.isEmpty ? nil : simplified
    }
}


private struct VerbEntry: Identifiable {
    let id: Int64
    let display: String
    let placeholder: String
    let voiceLabel: String?
    let personLabel: String?
    let numberLabel: String?
    let tenseLabel: String?
    let moodLabel: String?
    let personOrder: Int?
    let numberOrder: Int?
    let tenseOrder: Int?
    let answer: String

    init(form: VerbForm) {
        id = form.id
        display = form.form
        answer = form.form

        let normalizedPerson = MorphologyNormalizer.normalizePerson(form.person)
        let normalizedNumber = MorphologyNormalizer.normalizeNumber(form.number)
        let normalizedTense = MorphologyNormalizer.normalizeTense(form.tense)

        if let voice = form.voice, !voice.isEmpty {
            voiceLabel = voice.displayTitle(defaultTitle: voice)
        } else {
            voiceLabel = nil
        }

        if let normalizedPerson {
            personLabel = normalizedPerson.label
            personOrder = normalizedPerson.order
        } else if let person = form.person, !person.isEmpty {
            personLabel = person.displayTitle(defaultTitle: person)
            personOrder = nil
        } else {
            personLabel = nil
            personOrder = nil
        }

        if let normalizedNumber {
            numberLabel = normalizedNumber.label
            numberOrder = normalizedNumber.order
        } else if let number = form.number, !number.isEmpty {
            numberLabel = number.displayTitle(defaultTitle: number)
            numberOrder = nil
        } else {
            numberLabel = nil
            numberOrder = nil
        }

        if let normalizedTense {
            tenseLabel = normalizedTense.label
            tenseOrder = normalizedTense.order
        } else if let tense = form.tense, !tense.isEmpty {
            tenseLabel = tense.displayTitle(defaultTitle: tense)
            tenseOrder = nil
        } else {
            tenseLabel = nil
            tenseOrder = nil
        }

        if let mood = form.mood, !mood.isEmpty {
            moodLabel = mood.displayTitle(defaultTitle: mood)
        } else {
            moodLabel = nil
        }

        let contextParts = [personLabel, numberLabel, tenseLabel].compactMap { $0 }
        if contextParts.isEmpty {
            placeholder = "Enter form"
        } else {
            placeholder = contextParts.joined(separator: " • ")
        }
    }

    static func buildOthers(from forms: [VerbForm], excluding coveredIDs: Set<Int64>) -> [VerbEntry] {
        forms
            .filter { form in
                !coveredIDs.contains(form.id)
            }
            .map { VerbEntry(form: $0) }
            .sorted { lhs, rhs in
                if lhs.personOrder != rhs.personOrder {
                    return (lhs.personOrder ?? Int.max) < (rhs.personOrder ?? Int.max)
                }
                if lhs.numberOrder != rhs.numberOrder {
                    return (lhs.numberOrder ?? Int.max) < (rhs.numberOrder ?? Int.max)
                }
                if lhs.tenseOrder != rhs.tenseOrder {
                    return (lhs.tenseOrder ?? Int.max) < (rhs.tenseOrder ?? Int.max)
                }
                return lhs.id < rhs.id
            }
    }
}

// MARK: - Shared Helpers

private struct EmptyFormsPlaceholder: View {
    let message: String

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "text.book.closed")
                .font(.largeTitle)
                .foregroundColor(.secondary)
            Text(message)
                .font(.body)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .padding()
    }
}

private let dialectOrder = ["attic", "doric", "ionic", "aeolic", "epic", "koine", "byzantine", "unspecified"]

private extension Array where Element == String {
    func index(of key: String) -> Int {
        firstIndex(of: key) ?? count
    }
}
