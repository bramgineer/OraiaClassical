import Foundation

struct DictionarySearchOptions: Equatable {
    var mode: SearchMode
    var favoritesOnly: Bool
    var learningStatus: LearningStatus?
    var listTitle: String?
}

@MainActor
final class DictionaryViewModel: ObservableObject {
    @Published var results: [LemmaSummary] = []
    @Published var isLoading = false
    @Published var errorMessage: String?

    private var searchTask: Task<Void, Never>?

    func search(query: String, options: DictionarySearchOptions) {
        searchTask?.cancel()
        let trimmed = query.trimmed()
        let hasFilters = options.favoritesOnly || options.learningStatus != nil || (options.listTitle?.isEmpty == false)
        guard !trimmed.isEmpty || hasFilters else {
            results = []
            errorMessage = nil
            isLoading = false
            return
        }

        isLoading = true
        errorMessage = nil

        searchTask = Task {
            try? await Task.sleep(nanoseconds: 250_000_000)
            guard !Task.isCancelled else { return }

            do {
                let items = try await SQLiteStore.shared.searchLemmas(
                    query: trimmed,
                    mode: options.mode,
                    favoritesOnly: options.favoritesOnly,
                    learningStatus: options.learningStatus,
                    listTitle: options.listTitle
                )
                guard !Task.isCancelled else { return }
                results = items
                isLoading = false
            } catch {
                guard !Task.isCancelled else { return }
                errorMessage = error.localizedDescription
                isLoading = false
            }
        }
    }

    func refresh(query: String, options: DictionarySearchOptions) {
        search(query: query, options: options)
    }
}
