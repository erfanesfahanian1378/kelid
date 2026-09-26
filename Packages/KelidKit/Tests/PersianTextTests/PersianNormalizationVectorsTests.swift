import Foundation
@testable import PersianText
import Testing

/// Reads `vectors.json` — §6.6.7's minimum test-vector set, shared with the
/// Python data pipeline's `test_normalize.py` (Phase 6) — so the two
/// implementations of `canonical(_:)`/`matchKey(_:)` can never silently
/// drift apart. `PersianNormalizationTests.swift` covers the same rules
/// with descriptive, rule-by-rule cases; this file is the cross-language
/// contract check.
struct Vector: Decodable {
    let input: String
    let canonical: String
    let matchKey: String
    let note: String
}

private struct VectorsFile: Decodable {
    let vectors: [Vector]
}

@Suite("PersianNormalization vectors (§6.6.7, shared with the Python pipeline)")
struct PersianNormalizationVectorsTests {
    /// Empty if `vectors.json` is missing or fails to decode — rather than
    /// crashing at test-plan-build time (`@Test(arguments:)` needs a plain,
    /// non-throwing value here), `vectorsLoadedSuccessfully` below asserts
    /// non-emptiness explicitly, so a broken fixture still fails loudly as
    /// a normal test failure instead of vacuously running zero cases.
    private static let vectors: [Vector] = {
        guard let url = Bundle.module.url(forResource: "vectors", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode(VectorsFile.self, from: data)
        else {
            return []
        }
        return decoded.vectors
    }()

    @Test("vectors.json was found and decoded (guards against the parameterized tests below silently running zero cases)")
    func vectorsLoadedSuccessfully() {
        #expect(!Self.vectors.isEmpty)
    }

    @Test("every vector's canonical() matches the shared fixture", arguments: vectors)
    func canonicalMatchesVector(_ vector: Vector) {
        #expect(PersianNormalization.canonical(vector.input) == vector.canonical, Comment(rawValue: vector.note))
    }

    @Test("every vector's matchKey() matches the shared fixture", arguments: vectors)
    func matchKeyMatchesVector(_ vector: Vector) {
        #expect(PersianNormalization.matchKey(vector.input) == vector.matchKey, Comment(rawValue: vector.note))
    }
}
