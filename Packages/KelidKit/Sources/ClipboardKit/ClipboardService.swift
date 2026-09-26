import Foundation
import KelidCore
import KelidSettings
import PersianText

/// Task 5.2's façade — the single clipboard entry point the keyboard UI
/// layer talks to. Owns the `PasteboardClient`, `ClipboardMonitor` and
/// `ClipRepository` together, and finishes the one thing `ClipboardMonitor`
/// can't do alone: downsampling and writing image files (§6.5.8, needs
/// `ContainerPaths`).
@MainActor
public final class ClipboardService {
    public let repository: ClipRepository
    public let pasteboard: PasteboardClient
    private let monitor: ClipboardMonitor
    private let containerPaths: ContainerPaths
    private let clock: Clock

    public init(pasteboard: PasteboardClient, repository: ClipRepository, containerPaths: ContainerPaths, clock: Clock = SystemClock()) {
        self.pasteboard = pasteboard
        self.repository = repository
        monitor = ClipboardMonitor(pasteboard: pasteboard, repository: repository)
        self.containerPaths = containerPaths
        self.clock = clock
    }

    // MARK: - Capture (task 5.4, §6.5.2)

    @discardableResult
    public func checkForCapture(fullAccess: Bool, incognito: Bool, settings: ClipboardSettings) async -> ClipboardMonitor.CaptureOutcome {
        let outcome = await monitor.check(fullAccess: fullAccess, incognito: incognito, settings: settings, now: clock.now())
        return await finishIfImageCapture(outcome)
    }

    /// `.onTap` mode's deferred read, or the edit panel's Paste-into-history
    /// case — reads content regardless of `changeCount`.
    @discardableResult
    public func readPendingTap(settings: ClipboardSettings) async -> ClipboardMonitor.CaptureOutcome {
        let outcome = await monitor.readNow(settings: settings, now: clock.now())
        return await finishIfImageCapture(outcome)
    }

    private func finishIfImageCapture(_ outcome: ClipboardMonitor.CaptureOutcome) async -> ClipboardMonitor.CaptureOutcome {
        guard case let .imageCaptureNeeded(data) = outcome else { return outcome }
        guard let clip = await captureImage(data: data) else { return .classifiedAsSkip }
        return .captured(clip)
    }

    private func captureImage(data: Data) async -> Clip? {
        guard let result = await Task.detached(priority: .utility, operation: { ImageDownsampler.downsample(data: data) }).value else {
            return nil
        }
        let hash = ClipClassifier.sha256Hex(data)
        let ext = result.isPNG ? "png" : "jpg"
        let imageFilename = "\(UUID().uuidString).\(ext)"
        let thumbFilename = "\(UUID().uuidString)_thumb.\(ext)"
        do {
            try FileManager.default.createDirectory(at: containerPaths.clipImagesDirectoryURL, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: containerPaths.clipThumbsDirectoryURL, withIntermediateDirectories: true)
            try result.imageData.write(to: containerPaths.clipImagesDirectoryURL.appendingPathComponent(imageFilename))
            try result.thumbnailData.write(to: containerPaths.clipThumbsDirectoryURL.appendingPathComponent(thumbFilename))
        } catch {
            return nil
        }
        let draft = ClipClassifier.draftForImage(hash: hash, imageFile: imageFilename, thumbFile: thumbFilename, source: .capture)
        return try? await repository.upsert(draft)
    }

    // MARK: - Insert (§6.5.5) / edit panel Copy (§6.4.9)

    /// Writes an image clip's full-size file back to the system pasteboard
    /// (§6.5.8: keyboards can't insert images, C4) and marks the write so
    /// the monitor doesn't recapture it.
    public func copyImageToPasteboard(_ clip: Clip) {
        guard let imageFile = clip.imageFile else { return }
        let url = containerPaths.clipImagesDirectoryURL.appendingPathComponent(imageFile)
        guard let data = try? Data(contentsOf: url) else { return }
        pasteboard.setImageData(data, uti: imageFile.hasSuffix(".png") ? "public.png" : "public.jpeg")
        monitor.noteOwnWrite()
    }

    /// §6.4.9's Copy/Cut: writes to the pasteboard and stores a
    /// `.keyboard`-source clip, marking the write so it isn't recaptured.
    @discardableResult
    public func copyToPasteboard(_ text: String) async -> Clip? {
        pasteboard.setString(text)
        monitor.noteOwnWrite()
        let draft = ClipDraft(
            kind: ClipClassifier.detectURL(text) != nil ? .url : .text,
            text: text,
            searchKey: PersianNormalization.searchKey(text),
            contentHash: ClipClassifier.sha256Hex(PersianNormalization.canonical(text)),
            charCount: text.count,
            source: .keyboard
        )
        return try? await repository.upsert(draft)
    }

    /// §6.4.9's Paste: a user-initiated pasteboard read (never silently
    /// polled). Returns `nil` if there's no string content.
    public func pasteboardString() -> String? {
        pasteboard.string
    }

    public func markUsed(id: Int64) async {
        try? await repository.markUsed(id: id)
    }

    // MARK: - Retention (task 5.13) and deletion (with file cleanup)

    /// Runs `ClipRepository.enforceLimits` at most once per 10 minutes —
    /// pass back whatever this returns as `lastEnforcedAt` next time.
    public func enforceLimitsIfDue(settings: ClipboardSettings, lastEnforcedAt: Date?) async -> Date? {
        let now = clock.now()
        if let lastEnforcedAt, now.timeIntervalSince(lastEnforcedAt) < 600 {
            return lastEnforcedAt
        }
        let removedFiles = await (try? repository.enforceLimits(settings: settings, now: now)) ?? []
        deleteFiles(removedFiles)
        return now
    }

    public func delete(ids: [Int64]) async {
        let removedFiles = await (try? repository.delete(ids: ids)) ?? []
        deleteFiles(removedFiles)
    }

    public func deleteAll(keepPinned: Bool) async {
        let removedFiles = await (try? repository.deleteAll(keepPinned: keepPinned)) ?? []
        deleteFiles(removedFiles)
    }

    /// Filenames may belong to either directory — removal is attempted in
    /// both and silently no-ops wherever the file doesn't exist.
    private func deleteFiles(_ filenames: [String]) {
        guard !filenames.isEmpty else { return }
        for filename in filenames {
            try? FileManager.default.removeItem(at: containerPaths.clipImagesDirectoryURL.appendingPathComponent(filename))
            try? FileManager.default.removeItem(at: containerPaths.clipThumbsDirectoryURL.appendingPathComponent(filename))
        }
    }
}
