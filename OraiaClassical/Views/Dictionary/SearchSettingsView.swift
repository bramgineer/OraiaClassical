import SwiftUI

struct SearchSettingsView: View {
    @StateObject private var viewModel = SearchSettingsViewModel()

    @AppStorage(SearchSettingsKeys.searchMode) private var searchModeRaw = SearchMode.startsWith.rawValue
    @AppStorage(SearchSettingsKeys.favoritesOnly) private var favoritesOnly = false
    @AppStorage(SearchSettingsKeys.learningStatus) private var learningStatusRaw = -1
    @AppStorage(SearchSettingsKeys.listTitle) private var listTitle = ""

    var body: some View {
        Form {
            Section("Search") {
                Picker("Match", selection: Binding(
                    get: { SearchMode(rawValue: searchModeRaw) ?? .startsWith },
                    set: { searchModeRaw = $0.rawValue }
                )) {
                    ForEach(SearchMode.allCases) { mode in
                        Text(mode.label).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
            }

            Section("Filters") {
                Toggle("Favorites only", isOn: $favoritesOnly)

                Picker("Learning status", selection: $learningStatusRaw) {
                    Text("Any").tag(-1)
                    ForEach(LearningStatus.allCases) { status in
                        Text(status.label).tag(status.rawValue)
                    }
                }

                if viewModel.lists.isEmpty {
                    Text("No lists available")
                        .foregroundColor(.secondary)
                } else {
                    Picker("Vocabulary list", selection: $listTitle) {
                        Text("Any").tag("")
                        ForEach(viewModel.lists) { list in
                            Text(list.title).tag(list.title)
                        }
                    }
                }
            }
        }
        .navigationTitle("Search Settings")
        .onAppear {
            viewModel.load()
        }
    }
}
