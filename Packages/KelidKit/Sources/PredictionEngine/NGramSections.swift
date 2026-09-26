import Foundation

/// Builds §6.7.2's `BIDX`/`BENT`/`TIDX`/`TENT` sections (task 8.1) — split
/// out of `KLMWriter` purely for readability; behaviorally this is still
/// part of the writer.
enum NGramSections {
    struct Built {
        let bidx: [UInt8]
        let bent: [UInt8]
        let tidx: [UInt8]
        let tent: [UInt8]
    }

    static func build(
        bigrams: [BigramEntry],
        trigrams: [TrigramEntry],
        surfaceToID: [String: UInt32],
        rawCountByID: [UInt32: UInt64],
        options: KLMBuildOptions
    ) -> Built {
        let (bidx, bent, bigramCountByPair) = buildBigrams(
            bigrams: bigrams,
            surfaceToID: surfaceToID,
            rawCountByID: rawCountByID,
            options: options
        )
        let (tidx, tent) = buildTrigrams(
            trigrams: trigrams,
            surfaceToID: surfaceToID,
            bigramCountByPair: bigramCountByPair,
            options: options
        )
        return Built(bidx: bidx, bent: bent, tidx: tidx, tent: tent)
    }

    /// `pairKey` packs two word ids into one `UInt64` for use as a
    /// dictionary key (`ctx1 << 32 | ctx2`, or `ctx | next` for bigrams).
    private static func pairKey(_ a: UInt32, _ b: UInt32) -> UInt64 {
        (UInt64(a) << 32) | UInt64(b)
    }

    private static func buildBigrams(
        bigrams: [BigramEntry],
        surfaceToID: [String: UInt32],
        rawCountByID: [UInt32: UInt64],
        options: KLMBuildOptions
    ) -> (bidx: [UInt8], bent: [UInt8], bigramCountByPair: [UInt64: UInt64]) {
        guard !bigrams.isEmpty else { return ([], [], [:]) }

        struct Resolved { let ctx: UInt32; let next: UInt32; let count: UInt64 }

        var resolved: [Resolved] = []
        var bigramCountByPair: [UInt64: UInt64] = [:]
        for entry in bigrams {
            guard let w1 = surfaceToID[entry.w1], let w2 = surfaceToID[entry.w2] else { continue }
            // Recorded before the `bigramMinCount` filter below — the
            // trigram-context threshold (`c(w1 w2) ≥ 10`) needs the real
            // count even for pairs too rare to earn their own BENT entries.
            bigramCountByPair[pairKey(w1, w2), default: 0] += entry.count
            guard entry.count >= options.bigramMinCount else { continue }
            resolved.append(Resolved(ctx: w1, next: w2, count: entry.count))
        }

        // Per-context top-K (§6.7.2: 32 for bigrams).
        var byContext: [UInt32: [Resolved]] = [:]
        for r in resolved {
            byContext[r.ctx, default: []].append(r)
        }
        var trimmed: [Resolved] = []
        for group in byContext.values {
            let sortedGroup = group.sorted { $0.count == $1.count ? $0.next < $1.next : $0.count > $1.count }
            trimmed.append(contentsOf: sortedGroup.prefix(options.bigramTopK))
        }

        // Global cap across every context combined.
        if trimmed.count > options.maxBigramEntries {
            trimmed = Array(trimmed.sorted { $0.count > $1.count }.prefix(options.maxBigramEntries))
        }

        // Quantized `P(w2|w1) = count(w1,w2) / count(w1)`, then re-grouped
        // (the cap above may have dropped whole contexts down to zero
        // entries) and sorted for the final layout.
        var byContextFinal: [UInt32: [(next: UInt32, score: UInt8)]] = [:]
        for r in trimmed {
            let ctxCount = rawCountByID[r.ctx] ?? 0
            let probability = ctxCount > 0 ? Double(r.count) / Double(ctxCount) : 0
            let log10P = log10(max(probability, .leastNormalMagnitude))
            let score = KLMFormat.quantize(log10P: log10P, minLog10: options.biMinLog10)
            byContextFinal[r.ctx, default: []].append((r.next, score))
        }
        for ctx in byContextFinal.keys {
            byContextFinal[ctx]?.sort { $0.score == $1.score ? $0.next < $1.next : $0.score > $1.score }
        }

        var bidx = ByteWriter()
        var bent = ByteWriter()
        for ctx in byContextFinal.keys.sorted() {
            guard let entries = byContextFinal[ctx], !entries.isEmpty else { continue }
            bidx.u32(ctx)
            bidx.u32(UInt32(bent.count / 8)) // `start`: entry index into BENT
            bidx.u16(UInt16(entries.count))
            bidx.u16(0) // pad
            for entry in entries {
                bent.u32(entry.next)
                bent.u8(entry.score)
                bent.raw([0, 0, 0])
            }
        }
        return (bidx.bytes, bent.bytes, bigramCountByPair)
    }

