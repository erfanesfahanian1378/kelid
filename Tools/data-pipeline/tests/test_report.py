from __future__ import annotations

from pipeline.report import render_report, top_continuations


def test_top_continuations_filters_by_context_and_caps_at_limit() -> None:
    bigrams = [
        ("<s>", "من", 100),
        ("<s>", "او", 50),
        ("<s>", "تو", 10),
        ("من", "کتاب", 5),
    ]
    assert top_continuations(bigrams, "<s>", limit=2) == [("من", 100), ("او", 50)]


def test_render_report_includes_all_sections() -> None:
    content = render_report(
        lang="fa",
        top_words=[("کتاب", 100), ("من", 90)],
        continuations_by_context={"<s>": [("من", 100)]},
        coverage=0.95,
        oov_rate=0.05,
        run_time_seconds=12.5,
        output_sizes={"fa.unigrams.tsv": 2048},
    )
    assert "# fa language data report" in content
    assert "کتاب" in content
    assert "95.00%" in content
    assert "5.00%" in content
    assert "12.5s" in content
    assert "2.0 KB" in content
