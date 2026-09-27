#if canImport(UIKit)
    import ClipboardKit
    import Foundation
    import InputEngine
    import KelidSettings
    import UIKit

    /// Clipboard capture/panel (tasks 5.4–5.7, 5.9–5.13) — split out of
    /// `KeyboardController.swift` itself purely to keep that type's body
    /// under SwiftLint's `type_body_length`; behaviorally this is still
    /// part of `KeyboardController`, just declared in a second file.
    extension KeyboardController {
        /// Bridges `KeyboardState.clipChip`/`.toast` (plain `@Observable`
        /// properties UIKit doesn't watch on its own) to the toolbar's
        /// actual visible label — `withObservationTracking` re-registers
        /// itself on every change, the standard way to observe an
        /// `@Observable` object outside SwiftUI's own view-body tracking
        /// (same pattern as `+ResizeMode.swift`'s `observeResizeSession`).
        /// Called once from `init`.
        func observeToolbarText() {
            withObservationTracking {
                _ = state.clipChip
                _ = state.toast
            } onChange: { [weak self] in
                Task { @MainActor in
                    guard let self else { return }
                    self.rootView.toolbarStrip.setText(self.state.clipChip ?? self.state.toast)
                    self.observeToolbarText()
                }
            }
        }

        // MARK: - Capture polling (task 5.4, §6.5.2)

        /// Selector-based, not the closure-based `Timer` API — same
        /// `@Sendable`/actor-isolation reasoning as the backspace-repeat
        /// timer.
        public func startClipboardPolling() {
            stopClipboardPolling()
            clipboardPollTimer = Timer.scheduledTimer(
                timeInterval: 1.0, target: self, selector: #selector(handleClipboardPollTick), userInfo: nil, repeats: true
            )
            performClipboardCheck()
        }

        public func stopClipboardPolling() {
            clipboardPollTimer?.invalidate()
            clipboardPollTimer = nil
        }

        @objc fileprivate func handleClipboardPollTick() {
            guard settings.clipboard.pollWhileVisible else { return }
            performClipboardCheck()
        }

        private func performClipboardCheck() {
            guard settings.clipboard.enabled else { return }
            Task { [weak self] in
                guard let self else { return }
                let outcome = await clipboardService.checkForCapture(
                    fullAccess: hasFullAccess, incognito: state.incognito, settings: settings.clipboard
                )
                applyCaptureOutcome(outcome)
                lastEnforceLimitsAt = await clipboardService.enforceLimitsIfDue(
                    settings: settings.clipboard, lastEnforcedAt: lastEnforceLimitsAt
                )
            }
        }

        private func applyCaptureOutcome(_ outcome: ClipboardMonitor.CaptureOutcome) {
            switch outcome {
            case let .captured(clip):
                lastCapturedClip = clip
                showClipChip(for: clip)
            case .pendingTap:
                lastCapturedClip = nil
                if settings.clipboard.showChip, state.mode == .typing {
                    state.clipChip = "📋 Paste copied item"
                }
            case .imageCaptureNeeded, .blocked, .noChange, .skippedSensitiveType, .classifiedAsSkip:
                break
            }
        }

        /// §6.5.7: first 24 characters, masked for sensitive clips.
        private func showClipChip(for clip: Clip) {
            guard settings.clipboard.showChip, state.mode == .typing else { return }
            let preview = clip.isSensitive ? "••••" : String((clip.text ?? "🖼 Image").prefix(24))
            state.clipChip = "📋 \(preview)"
        }

        // MARK: - Clip chip tap (§6.5.7)

        public func tapClipChip() {
            guard state.clipChip != nil else { return }
            state.clipChip = nil
            Task { [weak self] in
                guard let self else { return }
                if let clip = lastCapturedClip {
                    await insertClip(clip)
                } else if case let .captured(clip) = await clipboardService.readPendingTap(settings: settings.clipboard) {
                    await insertClip(clip)
                }
            }
        }

        public func dismissClipChip() {
            state.clipChip = nil
        }

        /// The toolbar's dedicated "save clipboard now" button (added after
        /// real device testing showed the automatic/on-tap-chip capture
        /// path is easy to miss) — a direct tap on this button is itself
        /// the user gesture iOS's pasteboard-read privacy protection
        /// requires, so it reads content immediately rather than waiting on
        /// the 1s poll or a chip the user might not notice in time.
        public func quickCaptureClipboard() {
            Task { [weak self] in
                guard let self else { return }
                switch await performQuickCapture() {
                case let .captured(clip):
                    showClipChip(for: clip)
                case .blocked:
                    state.toast = hasFullAccess ? "Clipboard capture is off" : "Turn on Full Access to save clips"
                case .classifiedAsSkip, .skippedSensitiveType:
                    state.toast = "Nothing new to save"
                case .imageCaptureNeeded, .noChange, .pendingTap:
                    break
                }
            }
        }

        /// Shared by `quickCaptureClipboard()` and `presentClipboardPanel()`
        /// — both are triggered by a direct toolbar tap, so both can read
        /// the pasteboard's actual content immediately (`readPendingTap`
        /// ignores `changeCount`, unlike the background poll's `.onTap`
        /// deferral) rather than depending on the poll/chip having already
        /// caught it.
        @discardableResult
        private func performQuickCapture() async -> ClipboardMonitor.CaptureOutcome {
            guard hasFullAccess, settings.clipboard.enabled, settings.clipboard.captureMode != .off, !state.incognito else {
                return .blocked
            }
            return await clipboardService.readPendingTap(settings: settings.clipboard)
        }

        // MARK: - Insert (§6.5.5)

        private func insertClip(_ clip: Clip) async {
            switch clip.kind {
            case .text, .url:
                guard let text = clip.text else { return }
                perform(.insertClip(text))
            case .image:
                clipboardService.copyImageToPasteboard(clip)
                state.toast = "Image copied: long-press the text field and choose Paste"
            }
            if let id = clip.id {
                await clipboardService.markUsed(id: id)
            }
            if settings.clipboard.tapAction == .insertAndClose, state.mode == .clipboard {
                dismissClipboardPanel()
            }
        }

        // MARK: - Clipboard panel (tasks 5.5/5.6/5.12)

        public func toggleClipboardPanel() {
            if state.mode == .clipboard {
                dismissClipboardPanel()
            } else {
                presentClipboardPanel()
            }
        }

        private func presentClipboardPanel() {
            state.mode = .clipboard
            let model = ClipboardPanelModel(hasFullAccess: hasFullAccess, isCapturePaused: settings.clipboard.captureMode == .off)
            wireClipboardPanel(model)
            Task { [weak self] in
                guard let self else { return }
                // Opening the panel is itself a direct tap, so it doubles as
                // a manual "grab whatever's on the clipboard right now"
                // action (same reasoning as `quickCaptureClipboard()`) —
                // runs before the reload below so a freshly-grabbed clip
                // shows up in Recent immediately.
                await performQuickCapture()
                await reloadClipboardPanel(model)
            }
            onPresentClipboardPanel?(model)
        }

        func dismissClipboardPanel() {
            guard state.mode == .clipboard else { return }
            state.mode = .typing
            onDismissClipboardPanel?()
        }

        private func wireClipboardPanel(_ model: ClipboardPanelModel) {
            model.onTapClip = { [weak self, weak model] clip in
                Task {
                    guard let self, let model else { return }
                    await self.insertClip(clip)
                    await self.reloadClipboardPanel(model)
                }
            }
            model.onTogglePin = { [weak self, weak model] clip in
                Task {
                    guard let self, let model, let id = clip.id else { return }
                    if clip.isPinned {
                        try? await self.clipboardService.repository.unpin(id: id)
                    } else {
                        try? await self.clipboardService.repository.pin(id: id)
                    }
                    await self.reloadClipboardPanel(model)
                }
            }
            model.onDelete = { [weak self, weak model] clip in
                Task {
                    guard let self, let model, let id = clip.id else { return }
                    await self.clipboardService.delete(ids: [id])
                    await self.reloadClipboardPanel(model)
                }
            }
            model.onClearAll = { [weak self, weak model] in
                Task {
                    guard let self, let model else { return }
                    await self.clipboardService.deleteAll(keepPinned: true)
                    await self.reloadClipboardPanel(model)
                }
            }
            model.onTogglePause = { [weak self, weak model] in
                guard let self, let model else { return }
                let newMode: ClipboardCaptureMode = model.isCapturePaused ? .auto : .off
                model.isCapturePaused.toggle()
                onRequestSettingsChange? { $0.clipboard.captureMode = newMode }
            }
            model.onSearchQueryChanged = { [weak self, weak model] query in
                Task {
                    guard let self, let model else { return }
                    model.searchQuery = query
                    model.isSearching = !query.isEmpty
                    model.searchResults = await query.isEmpty ? [] : ((try? self.clipboardService.repository.search(query: query)) ?? [])
                }
            }
            model.onOpenFullAccessSettings = { [weak self] in
                // The keyboard can't open Settings itself (C15 — no
                // launching other apps); dismissing at least gets the panel
                // out of the way so the user can switch to Settings.
                self?.onDismissKeyboard?()
            }
            model.onTapSnippet = { [weak self] snippet in
                self?.perform(.insertClip(snippet.text))
                Task { [weak self] in
                    guard let self, let id = snippet.id else { return }
                    try? await snippetRepository.markUsed(id: id)
                }
            }
            model.onDone = { [weak self] in
                self?.dismissClipboardPanel()
            }
        }

        private func reloadClipboardPanel(_ model: ClipboardPanelModel) async {
            model.revealedIDs.removeAll()
            model.recentClips = await (try? clipboardService.repository.page(filter: .recent, offset: 0)) ?? []
            model.pinnedClips = await (try? clipboardService.repository.page(filter: .pinned, offset: 0)) ?? []
            model.snippetGroups = await (try? snippetRepository.listAllGroupedByFolder()) ?? []
        }

        // MARK: - Edit panel (task 5.9/5.10)

        public func toggleEditPanel() {
            if state.mode == .edit {
                dismissEditPanel()
            } else {
                presentEditPanel()
            }
        }

        private func presentEditPanel() {
            state.mode = .edit
            let doc = documentProvider()
            let model = EditPanelModel(
                hasSelection: !(doc.selectedText ?? "").isEmpty,
                hasFullAccess: hasFullAccess,
                canUndo: inputProcessor.hasUndo
            )
            wireEditPanel(model)
            onPresentEditPanel?(model)
        }

        private func dismissEditPanel() {
            guard state.mode == .edit else { return }
            state.mode = .typing
            onDismissEditPanel?()
        }

        private func wireEditPanel(_ model: EditPanelModel) {
            model.onMoveCursor = { [weak self] direction in
                self?.perform(.moveCursor(direction == .forward ? 1 : -1))
            }
            model.onMoveCursorWord = { [weak self] direction in
                self?.perform(.moveCursorWord(direction))
            }
            model.onMoveCursorLine = { [weak self] direction in
                self?.perform(.moveCursorLine(direction))
            }
            model.onCopy = { [weak self, weak model] in
                guard let self, let model else { return }
                perform(.copySelection)
                refreshEditPanel(model)
            }
            model.onCut = { [weak self, weak model] in
                guard let self, let model else { return }
                perform(.cutSelection)
                refreshEditPanel(model)
            }
            model.onPaste = { [weak self] in
                self?.perform(.pasteClipboard)
            }
            model.onDeleteWord = { [weak self, weak model] in
                guard let self, let model else { return }
                perform(.deleteWordBackward)
                refreshEditPanel(model)
            }
            model.onUndo = { [weak self, weak model] in
                guard let self, let model else { return }
                perform(.undo)
                refreshEditPanel(model)
            }
            model.onDone = { [weak self] in
                self?.dismissEditPanel()
            }
        }

        private func refreshEditPanel(_ model: EditPanelModel) {
            let doc = documentProvider()
            model.hasSelection = !(doc.selectedText ?? "").isEmpty
            model.canUndo = inputProcessor.hasUndo
        }
    }
#endif
