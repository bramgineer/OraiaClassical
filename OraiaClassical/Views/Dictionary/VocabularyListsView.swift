import SwiftUI

struct VocabularyListsView: View {
    @Environment(\.theme) private var theme
    @StateObject private var viewModel = VocabularyListsViewModel()
    @State private var showCreateSheet = false

    var body: some View {
        VStack(spacing: 12) {
            if viewModel.isLoading {
                ProgressView()
                    .padding(.top, 20)
            } else if let errorMessage = viewModel.errorMessage {
                Text(errorMessage)
                    .foregroundColor(theme.text.opacity(0.7))
                    .padding(.top, 20)
            } else if viewModel.lists.isEmpty {
                Text("No lists yet. Create one to start collecting words.")
                    .foregroundColor(theme.text.opacity(0.7))
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
                                    .foregroundColor(theme.text.opacity(0.7))
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    .listRowBackground(theme.surfaceAlt)
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
            .scrollContentBackground(.hidden)
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
    @Environment(\.theme) private var theme

    init(list: VocabularyList) {
        self.list = list
        _viewModel = StateObject(wrappedValue: VocabularyListDetailViewModel(listTitle: list.title))
    }

    var body: some View {
        VStack(spacing: 12) {
            searchBar

            if let errorMessage = viewModel.errorMessage {
                Text(errorMessage)
                    .foregroundColor(theme.text.opacity(0.7))
            }

            List {
                Section("Words") {
                    if viewModel.entries.isEmpty {
                        Text("No words in this list yet.")
                            .foregroundColor(theme.text.opacity(0.7))
                    } else {
                        ForEach(viewModel.entries) { entry in
                            LemmaRowView(lemma: entry)
                                .listRowBackground(theme.surfaceAlt)
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
                            .listRowBackground(theme.surfaceAlt)
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
        }
        .navigationTitle(list.title)
        .onAppear {
            viewModel.loadEntries()
        }
        .onChange(of: query) {
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
                .foregroundColor(theme.text.opacity(0.6))

            TextField("Search lemma to add", text: $query)
                .textInputAutocapitalization(.never)
                .disableAutocorrection(true)

            if !query.isEmpty {
                Button {
                    query = ""
                    viewModel.searchResults = []
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(theme.text.opacity(0.6))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(theme.surfaceAlt)
        )
        .padding(.horizontal, 16)
    }
}

private struct LemmaRowView: View {
    let lemma: LemmaSummary
    @Environment(\.theme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(lemma.headword)
                .font(.headline)
            if let pos = lemma.primaryPOS, !pos.isEmpty {
                Text(pos.displayTitle(defaultTitle: pos))
                    .font(.subheadline)
                    .foregroundColor(theme.text.opacity(0.7))
            }
        }
        .padding(.vertical, 4)
    }
}

private struct NewVocabularyListSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.theme) private var theme
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
            .scrollContentBackground(.hidden)
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
        .background(theme.background)
    }
}
