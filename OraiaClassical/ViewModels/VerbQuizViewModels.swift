import Foundation

@MainActor
final class VerbQuizSetupViewModel: ObservableObject {
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

    func refreshAvailableCount(config: VerbQuizConfig) {
        Task {
            do {
                let forms = try await SQLiteStore.shared.fetchVerbQuizForms(
                    listTitles: config.listTitles,
                    includeFavorites: config.includeFavorites,
                    learningStatuses: config.learningStatuses
                )
                let filtered = filterForms(forms, config: config)
                switch config.mode {
                case .conjugation:
                    availableCount = filtered.count
                case .transform:
                    let grouped = Dictionary(grouping: filtered, by: \.lemmaID)
                    let count = grouped.values.reduce(0) { total, forms in
                        forms.count > 1 ? total + forms.count : total
                    }
                    availableCount = count
                case .principalParts:
                    let grouped = Dictionary(grouping: filtered, by: \.lemmaID)
                    let partsCount = grouped.values.compactMap { inferPrincipalParts(from: $0) }.count
                    availableCount = partsCount
                }
            } catch {
                availableCount = 0
                errorMessage = error.localizedDescription
            }
        }
    }
}

@MainActor
final class VerbQuizSessionViewModel: ObservableObject {
    @Published var questions: [VerbQuizQuestion] = []
    @Published var currentIndex: Int = 0
    @Published var responses: [UUID: VerbQuizResponse] = [:]
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var showFeedback = false
    @Published var lastResponse: VerbQuizResponse?

    let config: VerbQuizConfig

    init(config: VerbQuizConfig) {
        self.config = config
    }

    var currentQuestion: VerbQuizQuestion? {
        guard currentIndex < questions.count else { return nil }
        return questions[currentIndex]
    }

    var isComplete: Bool {
        currentIndex >= questions.count && !questions.isEmpty
    }

