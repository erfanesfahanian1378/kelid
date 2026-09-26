import ArgumentParser
import Foundation
import KelidCore
import PersianText
import PredictionEngine

/// `klm` — builds and inspects Kelid Language Model (`.klm`) files.
///
/// `build`/`inspect` are real as of Phase 7 (task 7.4); `eval` (§6.7.12)
/// arrives with Phase 8's tuning work (task 8.9).
@main
struct KLMCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "klm",
        abstract: "Build and inspect Kelid Language Model (.klm) files.",
        version: "0.1.0-phase7",
        subcommands: [Build.self, Inspect.self]
    )
}

extension KLMCommand {
    struct Build: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Build a .klm file from unigram (and, from Phase 8, n-gram) counts.")

        @Option(help: "Language code (fa or en).")
        var lang: String

        @Option(help: "Path to a unigrams TSV (word<TAB>count[<TAB>flags]) — e.g. out/fa.unigrams.tsv.")
        var unigrams: String

        @Option(help: "Bigrams TSV — accepted but not yet built into the file (Phase 8, task 8.x).")
        var bigrams: String?

        @Option(help: "Trigrams TSV — accepted but not yet built into the file (Phase 8, task 8.x).")
        var trigrams: String?

        @Option(help: "Maximum vocabulary size (§6.7.2's caps: 200000 fa / 120000 en).")
        var maxWords: Int?

        @Option(name: .customLong("out"), help: "Output .klm path.")
        var outputPath: String

        func run() throws {
            guard let language = LanguageID(rawValue: lang) else {
                throw ValidationError("--lang must be \"fa\" or \"en\", got \"\(lang)\"")
            }
            if bigrams != nil || trigrams != nil {
                FileHandle.standardError.write(
                    Data("note: --bigrams/--trigrams are accepted but not yet built into the file (Phase 8).\n".utf8)
                )
            }

            let (entries, offensiveWords) = try Self.readUnigramsTSV(path: unigrams)
            guard !entries.isEmpty else {
                throw ValidationError("no valid unigrams found in \(unigrams)")
            }

            let cap = maxWords ?? (language == .fa ? 200_000 : 120_000)
            let data = try KLMWriter.build(language: language, unigrams: entries, maxWords: cap, offensiveWords: offensiveWords)
            try data.write(to: URL(fileURLWithPath: outputPath))

            let sizeMB = Double(data.count) / 1024 / 1024
            print("Wrote \(outputPath): \(entries.count > cap ? cap : entries.count) words, \(String(format: "%.2f", sizeMB)) MB")
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

        @Option(help: "Number of completions to print with --prefix.")
        var top: Int = 10

        func run() throws {
            let file = try KLMFile(path: model)
            if stats || prefix == nil {
                printStats(file)
            }
            if let prefix {
                printCompletions(file: file, prefix: prefix, limit: top)
            }
        }

        private func printStats(_ file: KLMFile) {
            print("language:     \(file.language?.rawValue ?? "?")")
            print("wordCount:    \(file.wordCount)")
            print("nodeCount:    \(file.nodeCount)")
            print("hasBigrams:   \(file.hasBigrams)")
            print("hasTrigrams:  \(file.hasTrigrams)")
            print("uniMinLog10:  \(file.uniMinLog10)")
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
    }
}
