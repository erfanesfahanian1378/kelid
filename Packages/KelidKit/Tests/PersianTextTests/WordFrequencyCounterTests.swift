@testable import PersianText
import Testing

@Suite("WordFrequencyCounter (task 10.6)")
struct WordFrequencyCounterTests {
    @Test("counts each distinct word and sorts by count descending")
    func countsAndSorts() {
        let result = WordFrequencyCounter.count(in: "cat dog cat bird cat dog")
        #expect(result.map(\.surface) == ["cat", "dog", "bird"])
        #expect(result.map(\.count) == [3, 2, 1])
    }

    @Test("words that differ only by ZWNJ/normalization count as the same word")
    func normalizesBeforeCounting() {
        let result = WordFrequencyCounter.count(in: "می\u{200C}خوام میخوام می\u{200C}خوام")
        #expect(result.count == 1)
        #expect(result.first?.count == 3)
    }

    @Test("punctuation and whitespace are not part of any word")
    func splitsOnNonWordCharacters() {
        let result = WordFrequencyCounter.count(in: "hello, world! hello... world?")
        #expect(Set(result.map(\.surface)) == ["hello", "world"])
        #expect(result.allSatisfy { $0.count == 2 })
    }

    @Test("empty text produces no words")
    func emptyTextProducesNothing() {
        #expect(WordFrequencyCounter.count(in: "").isEmpty)
        #expect(WordFrequencyCounter.count(in: "   \n\t  ").isEmpty)
    }

    @Test("the first-seen spelling is kept as the representative surface form")
    func keepsFirstSeenSpelling() {
        let result = WordFrequencyCounter.count(in: "Hello hello HELLO")
        // All three normalize to the same matchKey (case-insensitive) —
        // exactly one entry, spelled the way it first appeared.
        #expect(result.count == 1)
        #expect(result.first?.surface == "Hello")
        #expect(result.first?.count == 3)
    }

    @Test("a single real sentence tokenizes into exactly its words")
    func realSentenceTokenizesCorrectly() {
        let result = WordFrequencyCounter.count(in: "سلام دوست من، حالت چطوره؟")
        #expect(Set(result.map(\.surface)) == Set(["سلام", "دوست", "من", "حالت", "چطوره"]))
        #expect(result.allSatisfy { $0.count == 1 })
    }
}
