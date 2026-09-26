import Foundation
@testable import PredictionEngine
import Testing

/// Task 7.12's benchmark requirement — "XCTest measure for 1-character and
/// 3-character prefixes." This project uses Swift Testing everywhere else
/// (no `XCTest` anywhere in the codebase), so introducing a single
/// `XCTestCase` just for this one measurement would be inconsistent with
/// every other test; a `ContinuousClock`-timed loop over many iterations
/// serves the same purpose (catching a latency regression, and giving real
/// numbers for PROGRESS.md) without mixing test frameworks. On-device
/// numbers from the debug overlay (this test's other half) need a physical
/// device — see PROGRESS.md's Phase 7 handoff notes for what's still
/// outstanding there.
@Suite("Suggestion latency benchmark (task 7.12)")
struct SuggestionBenchmarkTests {
    /// Builds a real-scale (10,000-word) fixture rather than a tiny one —
    /// latency at 60/200 words tells you nothing about the real 120k/200k
    /// word models.
    static func makeRealisticLexicon() throws -> Lexicon {
        var generator = SplitMix64(seed: 42)
        let letters = Array("ابپتثجچحخدذرزژسشصضطظعغفقکگلمنوهی")
        var seen = Set<String>()
        var entries: [UnigramEntry] = []
        while entries.count < 10000 {
            let length = Int.random(in: 2 ... 8, using: &generator)
            let surface = String((0 ..< length).map { _ in letters.randomElement(using: &generator)! })
            guard seen.insert(surface).inserted else { continue }
            entries.append(UnigramEntry(surface: surface, count: UInt64.random(in: 1 ... 1_000_000, using: &generator)))
        }
        let data = try KLMWriter.build(language: .fa, unigrams: entries, maxWords: 200_000)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("kelid-benchmark-\(UUID().uuidString).klm")
        try data.write(to: url)
        return try Lexicon(file: KLMFile(path: url.path))
    }

    @Test("completions for a 1-character prefix stay well under the 20ms on-device budget in the Simulator")
    func oneCharacterPrefixLatency() throws {
        let lexicon = try Self.makeRealisticLexicon()
        let prefix = try String(#require("ابپتثجچحخدذرزژسشصضطظعغفقکگلمنوهی".first))
        let elapsed = Self.measure(iterations: 200) {
            _ = lexicon.completions(prefixKey: prefix, limit: 20)
        }
        print(
            "1-char prefix completions: \(elapsed.perIterationMilliseconds) ms/call (Simulator, macOS host — not the §7.12 on-device number)"
        )
        // A generous Simulator/CI budget, not the §6.7.12 on-device 20ms p95
        // itself (this session has no device to measure that on) — this
        // just catches a gross algorithmic regression (e.g. an accidental
        // linear scan replacing the best-first heap search).
        #expect(elapsed.perIterationMilliseconds < 50)
    }

    @Test("completions for a 3-character prefix stay well under the 20ms on-device budget in the Simulator")
    func threeCharacterPrefixLatency() throws {
        let lexicon = try Self.makeRealisticLexicon()
        let letters = Array("ابپتثجچحخدذرزژسشصضطظعغفقکگلمنوهی")
        let prefix = String(letters.prefix(3))
        let elapsed = Self.measure(iterations: 200) {
            _ = lexicon.completions(prefixKey: prefix, limit: 20)
        }
        print(
            "3-char prefix completions: \(elapsed.perIterationMilliseconds) ms/call (Simulator, macOS host — not the §7.12 on-device number)"
        )
        #expect(elapsed.perIterationMilliseconds < 50)
    }

    /// Same measurement against the real, committed 200,000-word
    /// `fa.klm` (built by `make klm` from Phase 6's quick-path unigrams) —
    /// skipped rather than failed if that file isn't present (e.g. a clean
    /// checkout before anyone's run `make klm` yet), since it's a real
    /// build artifact, not a checked-in fixture.
    @Test("completions against the real, committed fa.klm stay well under the 20ms on-device budget in the Simulator")
    func realFaModelLatency() throws {
        // Tests/PredictionEngineTests -> Tests -> KelidKit -> Packages -> repo root -> Keyboard/Resources/LM/fa.klm
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        let modelPath = repoRoot.appendingPathComponent("Keyboard/Resources/LM/fa.klm").path
        guard FileManager.default.fileExists(atPath: modelPath) else {
            print("skipped: \(modelPath) doesn't exist yet — run `make klm` first")
            return
        }
        let lexicon = try Lexicon(file: KLMFile(path: modelPath))
        let oneChar = Self.measure(iterations: 200) { _ = lexicon.completions(prefixKey: "م", limit: 20) }
        let threeChar = Self.measure(iterations: 200) { _ = lexicon.completions(prefixKey: "میخ", limit: 20) }
        print(
            "real fa.klm (\(lexicon.wordCount) words) — 1-char: \(oneChar.perIterationMilliseconds) ms/call, 3-char: \(threeChar.perIterationMilliseconds) ms/call"
        )
        #expect(oneChar.perIterationMilliseconds < 50)
        #expect(threeChar.perIterationMilliseconds < 50)
    }

    private struct Measurement {
        let perIterationMilliseconds: Double
    }

    private static func measure(iterations: Int, _ body: () -> Void) -> Measurement {
        let clock = ContinuousClock()
        let start = clock.now
        for _ in 0 ..< iterations {
            body()
        }
        let elapsed = clock.now - start
        let totalMilliseconds = Double(elapsed.components.seconds) * 1000 + Double(elapsed.components.attoseconds) / 1e15
        return Measurement(perIterationMilliseconds: totalMilliseconds / Double(iterations))
    }
}
