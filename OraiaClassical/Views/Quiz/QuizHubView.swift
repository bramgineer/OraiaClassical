import SwiftUI

struct QuizHubView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Quizzes")
                    .font(.title2.weight(.semibold))

                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 16) {
                    NavigationLink {
                        VocabQuizSetupView()
                    } label: {
                        QuizTile(title: "Vocabulary", subtitle: "Gloss ↔ Headword", systemImage: "text.book.closed")
                    }

                    NavigationLink {
                        VerbConjugationQuizSetupView()
                    } label: {
                        QuizTile(title: "Verb Conjugation", subtitle: "Forms + principal parts", systemImage: "character.book.closed")
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .padding(.bottom, 24)
        }
        .navigationTitle("Quizzes")
    }
}

private struct QuizTile: View {
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
    QuizHubView()
}
