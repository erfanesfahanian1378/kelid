"""Task 6.7: unigram/bigram/trigram counting with DuckDB, via
`LEAD(token, 1/2) OVER (PARTITION BY sentence_id ORDER BY pos)` — bigrams and
trigrams that occur fewer than `min_ngram_count` times are dropped
(`HAVING count >= 3` by default; unigrams are never filtered here, since
vocabulary-level filtering is task 6.9's job, not counting's).
"""

from __future__ import annotations

from collections.abc import Iterable

import duckdb

Token = tuple[int, int, str]  # (sentence_id, pos, token)


def sentences_to_tokens(sentences: Iterable[list[str]], start_sentence_id: int = 0) -> list[Token]:
    """Flattens `[["<s>", "w1", "w2"], ...]` (e.g. `tokenize.tokenize_paragraph`'s
    output) into `(sentence_id, pos, token)` triples ready for `count_ngrams`."""
    tokens: list[Token] = []
    for sentence_id, sentence in enumerate(sentences, start=start_sentence_id):
        for pos, token in enumerate(sentence):
            tokens.append((sentence_id, pos, token))
    return tokens


def count_ngrams(
    tokens: Iterable[Token],
    min_ngram_count: int = 3,
    memory_limit: str = "4GB",
    temp_directory: str | None = None,
) -> dict[str, list[tuple]]:
    """Returns `{"unigrams": [(word, count), ...], "bigrams": [(w1, w2, count), ...],
    "trigrams": [(w1, w2, w3, count), ...]}`, each sorted by count descending
    then lexicographically (a stable, deterministic order for tests and
    reports alike)."""
    con = duckdb.connect(":memory:")
    try:
        con.execute(f"PRAGMA memory_limit='{memory_limit}'")
        if temp_directory:
            con.execute(f"PRAGMA temp_directory='{temp_directory}'")

        con.execute("CREATE TABLE tokens (sentence_id BIGINT, pos INTEGER, token VARCHAR)")
        con.executemany("INSERT INTO tokens VALUES (?, ?, ?)", list(tokens))

        unigrams = con.execute(
            """
            SELECT token AS w1, COUNT(*) AS count
            FROM tokens
            GROUP BY token
            ORDER BY count DESC, w1
            """
        ).fetchall()

        bigrams = con.execute(
            f"""
            WITH pairs AS (
                SELECT token AS w1,
                       LEAD(token, 1) OVER (PARTITION BY sentence_id ORDER BY pos) AS w2
                FROM tokens
            )
            SELECT w1, w2, COUNT(*) AS count
            FROM pairs
            WHERE w2 IS NOT NULL
            GROUP BY w1, w2
            HAVING COUNT(*) >= {min_ngram_count}
            ORDER BY count DESC, w1, w2
            """
        ).fetchall()

        trigrams = con.execute(
            f"""
            WITH triples AS (
                SELECT token AS w1,
                       LEAD(token, 1) OVER (PARTITION BY sentence_id ORDER BY pos) AS w2,
                       LEAD(token, 2) OVER (PARTITION BY sentence_id ORDER BY pos) AS w3
                FROM tokens
            )
            SELECT w1, w2, w3, COUNT(*) AS count
            FROM triples
            WHERE w2 IS NOT NULL AND w3 IS NOT NULL
            GROUP BY w1, w2, w3
            HAVING COUNT(*) >= {min_ngram_count}
            ORDER BY count DESC, w1, w2, w3
            """
        ).fetchall()

        return {"unigrams": unigrams, "bigrams": bigrams, "trigrams": trigrams}
    finally:
        con.close()
