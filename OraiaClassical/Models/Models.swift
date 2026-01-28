import Foundation

enum SearchMode: String, CaseIterable, Identifiable {
    case startsWith = "startsWith"
    case contains = "contains"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .startsWith:
            return "Starts With"
        case .contains:
            return "Contains"
        }
    }
}

enum LearningStatus: Int, CaseIterable, Identifiable {
    case new = 0
    case inProgress = 1
    case completed = 2
    case restarted = 3
    case ignored = 4

    var id: Int { rawValue }

    var label: String {
        switch self {
        case .new:
            return "New"
        case .inProgress:
            return "In Progress"
        case .completed:
            return "Completed"
        case .restarted:
            return "Restarted"
        case .ignored:
            return "Ignored"
        }
    }
}

struct LemmaSummary: Identifiable, Hashable {
    let id: Int64
    let headword: String
    let primaryPOS: String?
    let isFavorite: Bool
    let learningStatus: LearningStatus
}

struct LemmaDetail: Identifiable, Hashable {
    let id: Int64
    var headword: String
    var notes: String?
    var isFavorite: Bool
    var learningStatus: LearningStatus
    var posCodes: [String]
    var senseGroups: [SenseGroup]
}

struct SenseItem: Identifiable, Hashable {
    let id: Int64
    let gloss: String
    let definition: String?
    let order: Int
}

struct SenseGroup: Identifiable, Hashable {
    let id: String
    let posCode: String
    let senses: [SenseItem]
}

struct VocabularyList: Identifiable, Hashable {
    let id: String
    let title: String
    let description: String?
}

enum QuizDirection: String, CaseIterable, Identifiable {
    case l1ToL2 = "l1ToL2"
    case l2ToL1 = "l2ToL1"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .l1ToL2:
            return "English → Greek"
        case .l2ToL1:
            return "Greek → English"
        }
    }
}

enum QuizAnswerType: String, CaseIterable, Identifiable {
    case textEntry = "textEntry"
    case multipleChoice = "multipleChoice"
    case flashCard = "flashCard"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .textEntry:
            return "Text Entry"
        case .multipleChoice:
            return "Multiple Choice"
        case .flashCard:
            return "Flash Cards"
        }
    }
}

struct VocabQuizConfig: Hashable {
    var listTitles: [String]
    var includeFavorites: Bool
    var learningStatuses: [LearningStatus]
    var questionCount: Int
    var direction: QuizDirection
    var answerType: QuizAnswerType
}

struct VocabQuizItem: Identifiable, Hashable {
    let id: Int64
    let headword: String
    let gloss: String
}

struct VocabQuizQuestion: Identifiable, Hashable {
    let id: UUID
    let prompt: String
    let correctAnswer: String
    let options: [String]
}

struct VocabQuizResponse: Identifiable, Hashable {
    let id: UUID
    let questionID: UUID
    let userAnswer: String
    let isCorrect: Bool
}

struct NounForm: Identifiable, Hashable {
    let id: Int64
    let form: String
    let number: String?
    let grammaticalCase: String?
    let gender: String?
    let dialect: String
}

struct VerbForm: Identifiable, Hashable {
    let id: Int64
    let form: String
    let person: String?
    let number: String?
    let tense: String?
    let mood: String?
    let voice: String?
    let verbFormType: String?
    let dialect: String
}
