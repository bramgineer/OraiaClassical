import SwiftUI

struct VerbConjugationQuizSetupView: View {
    @StateObject private var viewModel = VerbQuizSetupViewModel()

    @State private var selectedLists: Set<String> = []
    @State private var includeFavorites = false
    @State private var selectedStatuses: Set<LearningStatus> = []

    @State private var selectedTenses: Set<String> = Set(VerbQuizOptions.tenseOptions.map(\.value))
    @State private var selectedMoods: Set<String> = Set(VerbQuizOptions.moodOptions.map(\.value))
    @State private var selectedVoices: Set<String> = Set(VerbQuizOptions.voiceOptions.map(\.value))
    @State private var selectedPersons: Set<String> = Set(VerbQuizOptions.personOptions.map(\.value))
    @State private var selectedNumbers: Set<String> = Set(VerbQuizOptions.numberOptions.map(\.value))

    @State private var includeOtherTense = true
    @State private var includeOtherMood = true
    @State private var includeOtherVoice = true
    @State private var includeOtherPerson = true
    @State private var includeOtherNumber = true

    @State private var questionCount = 20
    @State private var mode: VerbQuizMode = .conjugation
    @State private var answerType: QuizAnswerType = .textEntry
    @State private var startQuiz = false

    var body: some View {
        Form {
            Section("Sources") {
                Toggle("Include favorites", isOn: $includeFavorites)

                if viewModel.lists.isEmpty {
                    Text("No lists available.")
                        .foregroundColor(.secondary)
                } else {
                    ForEach(viewModel.lists) { list in
                        Toggle(list.title, isOn: binding(for: list.title, in: $selectedLists))
                    }
                }

                ForEach(LearningStatus.allCases) { status in
                    Toggle(status.label, isOn: binding(for: status, in: $selectedStatuses))
                }
            }

            Section("Verb Forms") {
                optionGroup(title: "Tense", options: VerbQuizOptions.tenseOptions, selection: $selectedTenses)
                Toggle("Other / Unspecified", isOn: $includeOtherTense)
            }

            Section("Mood / Form Type") {
                optionGroup(title: "Mood", options: VerbQuizOptions.moodOptions, selection: $selectedMoods)
                Toggle("Other / Unspecified", isOn: $includeOtherMood)
            }

            Section("Voice") {
                optionGroup(title: "Voice", options: VerbQuizOptions.voiceOptions, selection: $selectedVoices)
                Toggle("Other / Unspecified", isOn: $includeOtherVoice)
            }

            Section("Person") {
                optionGroup(title: "Person", options: VerbQuizOptions.personOptions, selection: $selectedPersons)
                Toggle("Other / Unspecified", isOn: $includeOtherPerson)
            }

            Section("Number") {
                optionGroup(title: "Number", options: VerbQuizOptions.numberOptions, selection: $selectedNumbers)
                Toggle("Other / Unspecified", isOn: $includeOtherNumber)
            }

            Section("Quiz Size") {
                Stepper(value: $questionCount, in: 1...1000) {
                    Text("Questions: \(questionCount)")
                }
                Text("Available: \(viewModel.availableCount)")
                    .font(.footnote)
                    .foregroundColor(.secondary)
                if viewModel.availableCount > 0 {
                    Text("Quiz will be \(min(questionCount, viewModel.availableCount)) questions.")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                }
            }

            Section("Mode") {
                Picker("Mode", selection: $mode) {
                    ForEach(VerbQuizMode.allCases) { mode in
                        Text(mode.label).tag(mode)
                    }
                }
            }

            Section("Answer Type") {
                Picker("Answer Type", selection: $answerType) {
                    ForEach(QuizAnswerType.allCases) { type in
                        Text(type.label).tag(type)
                    }
                }
                .disabled(mode == .principalParts)

                if mode == .principalParts {
                    Text("Principal parts are text entry only.")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                }
            }

            Section {
                Button("Start Quiz") {
                    startQuiz = true
                }
                .disabled(!hasSources || viewModel.availableCount == 0)
            }
        }
        .navigationTitle("Verb Quiz")
        .navigationBarTitleDisplayMode(.inline)
        .background(
            NavigationLink(
                destination: VerbConjugationQuizSessionView(config: config),
                isActive: $startQuiz,
                label: { EmptyView() }
            )
        )
        .onAppear {
            viewModel.load()
            refreshCount()
        }
        .onChange(of: selectionToken) { _ in
            refreshCount()
        }
    }

