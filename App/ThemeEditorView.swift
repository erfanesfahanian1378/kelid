import CoreImage
import CoreImage.CIFilterBuiltins
import KeyboardUI
import PhotosUI
import SwiftUI
import ThemeKit
import UniformTypeIdentifiers

/// Task 11.8's theme editor. Always operates on a *custom* theme (the
/// gallery's "Duplicate" always creates one before opening this) — built-in
/// themes are read-only, matching §6.8.7's own "start from any theme →
/// edit" wording (start FROM, not edit in place).
struct ThemeEditorView: View {
    let services: AppServices
    @State private var theme: Theme
    @State private var backgroundKind: BackgroundKind
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var blur: Double
    @State private var dim: Double
    @State private var warnings: [ThemeValidator.Warning] = []
    @State private var showingExporter = false
    @Environment(\.dismiss) private var dismiss

    private enum BackgroundKind: String, CaseIterable {
        case color, gradient, image, material, glass
    }

    init(services: AppServices, theme: Theme) {
        self.services = services
        _theme = State(initialValue: theme)
        switch theme.background {
        case .color: _backgroundKind = State(initialValue: .color)
        case .gradient: _backgroundKind = State(initialValue: .gradient)
        case .image: _backgroundKind = State(initialValue: .image)
        case .material: _backgroundKind = State(initialValue: .material)
        case .glass: _backgroundKind = State(initialValue: .glass)
        }
        if case let .image(_, initialBlur, initialDim) = theme.background {
            _blur = State(initialValue: initialBlur)
            _dim = State(initialValue: initialDim)
        } else {
            _blur = State(initialValue: 12)
            _dim = State(initialValue: 0.25)
        }
    }

