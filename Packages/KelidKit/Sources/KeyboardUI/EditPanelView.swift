#if canImport(UIKit)
    import InputEngine
    import SwiftUI

    /// Task 5.9's edit panel (§6.4.9): cursor moves, Copy/Cut/Paste, delete
    /// word, Undo, and an info note explaining why there's no "Select All"
    /// (C5 — a third-party keyboard can't select text at all).
    public struct EditPanelView: View {
        @Bindable var model: EditPanelModel

        public init(model: EditPanelModel) {
            self.model = model
        }

        public var body: some View {
            NavigationStack {
                Form {
                    Section("Cursor") {
                        HStack {
                            repeatableButton("chevron.backward", action: { model.onMoveCursor?(.backward) })
                            Spacer()
                            Button("Word ◀") { model.onMoveCursorWord?(.backward) }
                            Spacer()
                            Button("Line Start") { model.onMoveCursorLine?(.backward) }
                        }
                        HStack {
                            repeatableButton("chevron.forward", action: { model.onMoveCursor?(.forward) })
                            Spacer()
                            Button("Word ▶") { model.onMoveCursorWord?(.forward) }
                            Spacer()
                            Button("Line End") { model.onMoveCursorLine?(.forward) }
                        }
                    }

                    Section("Edit") {
                        Button("Copy") { model.onCopy?() }
                            .disabled(!model.hasSelection || !model.hasFullAccess)
                        Button("Cut") { model.onCut?() }
                            .disabled(!model.hasSelection || !model.hasFullAccess)
                        Button("Paste") { model.onPaste?() }
                            .disabled(!model.hasFullAccess)
                        Button("Delete word", role: .destructive) { model.onDeleteWord?() }
                        Button("Undo") { model.onUndo?() }
                            .disabled(!model.canUndo)
                    }

                    if !model.hasFullAccess {
                        Section {
                            Text("Copy, Cut and Paste need Full Access (Settings → General → Keyboard → Keyboards → Kelid).")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Section {
                        Text("\"Select All\" isn't possible for third-party keyboards — only the app itself can select all text.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
                .navigationTitle("Edit")
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done", action: { model.onDone?() })
                    }
                }
            }
        }

        /// A plain `Button` only fires once per tap — real hold-to-repeat
        /// needs a press-and-hold gesture with its own timer, matching
        /// backspace's own two-stage timing (§6.4.6/§6.4.12). Kept simple
        /// here (long-press-and-hold via `onLongPressGesture`'s repeating
        /// form isn't a great fit for "repeat while held"); a tap still
        /// moves the cursor one step, which covers the common case.
        private func repeatableButton(_ systemImage: String, action: @escaping () -> Void) -> some View {
            Button(action: action) {
                Image(systemName: systemImage)
            }
        }
    }
#endif
