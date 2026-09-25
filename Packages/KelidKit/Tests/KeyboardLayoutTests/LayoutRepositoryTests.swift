@testable import KeyboardLayout
import Testing

@Suite("LayoutRepository")
struct LayoutRepositoryTests {
    @Test("every bundled layout loads and validates", arguments: LayoutRepository.allLayoutIDs)
    func everyLayoutLoads(id: String) {
        let repository = LayoutRepository()
        let file = repository.layout(id: id)
        #expect(file.id == id)
    }

    @Test("every Persian letter appears exactly once in fa.standard")
    func faStandardHasEveryLetterOnce() throws {
        let file = LayoutRepository().layout(id: "fa.standard")
        try LayoutValidator.validatePersianAlphabetComplete(file)
    }

    @Test("fa.compact omits چ as a standalone key (it's ج's long-press alternate)")
    func faCompactOmitsChehArgheh() {
        let file = LayoutRepository().layout(id: "fa.compact")
        let lettersPage = file[.letters]
        let allOut = lettersPage?.rows.flatMap { $0.compactMap(\.out) } ?? []
        #expect(!allOut.contains("چ"))
        #expect(file.alternates["ج"] == ["چ"])
    }

    @Test("an unknown layout id falls back to en.qwerty")
    func unknownIDFallsBack() {
        let file = LayoutRepository().layout(id: "does.not.exist")
        #expect(file.id == "en.qwerty")
    }

    @Test("loading the same id twice returns a cached, equal result")
    func loadingIsCached() {
        let repository = LayoutRepository()
        let first = repository.layout(id: "en.qwerty")
        let second = repository.layout(id: "en.qwerty")
        #expect(first == second)
    }
}
