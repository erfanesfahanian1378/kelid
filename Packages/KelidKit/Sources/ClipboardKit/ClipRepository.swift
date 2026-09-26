import Foundation
import GRDB
import KelidCore
import KelidSettings
import KelidStorage
import PersianText

public enum ClipFilter: Sendable, Equatable {
    case recent
    case pinned
}

/// Task 5.1: clip storage operations over `DatabaseManager`. Everything is
/// `async`; every write posts `.clipsChanged` (§6.5.4) so other
/// processes/observers (the panel, another process's monitor) pick up the
/// change without polling.
public actor ClipRepository {
    private let database: DatabaseManager
    private let darwinNotifier: DarwinNotifier
    private let appGroupIdentifier: String?
    private let clock: Clock

    public init(
        database: DatabaseManager,
        darwinNotifier: DarwinNotifier = .shared,
        appGroupIdentifier: String? = AppGroup.identifier,
        clock: Clock = SystemClock()
    ) {
        self.database = database
        self.darwinNotifier = darwinNotifier
        self.appGroupIdentifier = appGroupIdentifier
        self.clock = clock
    }

    /// §6.5.4's dedupe: a clip with an existing `contentHash` bumps
    /// `lastCopiedAt`/`copyCount` (moving it to the top) instead of
    /// inserting a new row.
    @discardableResult
    public func upsert(_ draft: ClipDraft) async throws -> Clip {
        let now = clock.now()
        let result = try await database.write { db -> Clip in
            if var existing = try Clip.filter(Column("contentHash") == draft.contentHash).fetchOne(db) {
                existing.lastCopiedAt = now
                existing.copyCount += 1
                existing.text = draft.text
                existing.searchKey = draft.searchKey
                existing.isSensitive = draft.isSensitive
                existing.expiresAt = draft.expiresAt
                try existing.update(db)
                return existing
            }
            var clip = Clip(
                kind: draft.kind,
                text: draft.text,
                searchKey: draft.searchKey,
                imageFile: draft.imageFile,
                thumbFile: draft.thumbFile,
                contentHash: draft.contentHash,
                charCount: draft.charCount,
                isTruncated: draft.isTruncated,
                createdAt: now,
                lastCopiedAt: now,
                isSensitive: draft.isSensitive,
                expiresAt: draft.expiresAt,
                source: draft.source
            )
            try clip.insert(db)
            return clip
        }
        notifyChanged()
        return result
    }

    public func page(filter: ClipFilter, offset: Int, limit: Int = 50) async throws -> [Clip] {
        try await database.read { db in
            switch filter {
            case .recent:
                try Clip
                    .filter(Column("isPinned") == false)
                    .order(Column("lastCopiedAt").desc)
                    .limit(limit, offset: offset)
                    .fetchAll(db)
            case .pinned:
                try Clip
                    .filter(Column("isPinned") == true)
                    .order(Column("pinnedOrder").desc)
                    .limit(limit, offset: offset)
                    .fetchAll(db)
            }
        }
    }

    /// §6.6.4's `searchKey`, `LIKE %q%`, pinned first.
    public func search(query: String, limit: Int = 50) async throws -> [Clip] {
        let likePattern = "%\(PersianNormalization.searchKey(query))%"
        return try await database.read { db in
            try Clip
                .filter(Column("searchKey").like(likePattern))
                .order(Column("isPinned").desc, Column("lastCopiedAt").desc)
                .limit(limit)
                .fetchAll(db)
        }
    }

    public func pin(id: Int64) async throws {
        try await database.write { db in
            let maxOrder = try Double.fetchOne(db, sql: "SELECT MAX(pinnedOrder) FROM clip WHERE isPinned = 1") ?? 0
            try db.execute(sql: "UPDATE clip SET isPinned = 1, pinnedOrder = ? WHERE id = ?", arguments: [maxOrder + 1, id])
        }
        notifyChanged()
    }

    public func unpin(id: Int64) async throws {
        try await database.write { db in
            try db.execute(sql: "UPDATE clip SET isPinned = 0, pinnedOrder = NULL WHERE id = ?", arguments: [id])
        }
        notifyChanged()
    }

    /// `ids` in display order — the first gets the highest `pinnedOrder`.
    public func reorderPinned(ids: [Int64]) async throws {
        try await database.write { db in
            for (index, id) in ids.enumerated() {
                try db.execute(
                    sql: "UPDATE clip SET pinnedOrder = ? WHERE id = ?",
                    arguments: [Double(ids.count - index), id]
                )
            }
        }
        notifyChanged()
    }

    /// Returns the removed rows' image/thumbnail file paths, for the caller
    /// (`ClipboardService`) to delete from disk.
    @discardableResult
    public func delete(ids: [Int64]) async throws -> [String] {
        let removedFiles = try await database.write { db -> [String] in
            let removed = try Clip.fetchAll(db, keys: ids)
            _ = try Clip.deleteAll(db, keys: ids)
            return removed.compactMap(\.imageFile) + removed.compactMap(\.thumbFile)
        }
        notifyChanged()
        return removedFiles
    }

    @discardableResult
    public func deleteAll(keepPinned: Bool) async throws -> [String] {
        let removedFiles = try await database.write { db -> [String] in
            let request = keepPinned ? Clip.filter(Column("isPinned") == false) : Clip.all()
            let removed = try request.fetchAll(db)
            _ = try request.deleteAll(db)
            return removed.compactMap(\.imageFile) + removed.compactMap(\.thumbFile)
        }
        notifyChanged()
        return removedFiles
    }

    public func markUsed(id: Int64) async throws {
        let now = clock.now()
        try await database.write { db in
            try db.execute(
                sql: "UPDATE clip SET lastUsedAt = ?, useCount = useCount + 1 WHERE id = ?",
                arguments: [now.timeIntervalSince1970, id]
            )
        }
        notifyChanged()
    }

    /// §6.5.4's limits, run on appear (throttled by the caller to at most
    /// once per 10 min) and after every insert: expired rows, then rows
    /// older than `retentionDays`, then the oldest non-pinned rows beyond
    /// `maxItems`. Pinned rows are never auto-deleted. Returns removed
    /// image/thumbnail file paths for cleanup.
    @discardableResult
    public func enforceLimits(settings: ClipboardSettings, now: Date) async throws -> [String] {
        let removedFiles = try await database.write { db -> [String] in
            var files: [String] = []

            let expiredRequest = Clip.filter(Column("expiresAt") != nil && Column("expiresAt") < now.timeIntervalSince1970)
            let expired = try expiredRequest.fetchAll(db)
            files += expired.compactMap(\.imageFile) + expired.compactMap(\.thumbFile)
            _ = try expiredRequest.deleteAll(db)

            if let retentionDays = settings.retentionDays {
                let cutoff = now.timeIntervalSince1970 - Double(retentionDays) * 86400
                let byAgeRequest = Clip.filter(Column("isPinned") == false && Column("lastCopiedAt") < cutoff)
                let byAge = try byAgeRequest.fetchAll(db)
                files += byAge.compactMap(\.imageFile) + byAge.compactMap(\.thumbFile)
                _ = try byAgeRequest.deleteAll(db)
            }

            let nonPinnedCount = try Clip.filter(Column("isPinned") == false).fetchCount(db)
            if nonPinnedCount > settings.maxItems {
                let overflow = nonPinnedCount - settings.maxItems
                let oldest = try Clip
                    .filter(Column("isPinned") == false)
                    .order(Column("lastCopiedAt").asc)
                    .limit(overflow)
                    .fetchAll(db)
                files += oldest.compactMap(\.imageFile) + oldest.compactMap(\.thumbFile)
                _ = try Clip.deleteAll(db, keys: oldest.compactMap(\.id))
            }
            return files
        }
        if !removedFiles.isEmpty {
            notifyChanged()
        }
        return removedFiles
    }

    public func imageFiles(for id: Int64) async throws -> (image: String?, thumb: String?) {
        try await database.read { db in
            guard let clip = try Clip.fetchOne(db, key: id) else { return (nil, nil) }
            return (clip.imageFile, clip.thumbFile)
        }
    }

    private func notifyChanged() {
        darwinNotifier.post(.clipsChanged, appGroupIdentifier: appGroupIdentifier)
    }
}
