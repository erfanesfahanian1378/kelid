import ArgumentParser
import Foundation
import KelidCore
import PersianText
import PredictionEngine

/// `klm` — builds, inspects and evaluates Kelid Language Model (`.klm`) files.
@main
struct KLMCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "klm",
        abstract: "Build, inspect and evaluate Kelid Language Model (.klm) files.",
        version: "0.1.0-phase8",
        subcommands: [Build.self, Inspect.self, EvalSubcommand.self]
    )
}

extension KLMCommand {
    struct Build: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Build a .klm file from unigram (and, from Phase 8, n-gram) counts.")

        @Option(help: "Language code (fa or en).")
        var lang: String

        @Option(help: "Path to a unigrams TSV (word<TAB>count[<TAB>flags]) — e.g. out/fa.unigrams.tsv.")
        var unigrams: String

        @Option(help: "Bigrams TSV (w1<TAB>w2<TAB>count) — out/<lang>.bigrams.tsv.")
        var bigrams: String?

        @Option(help: "Trigrams TSV (w1<TAB>w2<TAB>w3<TAB>count) — out/<lang>.trigrams.tsv.")
        var trigrams: String?

        @Option(help: "Maximum vocabulary size (§6.7.2's caps: 200000 fa / 120000 en).")
        var maxWords: Int?

        @Option(name: .customLong("out"), help: "Output .klm path.")
        var outputPath: String

        func run() throws {
            guard let language = LanguageID(rawValue: lang) else {
                throw ValidationError("--lang must be \"fa\" or \"en\", got \"\(lang)\"")
            }

            let (entries, offensiveWords) = try Self.readUnigramsTSV(path: unigrams)
            guard !entries.isEmpty else {
                throw ValidationError("no valid unigrams found in \(unigrams)")
            }
            let bigramEntries = try bigrams.map(Self.readBigramsTSV) ?? []
            let trigramEntries = try trigrams.map(Self.readTrigramsTSV) ?? []

            let cap = maxWords ?? (language == .fa ? 200_000 : 120_000)
            var options = KLMBuildOptions()
            options.offensiveWords = offensiveWords
            let data = try KLMWriter.build(
                language: language,
                unigrams: entries,
                maxWords: cap,
                bigrams: bigramEntries,
                trigrams: trigramEntries,
                options: options
            )
            try data.write(to: URL(fileURLWithPath: outputPath))

            let sizeMB = Double(data.count) / 1024 / 1024
            print("Wrote \(outputPath): \(entries.count > cap ? cap : entries.count) words, \(String(format: "%.2f", sizeMB)) MB")
            if !bigramEntries.isEmpty {
                print("  + \(bigramEntries.count) bigram rows read from \(bigrams ?? "")")
            }
            if !trigramEntries.isEmpty {
                print("  + \(trigramEntries.count) trigram rows read from \(trigrams ?? "")")
            }
        }

        static func readBigramsTSV(path: String) throws -> [BigramEntry] {
            let contents = try String(contentsOfFile: path, encoding: .utf8)
            return contents.split(separator: "\n", omittingEmptySubsequences: true).compactMap { line in
                let columns = line.split(separator: "\t", omittingEmptySubsequences: false)
                guard columns.count >= 3, let count = UInt64(columns[2]) else { return nil }
                return BigramEntry(w1: String(columns[0]), w2: String(columns[1]), count: count)
            }
        }

        static func readTrigramsTSV(path: String) throws -> [TrigramEntry] {
            let contents = try String(contentsOfFile: path, encoding: .utf8)
            return contents.split(separator: "\n", omittingEmptySubsequences: true).compactMap { line in
                let columns = line.split(separator: "\t", omittingEmptySubsequences: false)
                guard columns.count >= 4, let count = UInt64(columns[3]) else { return nil }
                return TrigramEntry(w1: String(columns[0]), w2: String(columns[1]), w3: String(columns[2]), count: count)
            }
        }

