import SwiftUI

struct VocabQuizSetupView: View {
    @StateObject private var viewModel = VocabQuizSetupViewModel()

    @State private var selectedLists: Set<String> = []
    @State private var includeFavorites = false
    @State private var selectedStatuses: Set<LearningStatus> = []
    @State private var questionCount = 20
    @State private var direction: QuizDirection = .l1ToL2
    @State private var answerType: QuizAnswerType = .textEntry
    @State private var startQuiz = false
    @State private var showListPicker = false

    var body: some View {
        Form {
            Section("Sources") {
                Toggle("Include favorites", isOn: $includeFavorites)

                Button {
                    showListPicker = true
                } label: {
                    HStack {
                        Text("Lists")
                        Spacer()
                        if selectedLists.isEmpty {
                            Text("None")
                                .foregroundColor(.secondary)
                        } else {
                            Text("\(selectedLists.count) selected")
                                .foregroundColor(.secondary)
                        }
                        Image(systemName: "chevron.right")
                            .foregroundColor(.secondary)
                    }
                }

                ForEach(LearningStatus.allCases) { status in
                    Toggle(status.label, isOn: binding(for: status, in: $selectedStatuses))
                }
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

            Section("Direction") {
                Picker("Direction", selection: $direction) {
                    ForEach(QuizDirection.allCases) { mode in
                        Text(mode.label).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
            }

            Section("Answer Type") {
                Picker("Answer Type", selection: $answerType) {
                    ForEach(QuizAnswerType.allCases) { mode in
                        Text(mode.label).tag(mode)
                    }
                }
            }

            Section {
                Button("Start Quiz") {
                    startQuiz = true
                }
                .disabled(viewModel.availableCount == 0)
            }
        }
        .navigationTitle("Vocab Quiz")
        .navigationBarTitleDisplayMode(.inline)
        .background(
            NavigationLink(
                destination: VocabQuizSessionView(config: config),
                isActive: $startQuiz,
                label: { EmptyView() }
            )
        )
        .sheet(isPresented: $showListPicker) {
            QuizListPickerView(
                title: "Choose Lists",
                lists: viewModel.lists,
                selection: $selectedLists
            )
        }
        .onAppear {
            viewModel.load()
            refreshCount()
        }
        .onChange(of: selectionToken) { _ in
            refreshCount()
        }
    }

    private var config: VocabQuizConfig {
        VocabQuizConfig(
            listTitles: Array(selectedLists),
            includeFavorites: includeFavorites,
            learningStatuses: Array(selectedStatuses),
            questionCount: questionCount,
            direction: direction,
            answerType: answerType
        )
    }

    private var selectionToken: String {
        let listKey = selectedLists.sorted().joined(separator: "|")
        let statusKey = selectedStatuses.map(\.rawValue).sorted().map(String.init).joined(separator: "|")
        return "\(listKey)-\(statusKey)-\(includeFavorites)-\(questionCount)-\(direction.rawValue)-\(answerType.rawValue)"
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
}

struct VocabQuizSessionView: View {
    @StateObject private var viewModel: VocabQuizSessionViewModel
    @State private var textAnswer = ""
    @State private var revealFlashCard = false

    init(config: VocabQuizConfig) {
        _viewModel = StateObject(wrappedValue: VocabQuizSessionViewModel(config: config))
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
                VocabQuizReportView(questions: viewModel.questions, responses: viewModel.responses)
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
    private func questionCard(_ question: VocabQuizQuestion) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(question.prompt)
                .font(.title3.weight(.semibold))

            switch viewModel.config.answerType {
            case .textEntry:
                textEntrySection(question)
            case .multipleChoice:
                multipleChoiceSection(question)
            case .flashCard:
                flashCardSection(question)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(.secondarySystemBackground))
        )
    }

    private func textEntrySection(_ question: VocabQuizQuestion) -> some View {
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

    private func multipleChoiceSection(_ question: VocabQuizQuestion) -> some View {
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

    private func flashCardSection(_ question: VocabQuizQuestion) -> some View {
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

    private func feedbackView(response: VocabQuizResponse, correctAnswer: String) -> some View {
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

struct VocabQuizReportView: View {
    let questions: [VocabQuizQuestion]
    let responses: [UUID: VocabQuizResponse]

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
                        Text("Answer: \(question.correctAnswer)")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        if let response {
                            Text("Your response: \(response.userAnswer)")
                                .font(.footnote)
                                .foregroundColor(response.isCorrect ? .green : .orange)
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

#Preview {
    NavigationStack {
        VocabQuizSetupView()
    }
}
