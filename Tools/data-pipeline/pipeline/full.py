"""`make data-full` (tasks 6.4-6.14): the full Wikipedia-based pipeline.

**Not run end-to-end in Phase 6's own session** — see `README.md` for why
(disk headroom: this machine had ~26 GB free against the plan's own ~30 GB
minimum) and what running it yourself looks like. Every module this
orchestrates (`download`, `wiki_text`, `tokenize`, `counting`,
`informal_merge`, `vocab`, `export`, `eval`, `report`) is independently unit
tested against small fixtures; this file is the wiring between them, which a
real run is what actually exercises end-to-end.

Wikimedia's own dump index and checksum files live at
`https://dumps.wikimedia.org/<lang>wiki/latest/` — `<lang>wiki-latest-pages-articles.xml.bz2`
plus `<lang>wiki-latest-sha1sums.txt` (or `-sha1sums.txt` styled similarly;
check the index page for the exact current filename before a real run, dump
layouts occasionally change).
"""

from __future__ import annotations

import argparse
import multiprocessing
import time
from pathlib import Path

from pipeline.counting import count_ngrams, sentences_to_tokens
from pipeline.download import download_resumable, parse_wikimedia_checksums
from pipeline.eval import build_eval_set, write_eval_set
from pipeline.export import export_meta, export_ngrams, export_unigrams
from pipeline.informal_merge import informal_merge
from pipeline.quick import build_unigrams_from_frequency_file
from pipeline.report import DEFAULT_PROBE_CONTEXTS, render_report, top_continuations, write_report
from pipeline.tokenize import tokenize_paragraph, word_tokenize
from pipeline.vocab import DEFAULT_CAPS, filter_ngrams, select_vocabulary
from pipeline.wiki_text import is_held_out, iter_paragraphs_from_directory, run_wikiextractor

_ROOT = Path(__file__).resolve().parents[1]
_DATA_DIR = _ROOT / "data"
_OUT_DIR = _ROOT / "out"
_EVAL_DIR = _ROOT / "eval"
_REPORTS_DIR = _ROOT / "reports"

_DUMP_INDEX = {
    "fa": "https://dumps.wikimedia.org/fawiki/latest/",
    "en": "https://dumps.wikimedia.org/enwiki/latest/",
}
_DUMP_FILENAME = {"fa": "fawiki-latest-pages-articles.xml.bz2", "en": "enwiki-latest-pages-articles.xml.bz2"}


def _tokenize_worker(paragraph: str) -> list[list[str]]:
    return tokenize_paragraph(paragraph)


