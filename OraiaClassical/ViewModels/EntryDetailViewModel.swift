import Foundation

@MainActor
final class EntryDetailViewModel: ObservableObject {
    @Published var lemma: LemmaDetail?
    @Published var isLoading = false
    @Published var errorMessage: String?

    private let lemmaID: Int64

    init(lemmaID: Int64) {
        self.lemmaID = lemmaID
    }

    func load() {
        isLoading = true
        errorMessage = nil

        Task {
            do {
                let detail = try await SQLiteStore.shared.fetchLemmaDetail(id: lemmaID)
                lemma = detail
                isLoading = false
            } catch {
                errorMessage = error.localizedDescription
                isLoading = false
            }
        }
    }

    func toggleFavorite() {
        guard var lemma else { return }
        let newValue = !lemma.isFavorite
        lemma.isFavorite = newValue
        self.lemma = lemma

        Task {
            do {
                try await SQLiteStore.shared.updateFavorite(lemmaID: lemmaID, isFavorite: newValue)
                NotificationCenter.default.post(name: .lemmaDidUpdate, object: lemmaID)
            } catch {
                self.errorMessage = error.localizedDescription
                self.lemma?.isFavorite = !newValue
            }
        }
    }

    func updateLearningStatus(_ status: LearningStatus) {
        guard var lemma else { return }
        lemma.learningStatus = status
        self.lemma = lemma

        Task {
            do {
                try await SQLiteStore.shared.updateLearningStatus(lemmaID: lemmaID, status: status)
                NotificationCenter.default.post(name: .lemmaDidUpdate, object: lemmaID)
            } catch {
                self.errorMessage = error.localizedDescription
            }
        }
    }
}