    private var hasSources: Bool {
        !selectedLists.isEmpty || includeFavorites
    }

    private var config: VerbQuizConfig {
        VerbQuizConfig(
            listTitles: Array(selectedLists),
            includeFavorites: includeFavorites,
            learningStatuses: Array(selectedStatuses),
            questionCount: questionCount,
            mode: mode,
            answerType: mode == .principalParts ? .textEntry : answerType,
            tenses: selectedTenses.map { $0.lowercased() },
            moods: selectedMoods.map { $0.lowercased() },
            voices: selectedVoices.map { $0.lowercased() },
            persons: selectedPersons.map { $0.lowercased() },
            numbers: selectedNumbers.map { $0.lowercased() },
            includeOtherTense: includeOtherTense,
            includeOtherMood: includeOtherMood,
            includeOtherVoice: includeOtherVoice,
            includeOtherPerson: includeOtherPerson,
            includeOtherNumber: includeOtherNumber
        )
    }

    private var selectionToken: String {
        [
            selectedLists.sorted().joined(separator: "|"),
            includeFavorites.description,
            selectedStatuses.map(\.rawValue).sorted().map(String.init).joined(separator: "|"),
            selectedTenses.sorted().joined(separator: "|"),
            selectedMoods.sorted().joined(separator: "|"),
            selectedVoices.sorted().joined(separator: "|"),
            selectedPersons.sorted().joined(separator: "|"),
            selectedNumbers.sorted().joined(separator: "|"),
            includeOtherTense.description,
            includeOtherMood.description,
            includeOtherVoice.description,
            includeOtherPerson.description,
            includeOtherNumber.description,
            "\(questionCount)",
            mode.rawValue,
            answerType.rawValue
        ].joined(separator: "~")
    }

    private func refreshCount() {
        viewModel.refreshAvailableCount(config: config)
    }

    private func binding<T: Hashable>(for value: T, in set: Binding<Set<T>>) -> Binding<Bool> {
        Binding(
            get: { set.wrappedValue.contains(value) },
            set: { isOn in
                if isOn {
                    set.wrappedValue.insert(value)
                } else {
                    set.wrappedValue.remove(value)
                }
            }
        )
    }

    private func optionGroup(title: String, options: [VerbQuizOption], selection: Binding<Set<String>>) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.subheadline.weight(.semibold))
            ForEach(options) { option in
                Toggle(option.label, isOn: binding(for: option.value, in: selection))
            }
        }
    }
}

struct VerbConjugationQuizSessionView: View {
    @StateObject private var viewModel: VerbQuizSessionViewModel
    @State private var textAnswer = ""
    @State private var revealFlashCard = false
    @State private var principalParts: [String] = Array(repeating: "", count: 6)

    init(config: VerbQuizConfig) {
        _viewModel = StateObject(wrappedValue: VerbQuizSessionViewModel(config: config))
    }

