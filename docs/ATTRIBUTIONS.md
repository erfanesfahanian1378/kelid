
## hermitdave/FrequencyWords (quick path, task 6.3)

- **Source:** https://raw.githubusercontent.com/hermitdave/FrequencyWords/master/content/2018/{fa,en}/*_full.txt
- **License:** CC-BY-SA-4.0 (hermitdave/FrequencyWords content license; code is MIT)
- **Used for:** `out/fa.unigrams.tsv`, `out/en.unigrams.tsv` — the quick-path unigram frequency lists Phase 7's prediction lexicon starts from before the full Wikipedia-based pipeline (task 6.4+) replaces them with richer, deduplicated counts.

## Unicode emoji-test.txt + CLDR annotations (task 6.12)

- **Source:** https://unicode.org/Public/emoji/latest/emoji-test.txt, https://raw.githubusercontent.com/unicode-org/cldr/main/common/annotations/{fa,en}.xml, https://raw.githubusercontent.com/unicode-org/cldr/main/common/annotationsDerived/{fa,en}.xml
- **License:** Unicode-3.0 (Unicode, Inc. — see each file's own header)
- **Used for:** `Packages/KelidKit/Sources/EmojiData/emoji.json` (the emoji panel's catalog) and `out/emoji_suggest_{fa,en}.tsv` (keyword -> emoji suggestions).

## Vazirmatn font (task 11.4)

- **Source:** https://github.com/rastikerdar/vazirmatn, release v33.003, `fonts/ttf/Vazirmatn-{Regular,Medium}.ttf`
- **License:** OFL-1.1 (SIL Open Font License) — full text bundled at `Packages/KelidKit/Sources/ThemeKit/Fonts/OFL.txt`
- **Used for:** `Packages/KelidKit/Sources/ThemeKit/Fonts/Vazirmatn-{Regular,Medium}.ttf`, the bundled Persian font offered by the `persianFont = .vazirmatn` appearance setting (§6.8.4), registered once per process via `CTFontManagerRegisterFontsForURL`.