    private static func buildTrigrams(
        trigrams: [TrigramEntry],
        surfaceToID: [String: UInt32],
        bigramCountByPair: [UInt64: UInt64],
        options: KLMBuildOptions
    ) -> (tidx: [UInt8], tent: [UInt8]) {
        guard !trigrams.isEmpty else { return ([], []) }

        struct Resolved { let ctx1: UInt32; let ctx2: UInt32; let next: UInt32; let count: UInt64 }

        var resolved: [Resolved] = []
        for entry in trigrams {
            guard let w1 = surfaceToID[entry.w1], let w2 = surfaceToID[entry.w2], let w3 = surfaceToID[entry.w3] else { continue }
            guard entry.count >= options.trigramMinCount else { continue }
            let contextBigramCount = bigramCountByPair[pairKey(w1, w2)] ?? 0
            guard contextBigramCount >= options.trigramContextMinBigramCount else { continue }
            resolved.append(Resolved(ctx1: w1, ctx2: w2, next: w3, count: entry.count))
        }

        var byContext: [UInt64: [Resolved]] = [:]
        for r in resolved {
            byContext[pairKey(r.ctx1, r.ctx2), default: []].append(r)
        }
        var trimmed: [Resolved] = []
        for group in byContext.values {
            let sortedGroup = group.sorted { $0.count == $1.count ? $0.next < $1.next : $0.count > $1.count }
            trimmed.append(contentsOf: sortedGroup.prefix(options.trigramTopK))
        }
        if trimmed.count > options.maxTrigramEntries {
            trimmed = Array(trimmed.sorted { $0.count > $1.count }.prefix(options.maxTrigramEntries))
        }

        var byContextFinal: [UInt64: (ctx1: UInt32, ctx2: UInt32, entries: [(next: UInt32, score: UInt8)])] = [:]
        for r in trimmed {
            let key = pairKey(r.ctx1, r.ctx2)
            let contextCount = bigramCountByPair[key] ?? 0
            let probability = contextCount > 0 ? Double(r.count) / Double(contextCount) : 0
            let log10P = log10(max(probability, .leastNormalMagnitude))
            let score = KLMFormat.quantize(log10P: log10P, minLog10: options.triMinLog10)
            byContextFinal[key, default: (r.ctx1, r.ctx2, [])].entries.append((r.next, score))
        }
        for key in byContextFinal.keys {
            byContextFinal[key]?.entries.sort { $0.score == $1.score ? $0.next < $1.next : $0.score > $1.score }
        }

        var tidx = ByteWriter()
        var tent = ByteWriter()
        for key in byContextFinal.keys.sorted() {
            guard let group = byContextFinal[key], !group.entries.isEmpty else { continue }
            tidx.u32(group.ctx1)
            tidx.u32(group.ctx2)
            tidx.u32(UInt32(tent.count / 8)) // `start`: entry index into TENT
            tidx.u16(UInt16(group.entries.count))
            tidx.u16(0) // pad
            for entry in group.entries {
                tent.u32(entry.next)
                tent.u8(entry.score)
                tent.raw([0, 0, 0])
            }
        }
        return (tidx.bytes, tent.bytes)
    }
}