        /// Reads `word<TAB>count` or `word<TAB>count<TAB>flags` lines
        /// (matching both `pipeline/quick.py`'s 2-column export and
        /// `pipeline/vocab.py`'s 3-column one, task 6.10) — a 3rd column
        /// containing "offensive" seeds `KLMWriter`'s offensive-word set
        /// directly from the pipeline's own vocabulary selection rather
        /// than needing a second curated list passed separately here.
        static func readUnigramsTSV(path: String) throws -> (entries: [UnigramEntry], offensiveWords: Set<String>) {
            let contents = try String(contentsOfFile: path, encoding: .utf8)
            var entries: [UnigramEntry] = []
            var offensiveWords: Set<String> = []
            for line in contents.split(separator: "\n", omittingEmptySubsequences: true) {
                let columns = line.split(separator: "\t", omittingEmptySubsequences: false)
                guard columns.count >= 2, let count = UInt64(columns[1]) else { continue }
                let surface = String(columns[0])
                entries.append(UnigramEntry(surface: surface, count: count))
                if columns.count >= 3, columns[2].split(separator: ",").contains("offensive") {
                    offensiveWords.insert(PersianNormalization.matchKey(surface))
                }
            }
            return (entries, offensiveWords)
        }
    }

    struct Inspect: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Inspect a .klm file's header, stats, or completions for a prefix.")

        @Option(help: "Path to a .klm file.")
        var model: String

        @Flag(help: "Print header/section statistics.")
        var stats = false

        @Option(help: "Print completions for this prefix (match-key normalized automatically).")
        var prefix: String?

        @Option(help: "Print next-word candidates for this context — \"<s>\" or one/two space-separated words (task 8.1).")
        var next: String?

        @Option(help: "Number of results to print with --prefix/--next.")
        var top: Int = 10

        func run() throws {
            let file = try KLMFile(path: model)
            if stats || (prefix == nil && next == nil) {
                printStats(file)
            }
            if let prefix {
                printCompletions(file: file, prefix: prefix, limit: top)
            }
            if let next {
                printNextWords(file: file, context: next, limit: top)
            }
        }

        private func printStats(_ file: KLMFile) {
            print("language:     \(file.language?.rawValue ?? "?")")
            print("wordCount:    \(file.wordCount)")
            print("nodeCount:    \(file.nodeCount)")
            print("hasBigrams:   \(file.hasBigrams)")
            print("hasTrigrams:  \(file.hasTrigrams)")
            print("uniMinLog10:  \(file.uniMinLog10)")
            print("biMinLog10:   \(file.biMinLog10)")
            print("triMinLog10:  \(file.triMinLog10)")
            print("buildUnixTime:\(file.buildUnixTime)")
            if file.wordCount > 0 {
                print("word 0 (most frequent): \(file.surface(0))")
            }
        }

        private func printCompletions(file: KLMFile, prefix: String, limit: Int) {
            let lexicon = Lexicon(file: file)
            let key = PersianNormalization.matchKey(prefix)
            let results = lexicon.completions(prefixKey: key, limit: limit)
            if results.isEmpty {
                print("(no completions for \"\(prefix)\")")
                return
            }
            for result in results {
                let log10P = file.log10Probability(result.wordID)
                print("\(result.surface)\tscore=\(result.score)\tlog10P=\(String(format: "%.3f", log10P))")
            }
        }

        /// `--next "<s>"` (empty prefix / sentence start) or `--next "من"` /
        /// `--next "من می‌خواهم"` (one or two space-separated context words).
        private func printNextWords(file: KLMFile, context: String, limit: Int) {
            let lexicon = Lexicon(file: file)
            let words = context.split(separator: " ").map(String.init)
            guard !words.isEmpty, words.count <= 2 else {
                print("--next takes \"<s>\" or one/two space-separated words")
                return
            }
            let ids = words.map { lexicon.wordID(forExactSurface: $0) }
            guard ids.allSatisfy({ $0 != nil }) else {
                print("(unknown context word in \"\(context)\" — not in the model's vocabulary)")
                return
            }
            let resolvedIDs = ids.compactMap { $0 }
            guard let lastID = resolvedIDs.last else { return }

            let candidates: [(next: UInt32, score: UInt8, source: String)]
            if resolvedIDs.count == 2, file.hasTrigrams {
                let trigram = lexicon.trigramCandidates(forContext: resolvedIDs[0], resolvedIDs[1])
                candidates = trigram.isEmpty
                    ? lexicon.bigramCandidates(forContext: lastID).map { ($0.next, $0.score, "bi") }
                    : trigram.map { ($0.next, $0.score, "tri") }
            } else {
                candidates = lexicon.bigramCandidates(forContext: lastID).map { ($0.next, $0.score, "bi") }
            }
            if candidates.isEmpty {
                print("(no next-word data for \"\(context)\")")
                return
            }
            for candidate in candidates.prefix(limit) {
                let log10P = candidate.source == "tri" ? lexicon.log10TrigramProbability(candidate.score) : lexicon
                    .log10BigramProbability(candidate.score)
                print(
                    "\(lexicon.surface(candidate.next))\tsource=\(candidate.source)\tscore=\(candidate.score)\tlog10P=\(String(format: "%.3f", log10P))"
                )
            }
        }
    }

    /// §6.7.12 (task 8.9): KSR, next-word accuracy, correction accuracy and
    /// completion latency against a held-out corpus. Named `EvalSubcommand`,
    /// not `Eval`, to avoid colliding with the `Eval` enum in `Eval.swift`
    /// that actually computes the metrics — this type is only the CLI
    /// surface over it.
    struct EvalSubcommand: ParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "eval",
            abstract: "Evaluate a .klm file against a held-out corpus (§6.7.12)."
        )

        @Option(help: "Path to a .klm file.")
        var model: String

        @Option(help: "Held-out corpus: one sentence per line, whitespace-tokenized (e.g. eval/fa_formal.txt).")
        var corpus: String

        @Option(help: "Seed for the synthetic-typo generator, for reproducible correction-accuracy numbers.")
        var typoSeed: UInt64 = 42

        func run() throws {
            let file = try KLMFile(path: model)
            let lexicon = Lexicon(file: file)
            let sentences = try Self.readCorpus(path: corpus)
            guard !sentences.isEmpty else {
                throw ValidationError("no sentences found in \(corpus)")
            }
            let metrics = Eval.run(lexicon: lexicon, sentences: sentences, proximity: .empty, typoSeed: typoSeed)
            Self.printReport(model: model, corpus: corpus, sentenceCount: sentences.count, metrics: metrics)
        }

        static func readCorpus(path: String) throws -> [[String]] {
            let contents = try String(contentsOfFile: path, encoding: .utf8)
            return contents.split(separator: "\n", omittingEmptySubsequences: true).map { line in
                line.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
            }
        }

        private static func printReport(model: String, corpus: String, sentenceCount: Int, metrics: Eval.Metrics) {
            print("model:                \(model)")
            print("corpus:               \(corpus) (\(sentenceCount) sentences, \(metrics.wordCount) words)")
            print("KSR:                  \(percent(metrics.ksr))")
            print("next-word top-1:      \(percent(metrics.nextWordTop1)) (n=\(metrics.nextWordSampleCount))")
            print("next-word top-3:      \(percent(metrics.nextWordTop3)) (n=\(metrics.nextWordSampleCount))")
            print("correction top-1:     \(percent(metrics.correctionTop1)) (n=\(metrics.correctionSampleCount))")
            print("correction top-3:     \(percent(metrics.correctionTop3)) (n=\(metrics.correctionSampleCount))")
            print("completion latency:   p50=\(ms(metrics.latencyP50Ms)) p95=\(ms(metrics.latencyP95Ms))")
        }

        private static func percent(_ value: Double) -> String {
            String(format: "%.1f%%", value * 100)
        }

        private static func ms(_ value: Double) -> String {
            String(format: "%.3fms", value)
        }
    }
}
