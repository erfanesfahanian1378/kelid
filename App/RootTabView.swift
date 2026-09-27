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
                ThemeGalleryView(services: services)
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
