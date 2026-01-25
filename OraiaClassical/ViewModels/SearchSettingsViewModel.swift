import Foundation

@MainActor
final class SearchSettingsViewModel: ObservableObject {
    @Published var lists: [VocabularyList] = []
    @Published var errorMessage: String?

    func load() {
        Task {
            do {
                let lists = try await SQLiteStore.shared.fetchVocabularyLists()
                self.lists = lists
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}