    var body: some View {
        VStack(spacing: 16) {
            if viewModel.isLoading {
                ProgressView()
                    .padding(.top, 40)
            } else if let errorMessage = viewModel.errorMessage {
                Text(errorMessage)
                    .foregroundColor(.secondary)
                    .padding(.top, 40)
            } else if viewModel.isComplete {
                VerbConjugationQuizReportView(questions: viewModel.questions, responses: viewModel.responses)
            } else {
                quizHeader
                if let question = viewModel.currentQuestion {
                    questionCard(question)
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 16)
        .onAppear {
            viewModel.load()
        }
    }

    private var quizHeader: some View {
        HStack {
            Text("Question \(min(viewModel.currentIndex + 1, viewModel.questions.count)) of \(viewModel.questions.count)")
                .font(.subheadline)
                .foregroundColor(.secondary)
            Spacer()
        }
    }

    @ViewBuilder
    private func questionCard(_ question: VerbQuizQuestion) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(question.prompt)
                .font(.title3.weight(.semibold))

            switch question.mode {
            case .principalParts:
                principalPartsSection(question)
            case .conjugation, .transform:
                switch viewModel.config.answerType {
                case .textEntry:
                    textEntrySection(question)
                case .multipleChoice:
                    multipleChoiceSection(question)
                case .flashCard:
                    flashCardSection(question)
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(.secondarySystemBackground))
        )
    }

    private func textEntrySection(_ question: VerbQuizQuestion) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            TextField("Enter answer", text: $textAnswer)
                .textInputAutocapitalization(.never)
                .disableAutocorrection(true)
                .padding(.vertical, 10)
                .padding(.horizontal, 12)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color(.systemBackground))
                )

            if viewModel.showFeedback, let response = viewModel.lastResponse {
                feedbackView(response: response, correctAnswer: question.correctAnswer)
            }

            Button(viewModel.showFeedback ? "Next" : "Submit") {
                if viewModel.showFeedback {
                    textAnswer = ""
                    viewModel.advance()
                } else {
                    viewModel.submitTextAnswer(textAnswer)
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(textAnswer.trimmed().isEmpty && !viewModel.showFeedback)
        }
    }

    private func multipleChoiceSection(_ question: VerbQuizQuestion) -> some View {
        VStack(spacing: 10) {
            ForEach(question.options, id: \.self) { option in
                Button {
                    if !viewModel.showFeedback {
                        viewModel.selectOption(option)
                    }
                } label: {
                    HStack {
                        Text(option)
                            .foregroundColor(.primary)
                        Spacer()
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color(.systemBackground))
                    )
                }
                .buttonStyle(.plain)
            }

            if viewModel.showFeedback, let response = viewModel.lastResponse {
                feedbackView(response: response, correctAnswer: question.correctAnswer)
                Button("Next") {
                    viewModel.advance()
                }
                .buttonStyle(.borderedProminent)
            }
        }
    }

    private func flashCardSection(_ question: VerbQuizQuestion) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            if revealFlashCard {
                Text(question.correctAnswer)
                    .font(.title2.weight(.semibold))
            } else {
                Text("Tap reveal to show the answer.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }

            if viewModel.showFeedback, let response = viewModel.lastResponse {
                feedbackView(response: response, correctAnswer: question.correctAnswer)
                Button("Next") {
                    revealFlashCard = false
                    viewModel.advance()
                }
                .buttonStyle(.borderedProminent)
            } else {
                if !revealFlashCard {
                    Button("Reveal") {
                        revealFlashCard = true
                    }
                    .buttonStyle(.bordered)
                } else {
                    HStack(spacing: 12) {
                        Button("I knew it") {
                            viewModel.markFlashCard(known: true)
                        }
                        .buttonStyle(.borderedProminent)

                        Button("I missed it") {
                            viewModel.markFlashCard(known: false)
                        }
                        .buttonStyle(.bordered)
                    }
                }
            }
        }
    }

    private func principalPartsSection(_ question: VerbQuizQuestion) -> some View {
        let labels = VerbQuizOptions.principalPartLabels
        return VStack(alignment: .leading, spacing: 10) {
            ForEach(labels.indices, id: \.self) { index in
                TextField(labels[index], text: Binding(
                    get: { principalParts[index] },
                    set: { principalParts[index] = $0 }
                ))
                .textInputAutocapitalization(.never)
                .disableAutocorrection(true)
                .padding(.vertical, 8)
                .padding(.horizontal, 12)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color(.systemBackground))
                )
            }

            if viewModel.showFeedback, let response = viewModel.lastResponse {
                feedbackView(response: response, correctAnswer: question.principalParts?.forms.joined(separator: " • ") ?? "")
            }

            Button(viewModel.showFeedback ? "Next" : "Submit") {
                if viewModel.showFeedback {
                    principalParts = Array(repeating: "", count: 6)
                    viewModel.advance()
                } else {
                    viewModel.submitPrincipalParts(principalParts)
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(principalParts.allSatisfy { $0.trimmed().isEmpty } && !viewModel.showFeedback)
        }
    }

    private func feedbackView(response: VerbQuizResponse, correctAnswer: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(response.isCorrect ? "Correct" : "Incorrect")
                .font(.headline)
                .foregroundColor(response.isCorrect ? .green : .orange)
            if !response.isCorrect {
                Text("Answer: \(correctAnswer)")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
        }
    }
}

