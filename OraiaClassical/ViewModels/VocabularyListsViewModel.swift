import Foundation

@MainActor
final class VocabularyListsViewModel: ObservableObject {
    @Published var lists: [VocabularyList] = []
    @Published var isLoading = false
    @Published var errorMessage: String?

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

    func createList(title: String, description: String?) {
        isLoading = true
        errorMessage = nil
        Task {
            do {
                try await SQLiteStore.shared.createVocabularyList(title: title, description: description)
                NotificationCenter.default.post(name: .vocabularyListsDidUpdate, object: nil)
                let lists = try await SQLiteStore.shared.fetchVocabularyLists()
                self.lists = lists
                self.isLoading = false
            } catch {
                self.errorMessage = error.localizedDescription
                self.isLoading = false
            }
        }
    }

    func deleteList(title: String) {
        isLoading = true
        errorMessage = nil
        Task {
            do {
                try await SQLiteStore.shared.deleteVocabularyList(title: title)
                NotificationCenter.default.post(name: .vocabularyListsDidUpdate, object: nil)
                let lists = try await SQLiteStore.shared.fetchVocabularyLists()
                self.lists = lists
                self.isLoading = false
            } catch {
                self.errorMessage = error.localizedDescription
                self.isLoading = false
            }
        }
    }
}

@MainActor
final class VocabularyListDetailViewModel: ObservableObject {
    @Published var entries: [LemmaSummary] = []
    @Published var searchResults: [LemmaSummary] = []
    @Published var isLoading = false
    @Published var errorMessage: String?

    let listTitle: String

    init(listTitle: String) {
        self.listTitle = listTitle
    }

    func loadEntries() {
        isLoading = true
        errorMessage = nil
        Task {
            do {
                let entries = try await SQLiteStore.shared.fetchVocabularyListEntries(listTitle: listTitle)
                self.entries = entries
                self.isLoading = false
            } catch {
                self.errorMessage = error.localizedDescription
                self.isLoading = false
            }
        }
    }

    func search(query: String) {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            searchResults = []
            return
        }
        Task {
            do {
                let results = try await SQLiteStore.shared.searchLemmas(
                    query: trimmed,
                    mode: .startsWith,
                    favoritesOnly: false,
                    learningStatus: nil,
                    listTitle: nil,
                    limit: 50
                )
                self.searchResults = results
            } catch {
                self.searchResults = []
                self.errorMessage = error.localizedDescription
            }
        }
    }

    func addLemma(_ lemmaID: Int64) {
        Task {
            do {
                try await SQLiteStore.shared.addLemmaToVocabularyList(listTitle: listTitle, lemmaID: lemmaID)
                NotificationCenter.default.post(name: .vocabularyListsDidUpdate, object: nil)
                let entries = try await SQLiteStore.shared.fetchVocabularyListEntries(listTitle: listTitle)
                self.entries = entries
            } catch {
                self.errorMessage = error.localizedDescription
            }
        }
    }

    func removeLemma(_ lemmaID: Int64) {
        Task {
            do {
                try await SQLiteStore.shared.removeLemmaFromVocabularyList(listTitle: listTitle, lemmaID: lemmaID)
                NotificationCenter.default.post(name: .vocabularyListsDidUpdate, object: nil)
                let entries = try await SQLiteStore.shared.fetchVocabularyListEntries(listTitle: listTitle)
                self.entries = entries
            } catch {
                self.errorMessage = error.localizedDescription
            }
        }
    }
}
