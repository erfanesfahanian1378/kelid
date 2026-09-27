import SwiftUI
import ThemeKit
import UniformTypeIdentifiers

/// Task 11.8's theme gallery: every built-in theme plus everything in the
/// App Group's custom `Themes/` directory, each a small swatch card. Tap a
/// card to set it as the active theme (light/dark/fixed, whichever the
/// current `themeMode` needs); long-press for duplicate/edit/delete.
struct ThemeGalleryView: View {
    let services: AppServices
    @State private var customThemes: [Theme] = []
    @State private var editingTheme: Theme?
    @State private var showingImporter = false
    @State private var importError: String?

    private let columns = [GridItem(.adaptive(minimum: 140), spacing: 12)]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Built-in").font(.headline).padding(.horizontal)
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(services.builtInThemeCatalog.allThemes(), id: \.id) { theme in
                        ThemeCardView(theme: theme, onTap: { setActive(theme) }, onDuplicate: { duplicate(theme) })
                    }
                }
                .padding(.horizontal)

                Text("My Themes").font(.headline).padding(.horizontal)
                if customThemes.isEmpty {
                    Text("No custom themes yet — duplicate a built-in one to start editing.")
                        .foregroundStyle(.secondary)
                        .padding(.horizontal)
                } else {
                    LazyVGrid(columns: columns, spacing: 12) {
                        ForEach(customThemes, id: \.id) { theme in
                            ThemeCardView(
                                theme: theme, onTap: { setActive(theme) }, onDuplicate: { duplicate(theme) },
                                onEdit: { editingTheme = theme }, onDelete: { delete(theme) }
                            )
                        }
                    }
                    .padding(.horizontal)
                }
            }
            .padding(.vertical)
        }
        .navigationTitle("Themes")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button("New from Light") { duplicate(.fallbackLight) }
                    Button("New from Dark") { duplicate(.fallbackDark) }
                    Button("Import .kelidtheme…") { showingImporter = true }
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(item: $editingTheme, onDismiss: reload) { theme in
            NavigationStack { ThemeEditorView(services: services, theme: theme) }
        }
        .fileImporter(isPresented: $showingImporter, allowedContentTypes: [.kelidTheme]) { result in
            if let url = try? result.get() {
                importTheme(from: url)
            }
        }
        .alert("Couldn't import theme", isPresented: .constant(importError != nil), actions: {
            Button("OK") { importError = nil }
        }, message: { Text(importError ?? "") })
        .onAppear(perform: reload)
    }

    private func reload() {
        customThemes = services.themeStore.listCustomThemes()
    }

    private func setActive(_ theme: Theme) {
        services.settings.update { settings in
            switch settings.appearance.themeMode {
            case .fixed:
                settings.appearance.fixedThemeID = theme.id
            case .followSystem, .followApp:
                if theme.isDark {
                    settings.appearance.darkThemeID = theme.id
                } else {
                    settings.appearance.lightThemeID = theme.id
                }
            }
        }
    }

    private func duplicate(_ theme: Theme) {
        var copy = theme
        copy.id = "custom.\(UUID().uuidString.prefix(8))"
        copy.name = ThemeName(en: theme.name.en + " Copy", fa: theme.name.fa + " کپی")
        try? services.themeStore.saveCustomTheme(copy)
        reload()
        editingTheme = copy
    }

    private func delete(_ theme: Theme) {
        try? services.themeStore.deleteCustomTheme(id: theme.id)
        reload()
    }

    private func importTheme(from url: URL) {
        let needsSecurityScope = url.startAccessingSecurityScopedResource()
        defer {
            if needsSecurityScope {
                url.stopAccessingSecurityScopedResource()
            }
        }
        do {
            let data = try Data(contentsOf: url)
            var theme = try JSONDecoder().decode(Theme.self, from: data)
            // Importing never silently overwrites an existing theme with the
            // same id (e.g. re-importing a file shared between two devices
            // that both still have the original) — always lands as a new,
            // clearly-separate custom theme instead.
            if services.themeStore.loadCustomTheme(id: theme.id) != nil {
                theme.id = "custom.\(UUID().uuidString.prefix(8))"
            }
            try services.themeStore.saveCustomTheme(theme)
            reload()
        } catch {
            importError = error.localizedDescription
        }
    }
}

private struct ThemeCardView: View {
    let theme: Theme
    let onTap: () -> Void
    var onDuplicate: (() -> Void)?
    var onEdit: (() -> Void)?
    var onDelete: (() -> Void)?

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 4) {
                    swatch(theme.keys.normal.fill)
                    swatch(theme.keys.accent.fill)
                    swatch(theme.panel.background)
                }
                .frame(height: 36)
                .clipShape(RoundedRectangle(cornerRadius: 6))
                Text(theme.name.en).font(.subheadline).lineLimit(1)
            }
            .padding(8)
            .background(.thinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button("Set as active") { onTap() }
            if let onDuplicate {
                Button("Duplicate") { onDuplicate() }
            }
            if let onEdit {
                Button("Edit") { onEdit() }
            }
            if let onDelete {
                Button("Delete", role: .destructive) { onDelete() }
            }
        }
    }

    private func swatch(_ hex: String) -> some View {
        Rectangle().fill(ThemeColorBinding.color(from: hex))
    }
}