struct VerbConjugationQuizReportView: View {
    let questions: [VerbQuizQuestion]
    let responses: [UUID: VerbQuizResponse]

    private var score: (correct: Int, total: Int) {
        let correct = responses.values.filter { $0.isCorrect }.count
        return (correct, questions.count)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Quiz Report")
                        .font(.title2.weight(.semibold))
                    Text("\(score.correct) / \(score.total) correct")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }

                ForEach(questions) { question in
                    let response = responses[question.id]
                    VStack(alignment: .leading, spacing: 6) {
                        Text(question.prompt)
                            .font(.headline)
                        if let parts = question.principalParts?.forms {
                            Text("Answer: \(parts.joined(separator: " • "))")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        } else {
                            Text("Answer: \(question.correctAnswer)")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                        if let response {
                            if let userParts = response.userParts {
                                Text("Your response: \(userParts.joined(separator: " • "))")
                                    .font(.footnote)
                                    .foregroundColor(response.isCorrect ? .green : .orange)
                            } else {
                                Text("Your response: \(response.userAnswer)")
                                    .font(.footnote)
                                    .foregroundColor(response.isCorrect ? .green : .orange)
                            }
                        }
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color(.secondarySystemBackground))
                    )
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 24)
        }
    }
}

private struct VerbQuizOption: Identifiable {
    let id: String
    let value: String
    let label: String
}

private enum VerbQuizOptions {
    static let tenseOptions: [VerbQuizOption] = [
        .init(id: "present", value: "present", label: "Present"),
        .init(id: "imperfect", value: "imperfect", label: "Imperfect"),
        .init(id: "future", value: "future", label: "Future"),
        .init(id: "aorist", value: "aorist", label: "Aorist"),
        .init(id: "perfect", value: "perfect", label: "Perfect"),
        .init(id: "pluperfect", value: "pluperfect", label: "Pluperfect"),
        .init(id: "future-perfect", value: "future-perfect", label: "Future Perfect")
    ]

    static let moodOptions: [VerbQuizOption] = [
        .init(id: "indicative", value: "indicative", label: "Indicative"),
        .init(id: "subjunctive", value: "subjunctive", label: "Subjunctive"),
        .init(id: "optative", value: "optative", label: "Optative"),
        .init(id: "imperative", value: "imperative", label: "Imperative"),
        .init(id: "infinitive", value: "infinitive", label: "Infinitive"),
        .init(id: "participle", value: "participle", label: "Participle")
    ]

    static let voiceOptions: [VerbQuizOption] = [
        .init(id: "active", value: "active", label: "Active"),
        .init(id: "middle", value: "middle", label: "Middle"),
        .init(id: "passive", value: "passive", label: "Passive"),
        .init(id: "middle-passive", value: "middle-passive", label: "Middle/Passive")
    ]

    static let personOptions: [VerbQuizOption] = [
        .init(id: "first-person", value: "first-person", label: "First"),
        .init(id: "second-person", value: "second-person", label: "Second"),
        .init(id: "third-person", value: "third-person", label: "Third")
    ]

    static let numberOptions: [VerbQuizOption] = [
        .init(id: "singular", value: "singular", label: "Singular"),
        .init(id: "dual", value: "dual", label: "Dual"),
        .init(id: "plural", value: "plural", label: "Plural")
    ]

    static let principalPartLabels: [String] = [
        "Present Active (1st sg)",
        "Future Active (1st sg)",
        "Aorist Active (1st sg)",
        "Perfect Active (1st sg)",
        "Perfect Middle/Passive (1st sg)",
        "Aorist Passive (1st sg)"
    ]
}

#Preview {
    NavigationStack {
        VerbConjugationQuizSetupView()
    }
}
