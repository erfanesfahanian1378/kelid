import SwiftUI

/// Task 10.1: the 5-tab shell (§6.10). Each tab owns its own
/// `NavigationStack` so pushes in one tab don't affect the others.
struct RootTabView: View {
    let services: AppServices
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false

    var body: some View {
        TabView {
            NavigationStack {
                HomeView(services: services)
            }
            .tabItem { Label("Home", systemImage: "house") }

            NavigationStack {
                ClipboardManagerView(services: services)
            }
            .tabItem { Label("Clipboard", systemImage: "doc.on.clipboard") }

            NavigationStack {
                DictionaryView(services: services)
            }
            .tabItem { Label("Dictionary", systemImage: "character.book.closed") }

            NavigationStack {
                ThemesPlaceholderView()
            }
            .tabItem { Label("Themes", systemImage: "paintpalette") }

            NavigationStack {
                SettingsView(services: services)
            }
            .tabItem { Label("Settings", systemImage: "gearshape") }
        }
        .fullScreenCover(isPresented: Binding(get: { !hasCompletedOnboarding }, set: { _ in })) {
            OnboardingView(onDone: { hasCompletedOnboarding = true })
        }
    }
}

/// Phase 11 builds the real gallery/editor (§6.8.7) — this placeholder just
/// keeps the 5-tab shell (§6.10's own spec) accurate about what's coming,
/// rather than silently omitting the tab until then.
private struct ThemesPlaceholderView: View {
    var body: some View {
        ContentUnavailableView(
            "Themes coming soon",
            systemImage: "paintpalette",
            description: Text("Theme galleries and a custom theme editor arrive in a later update.")
        )
        .navigationTitle("Themes")
    }
}
