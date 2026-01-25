import Foundation

extension String {
    func displayTitle(defaultTitle: String) -> String {
        guard !isEmpty else { return defaultTitle }
        return prefix(1).uppercased() + dropFirst()
    }

    func trimmed() -> String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func equalsMorph(_ other: String) -> Bool {
        normalizedMorph() == other.normalizedMorph()
    }

    private func normalizedMorph() -> String {
        trimmingCharacters(in: .whitespacesAndNewlines)
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
            .folding(options: .diacriticInsensitive, locale: .current)
            .lowercased()
    }
}
