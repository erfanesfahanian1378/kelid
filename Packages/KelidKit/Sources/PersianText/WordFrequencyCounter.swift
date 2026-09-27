/// Task 10.6's "Learn from text": tokenizes free text into words and counts
/// occurrences, for the app's Dictionary manager to preview before
/// committing. Pulled out as a pure, standalone function (rather than
/// living inline in the App target's SwiftUI view) so it's unit-testable
/// without a UI-test harness.
public enum WordFrequencyCounter {
    public struct WordCount: Sendable, Equatable {
        public let surface: String
        public let count: Int
    }

    /// Splits on everything `WordCharacters.isWordCharacter` doesn't
    /// consider part of a word — the same predicate `InputEngine`'s own
    /// word-boundary logic uses, so "a word" here means the same thing it
    /// does everywhere else in Kelid. Occurrences are grouped by
    /// `PersianNormalization.matchKey` (so "می‌خوام"/"میخوام" count as the
    /// same word), keeping the *first-seen* spelling as the representative
    /// surface form. Results are sorted by count, descending.
    public static func count(in text: String) -> [WordCount] {
        var order: [String] = []
        var counts: [String: (surface: String, count: Int)] = [:]
        var current = ""

        func flush() {
            guard !current.isEmpty else { return }
            defer { current = "" }
            let key = PersianNormalization.matchKey(current)
            if var existing = counts[key] {
                existing.count += 1
                counts[key] = existing
            } else {
                counts[key] = (surface: current, count: 1)
                order.append(key)
            }
        }

        for character in text {
            if WordCharacters.isWordCharacter(character) {
                current.append(character)
            } else {
                flush()
            }
        }
        flush()

        return order.compactMap { key in
            counts[key].map { WordCount(surface: $0.surface, count: $0.count) }
        }.sorted { $0.count > $1.count }
    }
}
