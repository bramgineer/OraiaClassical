import SwiftUI

struct MainPageView: View {
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    header
                    tiles
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .padding(.bottom, 24)
            }
            .navigationTitle("Oraia Classical")
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Welcome")
                .font(.title2.weight(.semibold))
            Text("Jump back into the dictionary or manage your study lists.")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
    }

    private var tiles: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 16) {
            NavigationLink {
                DictionaryView()
            } label: {
                MainNavTile(
                    title: "Dictionary",
                    subtitle: "Search lemmas",
                    systemImage: "book"
                )
            }

            NavigationLink {
                QuizHubView()
            } label: {
                MainNavTile(
                    title: "Quizzes",
                    subtitle: "Vocab + verbs",
                    systemImage: "checkmark.seal"
                )
            }

            NavigationLink {
                VocabularyListsView()
            } label: {
                MainNavTile(
                    title: "Lists",
                    subtitle: "Build vocabulary",
                    systemImage: "list.bullet.rectangle"
                )
            }
        }
    }
}

private struct MainNavTile: View {
    let title: String
    let subtitle: String
    let systemImage: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: systemImage)
                .font(.title2)
                .foregroundColor(.accentColor)

            Text(title)
                .font(.headline)
                .foregroundColor(.primary)

            Text(subtitle)
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 120, alignment: .leading)
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(.secondarySystemBackground))
        )
    }
}

#Preview {
    MainPageView()
}
