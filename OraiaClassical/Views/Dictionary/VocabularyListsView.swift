import SwiftUI

struct VocabularyListsView: View {
    @StateObject private var viewModel = VocabularyListsViewModel()
    @State private var showCreateSheet = false

    var body: some View {
        VStack(spacing: 12) {
            if viewModel.isLoading {
                ProgressView()
                    .padding(.top, 20)
            } else if let errorMessage = viewModel.errorMessage {
                Text(errorMessage)
                    .foregroundColor(.secondary)
                    .padding(.top, 20)
            } else if viewModel.lists.isEmpty {
                Text("No lists yet. Create one to start collecting words.")
                    .foregroundColor(.secondary)
                    .padding(.top, 20)
            }

            List {
                ForEach(viewModel.lists) { list in
                    NavigationLink {
                        VocabularyListDetailView(list: list)
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(list.title)
                                .font(.headline)
                            if let description = list.description, !description.isEmpty {
                                Text(description)
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) {
                            viewModel.deleteList(title: list.title)
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                }
            }
            .listStyle(.plain)
        }
        .navigationTitle("Vocabulary Lists")
        .toolbar {
            Button {
                showCreateSheet = true
            } label: {
                Image(systemName: "plus")
            }
        }
        .sheet(isPresented: $showCreateSheet) {
            NewVocabularyListSheet { title, description in
                viewModel.createList(title: title, description: description)
            }
        }
        .onAppear {
            viewModel.load()
        }
        .onReceive(NotificationCenter.default.publisher(for: .vocabularyListsDidUpdate)) { _ in
            viewModel.load()
        }
    }
}

private struct VocabularyListDetailView: View {
    let list: VocabularyList
    @StateObject private var viewModel: VocabularyListDetailViewModel
    @State private var query = ""

    init(list: VocabularyList) {
        self.list = list
        _viewModel = StateObject(wrappedValue: VocabularyListDetailViewModel(listTitle: list.title))
    }

    var body: some View {
        VStack(spacing: 12) {
            searchBar

            if let errorMessage = viewModel.errorMessage {
                Text(errorMessage)
                    .foregroundColor(.secondary)
            }

            List {
                Section("Words") {
                    if viewModel.entries.isEmpty {
                        Text("No words in this list yet.")
                            .foregroundColor(.secondary)
                    } else {
                        ForEach(viewModel.entries) { entry in
                            LemmaRowView(lemma: entry)
                                .swipeActions(edge: .trailing) {
                                    Button(role: .destructive) {
                                        viewModel.removeLemma(entry.id)
                                    } label: {
                                        Label("Remove", systemImage: "trash")
                                    }
                                }
                        }
                    }
                }

                if !filteredResults.isEmpty {
                    Section("Add Results") {
                        ForEach(filteredResults) { result in
                            HStack {
                                LemmaRowView(lemma: result)
                                Spacer()
                                Button {
                                    viewModel.addLemma(result.id)
                                } label: {
                                    Image(systemName: "plus.circle.fill")
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
        }
        .navigationTitle(list.title)
        .onAppear {
            viewModel.loadEntries()
        }
        .onChange(of: query) { _ in
            viewModel.search(query: query)
        }
    }

    private var filteredResults: [LemmaSummary] {
        let existing = Set(viewModel.entries.map(\.id))
        return viewModel.searchResults.filter { !existing.contains($0.id) }
    }

    private var searchBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.secondary)

            TextField("Search lemma to add", text: $query)
                .textInputAutocapitalization(.never)
                .disableAutocorrection(true)

            if !query.isEmpty {
                Button {
                    query = ""
                    viewModel.searchResults = []
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(.secondarySystemBackground))
        )
        .padding(.horizontal, 16)
    }
}

private struct LemmaRowView: View {
    let lemma: LemmaSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(lemma.headword)
                .font(.headline)
            if let pos = lemma.primaryPOS, !pos.isEmpty {
                Text(pos.displayTitle(defaultTitle: pos))
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}

private struct NewVocabularyListSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var description = ""

    let onCreate: (String, String?) -> Void

    var body: some View {
        NavigationStack {
            Form {
                Section("Title") {
                    TextField("List title", text: $title)
                }

                Section("Description") {
                    TextField("Optional description", text: $description)
                }
            }
            .navigationTitle("New List")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") {
                        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
                        let desc = description.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !trimmed.isEmpty else { return }
                        onCreate(trimmed, desc.isEmpty ? nil : desc)
                        dismiss()
                    }
                    .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
}
