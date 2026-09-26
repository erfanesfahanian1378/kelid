#if canImport(UIKit)
    import SwiftUI

    /// Task 9.5's suggestion long-press menu: *Don't suggest "…"* (block)
    /// and *Forget "…"* (delete the word's personal data), with a Cancel.
    /// `KeyboardController` hands this the word plus already-bound action
    /// closures; it never touches `SuggestionService`/`UserModel` directly
    /// (same "controller owns the services, the view just reports taps"
    /// pattern as `QuickSettingsView`/`ResizeOverlayView`).
    public struct SuggestionMenuView: View {
        let word: String
        let onDontSuggest: () -> Void
        let onForget: () -> Void
        let onCancel: () -> Void

        public init(word: String, onDontSuggest: @escaping () -> Void, onForget: @escaping () -> Void, onCancel: @escaping () -> Void) {
            self.word = word
            self.onDontSuggest = onDontSuggest
            self.onForget = onForget
            self.onCancel = onCancel
        }

        public var body: some View {
            ZStack {
                Color.black.opacity(0.2)
                    .ignoresSafeArea()
                    .onTapGesture(perform: onCancel)

                VStack(spacing: 0) {
                    Text(word)
                        .font(.headline)
                        .padding()
                    Divider()
                    menuButton("Don't suggest", role: .destructive, action: onDontSuggest)
                    Divider()
                    menuButton("Forget", role: .destructive, action: onForget)
                    Divider()
                    menuButton("Cancel", role: .cancel, action: onCancel)
                }
                .background(Color(uiColor: .systemBackground))
                .cornerRadius(12)
                .padding(40)
            }
        }

        private func menuButton(_ title: String, role: ButtonRole, action: @escaping () -> Void) -> some View {
            Button(title, role: role, action: action)
                .frame(maxWidth: .infinity)
                .padding()
        }
    }
#endif
