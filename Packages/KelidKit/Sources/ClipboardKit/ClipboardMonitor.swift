import Foundation
import KelidSettings

/// §6.5.2's capture algorithm. Owns `lastSeenChangeCount` and the
/// guard/sensitive-type/capture-mode/classify/store flow for text and URL
/// content. Image content is hollowed out to `.imageCaptureNeeded(Data)`
/// rather than stored here directly — downsampling and writing files needs
/// `ContainerPaths`, a path-resolution concern this type doesn't have;
/// `ClipboardService` finishes that job and calls `ClipRepository.upsert`
/// itself for images. Doesn't own the 1s timer itself (task 5.4's
/// `KeyboardState` integration drives that) — fed triggers, matching the
/// rest of the codebase's "external clock/timer drives logic" pattern.
@MainActor
public final class ClipboardMonitor {
    public enum CaptureOutcome: Sendable, Equatable {
        /// Text/URL content was classified and stored.
        case captured(Clip)
        /// Image bytes were found and should be downsampled/stored by the
        /// caller.
        case imageCaptureNeeded(Data)
        /// `.onTap` mode: content exists but reading it is deferred to a
        /// user-initiated tap (`readNow`).
        case pendingTap
        /// A guard failed (Full Access off, disabled, `captureMode == .off`,
        /// or incognito) — nothing happened.
        case blocked
        /// `changeCount` hasn't changed since the last check.
        case noChange
        /// `skipSensitive` is on and the pasteboard carries a sensitive type.
        case skippedSensitiveType
        /// Content was read but classified as skip-worthy (empty, an
        /// ignored pattern, or `otpHandling == .skip`), or storing it failed.
        case classifiedAsSkip
    }

    private let pasteboard: PasteboardClient
    private let repository: ClipRepository
    private var lastSeenChangeCount: Int

    public init(pasteboard: PasteboardClient, repository: ClipRepository, initialChangeCount: Int? = nil) {
        self.pasteboard = pasteboard
        self.repository = repository
        lastSeenChangeCount = initialChangeCount ?? pasteboard.changeCount
    }

    /// Call immediately after the keyboard itself writes to the pasteboard
    /// (Copy/Cut, image-clip tap) so that write isn't captured again on the
    /// next check (§6.5.2's own pitfall).
    public func noteOwnWrite() {
        lastSeenChangeCount = pasteboard.changeCount
    }

    /// §6.5.2's full guard chain, then (for `.auto`) the classify-and-store
    /// step. For `.onTap`, returns `.pendingTap` without reading content.
    @discardableResult
    public func check(fullAccess: Bool, incognito: Bool, settings: ClipboardSettings, now: Date) async -> CaptureOutcome {
        guard fullAccess, settings.enabled, settings.captureMode != .off, !incognito else { return .blocked }

        let currentChangeCount = pasteboard.changeCount
        guard currentChangeCount != lastSeenChangeCount else { return .noChange }
        lastSeenChangeCount = currentChangeCount

        if settings.skipSensitive, ClipClassifier.hasSensitiveType(pasteboard.typeIdentifiers) {
            return .skippedSensitiveType
        }

        switch settings.captureMode {
        case .off:
            return .blocked
        case .onTap:
            return .pendingTap
        case .auto:
            return await readAndStore(settings: settings, now: now)
        }
    }

    /// User-initiated read (the `.onTap` chip was tapped, or the edit
    /// panel's Paste) — reads content regardless of `changeCount`.
    public func readNow(settings: ClipboardSettings, now: Date) async -> CaptureOutcome {
        await readAndStore(settings: settings, now: now)
    }

    private func readAndStore(settings: ClipboardSettings, now: Date) async -> CaptureOutcome {
        if pasteboard.hasImages, settings.captureImages, let data = pasteboard.loadImageData() {
            return .imageCaptureNeeded(data)
        }
        guard let text = pasteboard.string else { return .classifiedAsSkip }
        guard let draft = ClipClassifier.classifyText(text, settings: settings, source: .capture, now: now) else {
            return .classifiedAsSkip
        }
        guard let clip = try? await repository.upsert(draft) else { return .classifiedAsSkip }
        return .captured(clip)
    }
}
