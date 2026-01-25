import Foundation

@MainActor
final class NounFormsViewModel: ObservableObject {
    @Published var forms: [NounForm] = []
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
                let forms = try await SQLiteStore.shared.fetchNounForms(lemmaID: lemmaID)
                self.forms = forms
                self.isLoading = false
            } catch {
                self.errorMessage = error.localizedDescription
                self.isLoading = false
            }
        }
    }
}

@MainActor
final class VerbFormsViewModel: ObservableObject {
    @Published var forms: [VerbForm] = []
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
                let forms = try await SQLiteStore.shared.fetchVerbForms(lemmaID: lemmaID)
                self.forms = forms
                self.isLoading = false
            } catch {
                self.errorMessage = error.localizedDescription
                self.isLoading = false
            }
        }
    }
}
