import SwiftUI

struct QuizListPickerView: View {
    let title: String
    let lists: [VocabularyList]
    @Binding var selection: Set<String>
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List(lists) { list in
                Toggle(list.title, isOn: binding(for: list.title))
            }
            .navigationTitle(title)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func binding(for value: String) -> Binding<Bool> {
        Binding(
            get: { selection.contains(value) },
            set: { isOn in
                if isOn {
                    selection.insert(value)
                } else {
                    selection.remove(value)
                }
            }
        )
    }
}
