import SwiftUI

struct DictionaryView: View {
    @Environment(\.theme) private var theme
    @StateObject private var viewModel = DictionaryViewModel()
    @State private var query = ""

    @AppStorage(SearchSettingsKeys.searchMode) private var searchModeRaw = SearchMode.startsWith.rawValue
    @AppStorage(SearchSettingsKeys.favoritesOnly) private var favoritesOnly = false
    @AppStorage(SearchSettingsKeys.learningStatus) private var learningStatusRaw = -1
    @AppStorage(SearchSettingsKeys.listTitle) private var listTitle = ""

    private var searchMode: SearchMode {
        SearchMode(rawValue: searchModeRaw) ?? .startsWith
    }

    private var learningStatusFilter: LearningStatus? {
        LearningStatus(rawValue: learningStatusRaw)
    }

    private var options: DictionarySearchOptions {
        DictionarySearchOptions(
            mode: searchMode,
            favoritesOnly: favoritesOnly,
            learningStatus: learningStatusFilter,
            listTitle: listTitle.isEmpty ? nil : listTitle
        )
    }

    private var hasActiveFilters: Bool {
        favoritesOnly || learningStatusFilter != nil || !listTitle.isEmpty
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                searchBar

                if viewModel.isLoading {
                    ProgressView()
                        .padding(.top, 20)
                } else if let errorMessage = viewModel.errorMessage {
                    Text(errorMessage)
                        .foregroundColor(theme.text.opacity(0.7))
                        .padding(.top, 20)
                } else if query.trimmed().isEmpty && !hasActiveFilters {
                    Text("Search by lemma or apply a filter to see results.")
                        .foregroundColor(theme.text.opacity(0.7))
                        .padding(.top, 20)
                } else if viewModel.results.isEmpty {
                    Text("No results found.")
                        .foregroundColor(theme.text.opacity(0.7))
                        .padding(.top, 20)
                } else {
                    List(viewModel.results) { lemma in
                        NavigationLink {
                            EntryDetailView(lemmaID: lemma.id)
                        } label: {
                            LemmaCardView(lemma: lemma)
                        }
                        .listRowBackground(theme.surfaceAlt)
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                }
            }
            .padding(.horizontal, 16)
            .navigationTitle("Dictionary")
            .toolbar {
                NavigationLink {
                    SearchSettingsView()
                } label: {
                    Image(systemName: "slider.horizontal.3")
                }

                NavigationLink {
                    VocabularyListsView()
                } label: {
                    Image(systemName: "list.bullet.rectangle")
                }
            }
            .onAppear {
                viewModel.refresh(query: query, options: options)
            }
            .onChange(of: query) {
                viewModel.search(query: query, options: options)
            }
            .onChange(of: searchModeRaw) {
                viewModel.search(query: query, options: options)
            }
            .onChange(of: favoritesOnly) {
                viewModel.search(query: query, options: options)
            }
            .onChange(of: learningStatusRaw) {
                viewModel.search(query: query, options: options)
            }
            .onChange(of: listTitle) {
                viewModel.search(query: query, options: options)
            }
            .onReceive(NotificationCenter.default.publisher(for: .lemmaDidUpdate)) { _ in
                viewModel.refresh(query: query, options: options)
            }
            .onReceive(NotificationCenter.default.publisher(for: .vocabularyListsDidUpdate)) { _ in
                viewModel.refresh(query: query, options: options)
            }
        }
    }

    private var searchBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundColor(theme.text.opacity(0.6))

            TextField("Search lemma", text: $query)
                .textInputAutocapitalization(.never)
                .disableAutocorrection(true)

            if !query.isEmpty {
                Button {
                    query = ""
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
    }
}

private struct LemmaCardView: View {
    let lemma: LemmaSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(lemma.headword)
                    .font(.headline)

                Spacer()

                if lemma.isFavorite {
                    Image(systemName: "star.fill")
                        .foregroundColor(.yellow)
                }
            }

            HStack(spacing: 8) {
                if let pos = lemma.primaryPOS {
                    TagPill(text: pos.displayTitle(defaultTitle: pos), color: Color.blue.opacity(0.15), foreground: .blue)
                }

                TagPill(text: lemma.learningStatus.label, color: Color.green.opacity(0.15), foreground: .green)
            }
        }
        .padding(.vertical, 8)
    }
}