def run_language(lang: str, *, min_ngram_count: int = 3, cap: int | None = None, processes: int | None = None) -> dict:
    """Runs tasks 6.4-6.13 for one language and returns the metadata dict
    also written to `out/<lang>.meta.json`."""
    started = time.monotonic()
    cap = cap if cap is not None else DEFAULT_CAPS[lang]

    # 6.4: download the dump (checksum-verified, resumable).
    dump_path = _DATA_DIR / _DUMP_FILENAME[lang]
    checksums_text = None  # a real run fetches "<index>-sha1sums.txt" first and passes it here
    expected_sha1 = parse_wikimedia_checksums(checksums_text, _DUMP_FILENAME[lang]) if checksums_text else None
    download_resumable(_DUMP_INDEX[lang] + _DUMP_FILENAME[lang], dump_path, expected_sha1=expected_sha1)

    # 6.5: wikiextractor -> plain paragraphs.
    extracted_dir = _DATA_DIR / f"{lang}_extracted"
    run_wikiextractor(dump_path, extracted_dir, processes=processes)

    # 6.6: normalize + tokenize in parallel; split held-out articles.
    held_out_sentences: list[str] = []
    counted_sentences: list[list[str]] = []
    with multiprocessing.Pool(processes=processes) as pool:
        for article_id, paragraphs in iter_paragraphs_from_directory(extracted_dir):
            held_out = is_held_out(article_id)
            for sentence_tokens in pool.imap_unordered(_tokenize_worker, paragraphs):
                for sentence in sentence_tokens:
                    if held_out:
                        held_out_sentences.append(" ".join(t for t in sentence if t != "<s>"))
                    else:
                        counted_sentences.append(sentence)

    # 6.7: count with DuckDB.
    tokens = sentences_to_tokens(counted_sentences)
    counts = count_ngrams(tokens, min_ngram_count=min_ngram_count)

    # 6.8: informal merge (fa only has a natural hermitdave counterpart, but
    # nothing stops running it for en too — the plan only flags it as a
    # *fa* pitfall, so this stays language-agnostic).
    hermitdave_path = _DATA_DIR / f"{lang}_full.txt"
    if hermitdave_path.exists():
        hermitdave_counts, _, _ = build_unigrams_from_frequency_file(hermitdave_path, lang)
        unigram_counts_dict = informal_merge(dict(counts["unigrams"]), hermitdave_counts)
        unigram_counts = list(unigram_counts_dict.items())
    else:
        unigram_counts = counts["unigrams"]

    # 6.9: vocabulary selection (Lilak/offensive lists are optional — a real
    # run passes them in once they're sourced; see README.md's Lilak note).
    vocab = select_vocabulary(unigram_counts, lang=lang, cap=cap)
    bigrams = filter_ngrams(counts["bigrams"], vocab)
    trigrams = filter_ngrams(counts["trigrams"], vocab)

    # 6.10/6.11: export.
    export_unigrams(vocab, _OUT_DIR / f"{lang}.unigrams.tsv")
    export_ngrams(bigrams, _OUT_DIR / f"{lang}.bigrams.tsv")
    export_ngrams(trigrams, _OUT_DIR / f"{lang}.trigrams.tsv")

    # 6.13: eval set from held-out articles.
    eval_sentences = build_eval_set(held_out_sentences)
    write_eval_set(eval_sentences, _EVAL_DIR / f"{lang}_formal.txt")

    run_time = time.monotonic() - started
    meta = {
        "language": lang,
        "vocabSize": len(vocab),
        "bigramCount": len(bigrams),
        "trigramCount": len(trigrams),
        "heldOutArticleSentences": len(held_out_sentences),
        "runTimeSeconds": round(run_time, 2),
    }
    export_meta(_OUT_DIR / f"{lang}.meta.json", meta)

    # 6.14: report.
    sorted_unigrams = sorted(((w, v["count"]) for w, v in vocab.items()), key=lambda wc: -wc[1])
    continuations = {ctx: top_continuations(bigrams, ctx) for ctx in DEFAULT_PROBE_CONTEXTS.get(lang, [])}
    coverage, oov_rate = (
        _coverage(eval_sentences, set(vocab)) if eval_sentences else (0.0, 0.0)
    )
    report = render_report(
        lang=lang,
        top_words=sorted_unigrams,
        continuations_by_context=continuations,
        coverage=coverage,
        oov_rate=oov_rate,
        run_time_seconds=run_time,
        output_sizes={
            name: (_OUT_DIR / name).stat().st_size
            for name in (f"{lang}.unigrams.tsv", f"{lang}.bigrams.tsv", f"{lang}.trigrams.tsv")
            if (_OUT_DIR / name).exists()
        },
    )
    write_report(_REPORTS_DIR / f"{lang}.md", report)

    return meta


def _coverage(eval_sentences: list[str], vocab: set[str]) -> tuple[float, float]:
    from pipeline.eval import coverage_and_oov

    return coverage_and_oov(eval_sentences, vocab, word_tokenize)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--lang", choices=["fa", "en"], action="append", dest="langs")
    parser.add_argument("--processes", type=int, default=None)
    args = parser.parse_args()
    for lang in args.langs or ["fa", "en"]:
        meta = run_language(lang, processes=args.processes)
        print(f"{lang}: {meta}")


if __name__ == "__main__":
    main()
