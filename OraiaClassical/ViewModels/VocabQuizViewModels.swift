import Foundation

@MainActor
final class VocabQuizSetupViewModel: ObservableObject {
    @Published var lists: [VocabularyList] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var availableCount: Int = 0

    func load() {
        isLoading = true
        errorMessage = nil
        Task {
            do {
                let lists = try await SQLiteStore.shared.fetchVocabularyLists()
                self.lists = lists
                self.isLoading = false
            } catch {
                self.errorMessage = error.localizedDescription
                self.isLoading = false
            }
        }
    }

    func refreshAvailableCount(config: VocabQuizConfig) {
        Task {
            do {
                let items = try await SQLiteStore.shared.fetchVocabQuizItems(
                    listTitles: config.listTitles,
                    includeFavorites: config.includeFavorites,
                    learningStatuses: config.learningStatuses
                )
                self.availableCount = items.count
            } catch {
                self.availableCount = 0
                self.errorMessage = error.localizedDescription
            }
        }
    }
}

@MainActor
final class VocabQuizSessionViewModel: ObservableObject {
    @Published var questions: [VocabQuizQuestion] = []
    @Published var currentIndex: Int = 0
    @Published var responses: [UUID: VocabQuizResponse] = [:]
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var showFeedback = false
    @Published var lastResponse: VocabQuizResponse?

    let config: VocabQuizConfig

    init(config: VocabQuizConfig) {
        self.config = config
    }

    var isComplete: Bool {
        currentIndex >= questions.count && !questions.isEmpty
    }

    var currentQuestion: VocabQuizQuestion? {
        guard currentIndex < questions.count else { return nil }
        return questions[currentIndex]
    }

    func load() {
        isLoading = true
        errorMessage = nil
        Task {
            do {
                let items = try await SQLiteStore.shared.fetchVocabQuizItems(
                    listTitles: config.listTitles,
                    includeFavorites: config.includeFavorites,
                    learningStatuses: config.learningStatuses
                )
                let unique = Dictionary(grouping: items, by: \.id).compactMap { $0.value.first }
                let shuffled = unique.shuffled()
                let count = min(config.questionCount, shuffled.count)
                let selected = Array(shuffled.prefix(count))
                self.questions = buildQuestions(from: selected)
                self.currentIndex = 0
                self.responses = [:]
                self.isLoading = false
            } catch {
                self.errorMessage = error.localizedDescription
                self.isLoading = false
            }
        }
    }

    func submitTextAnswer(_ answer: String) {
        guard let question = currentQuestion else { return }
        let isCorrect = answer.trimmed().equalsMorph(question.correctAnswer)
        recordResponse(questionID: question.id, answer: answer, isCorrect: isCorrect)
    }

    func selectOption(_ option: String) {
        guard let question = currentQuestion else { return }
        let isCorrect = option.equalsMorph(question.correctAnswer)
        recordResponse(questionID: question.id, answer: option, isCorrect: isCorrect)
    }

    func markFlashCard(known: Bool) {
        guard let question = currentQuestion else { return }
        let answer = known ? "✓" : "✗"
        recordResponse(questionID: question.id, answer: answer, isCorrect: known)
    }

    func advance() {
        showFeedback = false
        lastResponse = nil
        currentIndex += 1
    }

    private func recordResponse(questionID: UUID, answer: String, isCorrect: Bool) {
        let response = VocabQuizResponse(id: UUID(), questionID: questionID, userAnswer: answer, isCorrect: isCorrect)
        responses[questionID] = response
        lastResponse = response
        showFeedback = true
    }

    private func buildQuestions(from items: [VocabQuizItem]) -> [VocabQuizQuestion] {
        let answerPool: [String]
        switch config.direction {
        case .l1ToL2:
            answerPool = Array(Set(items.map(\.headword))).sorted()
        case .l2ToL1:
            answerPool = Array(Set(items.map(\.gloss))).sorted()
        }

        return items.map { item in
            let prompt: String
            let answer: String
            switch config.direction {
            case .l1ToL2:
                prompt = item.gloss
                answer = item.headword
            case .l2ToL1:
                prompt = item.headword
                answer = item.gloss
            }

            let options: [String]
            if config.answerType == .multipleChoice {
                options = buildOptions(correct: answer, pool: answerPool)
            } else {
                options = []
            }

            return VocabQuizQuestion(id: UUID(), prompt: prompt, correctAnswer: answer, options: options)
        }
    }

    private func buildOptions(correct: String, pool: [String]) -> [String] {
        let uniquePool = Array(Set(pool.filter { !$0.isEmpty }))
        let targetCount = min(4, uniquePool.count)
        guard targetCount > 0 else { return [correct] }

        var choices: [String] = [correct]
        var candidates = uniquePool.filter { !$0.equalsMorph(correct) }.shuffled()
        while choices.count < targetCount, let next = candidates.first {
            choices.append(next)
            candidates.removeFirst()
        }
        return choices.shuffled()
    }
}