    func load() {
        isLoading = true
        errorMessage = nil
        Task {
            do {
                let forms = try await SQLiteStore.shared.fetchVerbQuizForms(
                    listTitles: config.listTitles,
                    includeFavorites: config.includeFavorites,
                    learningStatuses: config.learningStatuses
                )
                let filtered = filterForms(forms, config: config)
                let questions = buildQuestions(from: filtered)
                let shuffled = questions.shuffled()
                let count = min(config.questionCount, shuffled.count)
                self.questions = Array(shuffled.prefix(count))
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
        recordResponse(questionID: question.id, userAnswer: answer, isCorrect: isCorrect, parts: nil)
    }

    func selectOption(_ option: String) {
        guard let question = currentQuestion else { return }
        let isCorrect = option.equalsMorph(question.correctAnswer)
        recordResponse(questionID: question.id, userAnswer: option, isCorrect: isCorrect, parts: nil)
    }

    func markFlashCard(known: Bool) {
        guard let question = currentQuestion else { return }
        let answer = known ? "✓" : "✗"
        recordResponse(questionID: question.id, userAnswer: answer, isCorrect: known, parts: nil)
    }

    func submitPrincipalParts(_ parts: [String]) {
        guard let question = currentQuestion, let principalParts = question.principalParts else { return }
        let trimmedParts = parts.map { $0.trimmed() }
        let expected = principalParts.forms.map { $0.trimmed() }
        let isCorrect = trimmedParts == expected
        recordResponse(questionID: question.id, userAnswer: trimmedParts.joined(separator: " | "), isCorrect: isCorrect, parts: trimmedParts)
    }

    func advance() {
        showFeedback = false
        lastResponse = nil
        currentIndex += 1
    }

    private func recordResponse(questionID: UUID, userAnswer: String, isCorrect: Bool, parts: [String]?) {
        let response = VerbQuizResponse(id: UUID(), questionID: questionID, userAnswer: userAnswer, isCorrect: isCorrect, userParts: parts)
        responses[questionID] = response
        lastResponse = response
        showFeedback = true
    }

    private func buildQuestions(from forms: [VerbQuizForm]) -> [VerbQuizQuestion] {
        let groupedByLemma = Dictionary(grouping: forms, by: \.lemmaID)
        switch config.mode {
        case .conjugation:
            return forms.map { form in
                let label = formDescriptor(form)
                let options = config.answerType == .multipleChoice
                    ? buildOptions(for: form, formsByLemma: groupedByLemma)
                    : []
                return VerbQuizQuestion(
                    id: UUID(),
                    mode: .conjugation,
                    lemmaID: form.lemmaID,
                    headword: form.headword,
                    prompt: "\(form.headword) — \(label)",
                    correctAnswer: form.form,
                    options: options,
                    sourceForm: nil,
                    targetLabel: label,
                    principalParts: nil
                )
            }
        case .transform:
            var questions: [VerbQuizQuestion] = []
            for (lemmaID, lemmaForms) in groupedByLemma {
                guard lemmaForms.count > 1 else { continue }
                for target in lemmaForms {
                    let sourceCandidates = lemmaForms.filter { $0.id != target.id }
                    guard let source = sourceCandidates.randomElement() else { continue }
                    let targetLabel = formDescriptor(target)
                    let sourceLabel = formDescriptor(source)
                    let options = config.answerType == .multipleChoice
                        ? buildOptions(for: target, formsByLemma: groupedByLemma)
                        : []
                    questions.append(
                        VerbQuizQuestion(
                            id: UUID(),
                            mode: .transform,
                            lemmaID: lemmaID,
                            headword: target.headword,
                            prompt: "\(target.headword) — change \(source.form) (\(sourceLabel)) → \(targetLabel)",
                            correctAnswer: target.form,
                            options: options,
                            sourceForm: source.form,
                            targetLabel: targetLabel,
                            principalParts: nil
                        )
                    )
                }
            }
            return questions
        case .principalParts:
            var questions: [VerbQuizQuestion] = []
            for (lemmaID, lemmaForms) in groupedByLemma {
                guard let parts = inferPrincipalParts(from: lemmaForms) else { continue }
                questions.append(
                    VerbQuizQuestion(
                        id: UUID(),
                        mode: .principalParts,
                        lemmaID: lemmaID,
                        headword: lemmaForms.first?.headword ?? "",
                        prompt: "\(lemmaForms.first?.headword ?? "") — enter principal parts",
                        correctAnswer: "",
                        options: [],
                        sourceForm: nil,
                        targetLabel: nil,
                        principalParts: parts
                    )
                )
            }
            return questions
        }
    }

    private func buildOptions(for form: VerbQuizForm, formsByLemma: [Int64: [VerbQuizForm]]) -> [String] {
        guard let lemmaForms = formsByLemma[form.lemmaID] else { return [form.form] }
        let targetMood = effectiveMood(form)
        let matches = lemmaForms.filter { candidate in
            candidate.tense?.lowercased() == form.tense?.lowercased()
                && candidate.voice?.lowercased() == form.voice?.lowercased()
                && effectiveMood(candidate) == targetMood
        }
        let pool = Array(Set(matches.map(\.form))).filter { !$0.isEmpty }
        let correct = form.form
        let uniquePool = Array(Set(pool))
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

private func filterForms(_ forms: [VerbQuizForm], config: VerbQuizConfig) -> [VerbQuizForm] {
    forms.filter { form in
        matchesCategory(value: form.tense, allowed: config.tenses, includeOther: config.includeOtherTense)
            && matchesCategory(value: effectiveMood(form), allowed: config.moods, includeOther: config.includeOtherMood)
            && matchesCategory(value: form.voice, allowed: config.voices, includeOther: config.includeOtherVoice)
            && matchesCategory(value: form.person, allowed: config.persons, includeOther: config.includeOtherPerson)
            && matchesCategory(value: form.number, allowed: config.numbers, includeOther: config.includeOtherNumber)
    }
}

private func matchesCategory(value: String?, allowed: [String], includeOther: Bool) -> Bool {
    let trimmed = (value ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    if trimmed.isEmpty {
        return includeOther
    }
    return allowed.contains(trimmed.lowercased())
}

private func effectiveMood(_ form: VerbQuizForm) -> String? {
    let mood = form.mood?.trimmingCharacters(in: .whitespacesAndNewlines)
    if let mood_toggle = mood, !mood_toggle.isEmpty {
        return mood_toggle.lowercased()
    }
    let formType = form.verbFormType?.trimmingCharacters(in: .whitespacesAndNewlines)
    if let formType, !formType.isEmpty {
        return formType.lowercased()
    }
    return nil
}

private func formDescriptor(_ form: VerbQuizForm) -> String {
    var parts: [String] = []
    if let tense = form.tense, !tense.isEmpty { parts.append(label(for: tense)) }
    if let mood = effectiveMood(form), !mood.isEmpty { parts.append(label(for: mood)) }
    if let voice = form.voice, !voice.isEmpty { parts.append(label(for: voice)) }
    if let person = form.person, !person.isEmpty { parts.append(label(for: person)) }
    if let number = form.number, !number.isEmpty { parts.append(label(for: number)) }
    return parts.isEmpty ? "Unspecified" : parts.joined(separator: " • ")
}

private func label(for raw: String) -> String {
    raw.displayTitle(defaultTitle: raw)
        .replacingOccurrences(of: "person", with: "")
        .replacingOccurrences(of: "-", with: " ")
        .trimmingCharacters(in: .whitespacesAndNewlines)
}

private func inferPrincipalParts(from forms: [VerbQuizForm]) -> VerbPrincipalParts? {
    let sorted = forms.sorted { $0.id < $1.id }

    func pick(tense: String, voiceCandidates: [String], mood: String = "indicative") -> String? {
        for form in sorted {
            guard form.tense?.lowercased() == tense else { continue }
            guard effectiveMood(form) == mood else { continue }
            guard form.person?.lowercased() == "first-person" else { continue }
            guard form.number?.lowercased() == "singular" else { continue }
            guard let voice = form.voice?.lowercased(), voiceCandidates.contains(voice) else { continue }
            return form.form
        }
        return nil
    }

    guard let present = pick(tense: "present", voiceCandidates: ["active"]) else { return nil }
    guard let future = pick(tense: "future", voiceCandidates: ["active"]) else { return nil }
    guard let aoristActive = pick(tense: "aorist", voiceCandidates: ["active"]) else { return nil }
    guard let perfectActive = pick(tense: "perfect", voiceCandidates: ["active"]) else { return nil }
    guard let perfectMP = pick(tense: "perfect", voiceCandidates: ["middle", "passive", "middle-passive"]) else { return nil }
    guard let aoristPassive = pick(tense: "aorist", voiceCandidates: ["passive", "middle-passive"]) else { return nil }

    return VerbPrincipalParts(forms: [
        present,
        future,
        aoristActive,
        perfectActive,
        perfectMP,
        aoristPassive
    ])
}
