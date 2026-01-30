import SwiftUI

struct QuizHubView: View {
    @Environment(\.theme) private var theme

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
    @Environment(\.theme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: systemImage)
                .font(.title2)
                .foregroundColor(theme.accent)

            Text(title)
                .font(.headline)
                .foregroundColor(theme.text)

            Text(subtitle)
                .font(.subheadline)
                .foregroundColor(theme.text.opacity(0.7))
        }
        .frame(maxWidth: .infinity, minHeight: 120, alignment: .leading)
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(theme.surface)
        )
    }
}

#Preview {
    QuizHubView()
}
