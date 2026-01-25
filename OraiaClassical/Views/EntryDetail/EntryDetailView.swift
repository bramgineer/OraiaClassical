import SwiftUI

struct EntryDetailView: View {
    @StateObject private var viewModel: EntryDetailViewModel

    init(lemmaID: Int64) {
        _viewModel = StateObject(wrappedValue: EntryDetailViewModel(lemmaID: lemmaID))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if viewModel.isLoading {
                    ProgressView()
                        .padding(.top, 40)
                } else if let errorMessage = viewModel.errorMessage {
                    Text(errorMessage)
                        .foregroundColor(.secondary)
                        .padding(.top, 40)
                } else if let lemma = viewModel.lemma {
                    header(for: lemma)
                    posSection(for: lemma)
                    learningStatusSection(for: lemma)
                    formsSection(for: lemma)
                    sensesSection(for: lemma)
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 32)
        }
        .navigationTitle(viewModel.lemma?.headword ?? "Entry")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            viewModel.load()
        }
    }

    private func header(for lemma: LemmaDetail) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(lemma.headword)
                .font(.largeTitle.weight(.semibold))

            Spacer()

            Button {
                viewModel.toggleFavorite()
            } label: {
                Image(systemName: lemma.isFavorite ? "star.fill" : "star")
                    .foregroundColor(lemma.isFavorite ? .yellow : .secondary)
                    .font(.title3)
            }
            .buttonStyle(.plain)
        }
    }

    private func posSection(for lemma: LemmaDetail) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Parts of Speech")
                .font(.headline)

            if lemma.posCodes.isEmpty {
                Text("No POS data")
                    .foregroundColor(.secondary)
            } else {
                let columns = [GridItem(.adaptive(minimum: 80), spacing: 8)]
                LazyVGrid(columns: columns, alignment: .leading, spacing: 8) {
                    ForEach(lemma.posCodes, id: \.self) { code in
                        TagPill(
                            text: code.displayTitle(defaultTitle: code),
                            color: Color.blue.opacity(0.15),
                            foreground: .blue
                        )
                    }
                }
            }
        }
    }

    private func learningStatusSection(for lemma: LemmaDetail) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Learning Status")
                .font(.headline)

            Picker("Learning Status", selection: Binding(
                get: { lemma.learningStatus },
                set: { viewModel.updateLearningStatus($0) }
            )) {
                ForEach(LearningStatus.allCases) { status in
                    Text(status.label).tag(status)
                }
            }
            .pickerStyle(.menu)
        }
    }

    private func formsSection(for lemma: LemmaDetail) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            if lemma.posCodes.contains("noun") {
                NavigationLink {
                    FormsGridView(lemmaID: lemma.id, lemmaHeadword: lemma.headword, posCode: "noun")
                } label: {
                    formsLinkLabel(title: "Noun Forms")
                }
            }

            if lemma.posCodes.contains("verb") {
                NavigationLink {
                    FormsGridView(lemmaID: lemma.id, lemmaHeadword: lemma.headword, posCode: "verb")
                } label: {
                    formsLinkLabel(title: "Verb Forms")
                }
            }
        }
    }

    private func formsLinkLabel(title: String) -> some View {
        HStack {
            Text(title)
                .font(.headline)
            Spacer()
            Image(systemName: "chevron.right")
                .foregroundColor(.secondary)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(.secondarySystemBackground))
        )
    }

    private func sensesSection(for lemma: LemmaDetail) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Senses")
                .font(.headline)

            if lemma.senseGroups.isEmpty {
                Text("No senses available")
                    .foregroundColor(.secondary)
            } else {
                ForEach(lemma.senseGroups) { group in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(group.posCode.displayTitle(defaultTitle: group.posCode))
                            .font(.subheadline.weight(.semibold))
                            .foregroundColor(.secondary)

                        ForEach(group.senses) { sense in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(sense.gloss)
                                    .font(.body.weight(.semibold))
                                if let definition = sense.definition, !definition.isEmpty {
                                    Text(definition)
                                        .font(.body)
                                        .foregroundColor(.secondary)
                                }
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }
            }
        }
    }
}