    var body: some View {
        Form {
            Section {
                KeyboardPreviewView(profile: .portraitDefault, language: .fa, theme: theme)
                    .frame(height: 200)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.separator))
            }
            nameSection
            backgroundSection
            keysSection
            toolbarSection
            calloutSection
            panelSection
            fontsSection
            if !warnings.isEmpty {
                Section("Warnings") {
                    ForEach(Array(warnings.enumerated()), id: \.offset) { _, warning in
                        Text("\(warning.field): \(warning.message)").font(.caption).foregroundStyle(.orange)
                    }
                }
            }
        }
        .navigationTitle(theme.name.en)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) { Button("Save") { save() } }
            ToolbarItem(placement: .secondaryAction) {
                Button { showingExporter = true } label: {
                    Label("Export", systemImage: "square.and.arrow.up")
                }
            }
        }
        .fileExporter(
            isPresented: $showingExporter, document: ThemeDocument(theme: theme), contentType: .kelidTheme,
            defaultFilename: theme.name.en
        ) { _ in }
        .onChange(of: selectedPhoto) { _, newItem in
            Task { await loadAndBakeImage(newItem) }
        }
        .onAppear { warnings = ThemeValidator.validate(theme) }
    }

    private var nameSection: some View {
        Section("Name") {
            TextField("English", text: $theme.name.en)
            TextField("Persian", text: $theme.name.fa)
            Toggle("Dark theme", isOn: $theme.isDark)
        }
    }

    private var backgroundSection: some View {
        Section("Background") {
            Picker("Type", selection: $backgroundKind) {
                Text("Color").tag(BackgroundKind.color)
                Text("Gradient").tag(BackgroundKind.gradient)
                Text("Photo").tag(BackgroundKind.image)
                Text("Material").tag(BackgroundKind.material)
                Text("Glass").tag(BackgroundKind.glass)
            }
            .onChange(of: backgroundKind) { _, newKind in updateBackgroundKind(newKind) }

            switch backgroundKind {
            case .color:
                if case let .color(hex) = theme.background {
                    ColorPicker("Color", selection: colorBinding(get: { hex }, set: { theme.background = .color($0) }))
                }
            case .gradient:
                if case let .gradient(colors, angle) = theme.background {
                    ForEach(colors.indices, id: \.self) { index in
                        ColorPicker(
                            "Color \(index + 1)",
                            selection: colorBinding(
                                get: { colors[index] },
                                set: { newHex in
                                    var updated = colors
                                    updated[index] = newHex
                                    theme.background = .gradient(colors: updated, angle: angle)
                                }
                            )
                        )
                    }
                    LabeledContent("Angle: \(Int(angle))°") {
                        Slider(
                            value: Binding(get: { angle }, set: { theme.background = .gradient(colors: colors, angle: $0) }),
                            in: 0 ... 360
                        )
                    }
                }
            case .image:
                PhotosPicker("Choose Photo", selection: $selectedPhoto, matching: .images)
                if case let .image(file, _, _) = theme.background {
                    Text(file).font(.caption).foregroundStyle(.secondary)
                    LabeledContent("Blur: \(Int(blur))") { Slider(value: $blur, in: 0 ... 30) }
                    LabeledContent("Dim: \(String(format: "%.2f", dim))") { Slider(value: $dim, in: 0 ... 0.8) }
                        .onChange(of: blur) { _, _ in Task { await rebakeCurrentImage() } }
                        .onChange(of: dim) { _, _ in Task { await rebakeCurrentImage() } }
                } else {
                    Text("No photo chosen yet").font(.caption).foregroundStyle(.secondary)
                }
            case .material:
                if case let .material(style) = theme.background {
                    Picker(
                        "Style",
                        selection: Binding(get: { style }, set: { theme.background = .material(style: $0) })
                    ) {
                        ForEach(Self.materialStyleNames, id: \.self) { Text($0).tag($0) }
                    }
                }
            case .glass:
                if case let .glass(tint) = theme.background {
                    Text("Real Liquid Glass (iOS 26+) — falls back to a plain system material on older versions.")
                        .font(.caption).foregroundStyle(.secondary)
                    Toggle(
                        "Tinted",
                        isOn: Binding(
                            get: { tint != nil },
                            set: { isOn in theme.background = .glass(tint: isOn ? (tint ?? "#007AFF80") : nil) }
                        )
                    )
                    if let tint {
                        ColorPicker("Tint", selection: colorBinding(get: { tint }, set: { theme.background = .glass(tint: $0) }))
                    }
                }
            }
        }
    }

    private static let materialStyleNames = [
        "systemMaterial", "systemMaterialLight", "systemMaterialDark",
        "systemThinMaterial", "systemThinMaterialLight", "systemThinMaterialDark",
        "systemThickMaterial", "systemChromeMaterial",
    ]

    private var keysSection: some View {
        Section("Keys") {
            keyStateRow("Normal", fill: \.keys.normal.fill, text: \.keys.normal.text, pressed: \.keys.normal.pressedFill)
            keyStateRow("Special", fill: \.keys.special.fill, text: \.keys.special.text, pressed: \.keys.special.pressedFill)
            keyStateRow("Accent", fill: \.keys.accent.fill, text: \.keys.accent.text, pressed: \.keys.accent.pressedFill)
            ColorPicker("Hint text", selection: colorBinding(get: { theme.keys.hintText }, set: { theme.keys.hintText = $0 }))
            LabeledContent("Corner radius: \(Int(theme.keys.cornerRadius))") {
                Slider(value: $theme.keys.cornerRadius, in: 0 ... 20)
            }
            LabeledContent("Border width: \(String(format: "%.1f", theme.keys.borderWidth))") {
                Slider(value: $theme.keys.borderWidth, in: 0 ... 4)
            }
            ColorPicker("Border color", selection: colorBinding(get: { theme.keys.borderColor }, set: { theme.keys.borderColor = $0 }))
        }
    }

    private func keyStateRow(
        _ title: String, fill: WritableKeyPath<Theme, String>, text: WritableKeyPath<Theme, String>,
        pressed: WritableKeyPath<Theme, String>
    ) -> some View {
        DisclosureGroup(title) {
            ColorPicker("Fill", selection: colorBinding(get: { theme[keyPath: fill] }, set: { theme[keyPath: fill] = $0 }))
            ColorPicker("Text", selection: colorBinding(get: { theme[keyPath: text] }, set: { theme[keyPath: text] = $0 }))
            ColorPicker(
                "Pressed fill", selection: colorBinding(get: { theme[keyPath: pressed] }, set: { theme[keyPath: pressed] = $0 })
            )
        }
    }

    private var toolbarSection: some View {
        Section("Toolbar") {
            ColorPicker("Background", selection: colorBinding(get: { theme.toolbar.background }, set: { theme.toolbar.background = $0 }))
            ColorPicker("Icons", selection: colorBinding(get: { theme.toolbar.icon }, set: { theme.toolbar.icon = $0 }))
            ColorPicker(
                "Suggestion text", selection: colorBinding(
                    get: { theme.toolbar.suggestionText },
                    set: { theme.toolbar.suggestionText = $0 }
                )
            )
            ColorPicker("Divider", selection: colorBinding(get: { theme.toolbar.divider }, set: { theme.toolbar.divider = $0 }))
            ColorPicker("Chip fill", selection: colorBinding(get: { theme.toolbar.chipFill }, set: { theme.toolbar.chipFill = $0 }))
        }
    }

    private var calloutSection: some View {
        Section("Key Callout") {
            ColorPicker("Fill", selection: colorBinding(get: { theme.callout.fill }, set: { theme.callout.fill = $0 }))
            ColorPicker("Text", selection: colorBinding(get: { theme.callout.text }, set: { theme.callout.text = $0 }))
        }
    }

    private var panelSection: some View {
        Section("Panels (Clipboard/Emoji)") {
            ColorPicker("Background", selection: colorBinding(get: { theme.panel.background }, set: { theme.panel.background = $0 }))
            ColorPicker("Row fill", selection: colorBinding(get: { theme.panel.rowFill }, set: { theme.panel.rowFill = $0 }))
            ColorPicker("Text", selection: colorBinding(get: { theme.panel.text }, set: { theme.panel.text = $0 }))
            ColorPicker(
                "Secondary text", selection: colorBinding(get: { theme.panel.secondaryText }, set: { theme.panel.secondaryText = $0 })
            )
            ColorPicker("Accent", selection: colorBinding(get: { theme.panel.accent }, set: { theme.panel.accent = $0 }))
        }
    }

    private var fontsSection: some View {
        Section("Fonts") {
            Picker("Weight", selection: $theme.fonts.weight) {
                Text("Regular").tag("regular")
                Text("Medium").tag("medium")
                Text("Semibold").tag("semibold")
                Text("Bold").tag("bold")
            }
            LabeledContent("Scale: \(String(format: "%.2f", theme.fonts.scale))") {
                Slider(value: $theme.fonts.scale, in: 0.8 ... 1.3)
            }
        }
    }

    private func colorBinding(get: @escaping () -> String, set: @escaping (String) -> Void) -> Binding<Color> {
        ThemeColorBinding.binding(Binding(get: get, set: set))
    }

    private func updateBackgroundKind(_ kind: BackgroundKind) {
        switch kind {
        case .color:
            theme.background = .color(theme.isDark ? "#1C1C1E" : "#D1D3D9")
        case .gradient:
            theme.background = .gradient(colors: ["#4A69E2", "#8E6FE0"], angle: 90)
        case .image:
            break // set once a photo is actually picked
        case .material:
            theme.background = .material(style: theme.isDark ? "systemMaterialDark" : "systemMaterialLight")
        case .glass:
            theme.background = .glass(tint: nil)
        }
    }

    /// §6.8.1: "Blur and dim are baked into the saved image by the app" —
    /// this is that baking step, via Core Image, run off the main actor
    /// since a full-resolution photo's Gaussian blur is real CPU/GPU work.
    private func loadAndBakeImage(_ item: PhotosPickerItem?) async {
        guard let item, let data = try? await item.loadTransferable(type: Data.self) else { return }
        await bakeAndSave(sourceData: data)
    }

    private func rebakeCurrentImage() async {
        guard case let .image(file, _, _) = theme.background,
              let data = try? Data(contentsOf: services.themeStore.imageURL(filename: file)),
              let originalData = Self.originalImageCache[file]
        else { return }
        _ = data // the on-disk file is already baked; re-bake from the cached original instead
        await bakeAndSave(sourceData: originalData, existingFilename: file)
    }

    /// Keeps the *unbaked* source in memory only (never written to disk) so
    /// moving the blur/dim sliders can re-bake from the original repeatedly
    /// without accumulating blur-on-top-of-blur.
    @MainActor private static var originalImageCache: [String: Data] = [:]

    private func bakeAndSave(sourceData: Data, existingFilename: String? = nil) async {
        guard let uiImage = UIImage(data: sourceData), let ciImage = CIImage(image: uiImage) else { return }
        let context = CIContext()
        let blurFilter = CIFilter.gaussianBlur()
        blurFilter.inputImage = ciImage.clampedToExtent()
        blurFilter.radius = Float(blur)
        var output = blurFilter.outputImage?.cropped(to: ciImage.extent) ?? ciImage

        if dim > 0 {
            let dimFilter = CIFilter.colorMatrix()
            dimFilter.inputImage = output
            let scale = 1 - dim
            dimFilter.rVector = CIVector(x: scale, y: 0, z: 0, w: 0)
            dimFilter.gVector = CIVector(x: 0, y: scale, z: 0, w: 0)
            dimFilter.bVector = CIVector(x: 0, y: 0, z: scale, w: 0)
            output = dimFilter.outputImage ?? output
        }

        guard let cgImage = context.createCGImage(output, from: ciImage.extent) else { return }
        let baked = UIImage(cgImage: cgImage)
        guard let jpegData = baked.jpegData(compressionQuality: 0.8) else { return }

        let filename = existingFilename ?? "\(theme.id)-\(UUID().uuidString.prefix(6)).jpg"
        Self.originalImageCache[filename] = sourceData
        try? services.themeStore.saveImage(jpegData, filename: filename)
        theme.background = .image(file: filename, blur: blur, dim: dim)
    }

    private func save() {
        try? services.themeStore.saveCustomTheme(theme)
        dismiss()
    }
}
