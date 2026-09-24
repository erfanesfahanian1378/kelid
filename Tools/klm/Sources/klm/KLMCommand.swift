import ArgumentParser
import PersianText
import PredictionEngine

/// `klm` — builds and inspects Kelid Language Model (`.klm`) files.
///
/// Phase 0 only ships a placeholder: `klm --version` must succeed, proving
/// the tool package builds and links `PredictionEngine`/`PersianText` from
/// `KelidKit`. The real `build` / `inspect` / `eval` subcommands (PLAN.md
/// §4.2, §7) arrive with the language data pipeline in Phase 6+.
@main
struct KLMCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "klm",
        abstract: "Build and inspect Kelid Language Model (.klm) files.",
        version: "0.0.0-phase0"
    )

    func run() throws {
        let persianTextReady = PersianTextPlaceholder().isReady
        let predictionEngineReady = PredictionEnginePlaceholder().isReady
        print("klm phase-0 placeholder — PersianText ready: \(persianTextReady), PredictionEngine ready: \(predictionEngineReady)")
        print("Real subcommands (build/inspect/eval) arrive with the language data pipeline (PLAN.md §7, Phase 6+).")
    }
}
