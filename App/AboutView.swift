import SwiftUI

/// Task 10.10: version, privacy statement (`docs/PRIVACY.md`) and
/// acknowledgements (`docs/ATTRIBUTIONS.md`) — "Delete all Kelid data"
/// lives in Advanced settings instead, per §6.12's own placement
/// ("App → Settings → Advanced").
struct AboutView: View {
    var body: some View {
        List {
            Section {
                LabeledContent("Version", value: Self.versionString)
            }
            Section {
                NavigationLink("Privacy") { DocumentTextView(title: "Privacy", resourceName: "PRIVACY") }
                NavigationLink("Acknowledgements") { DocumentTextView(title: "Acknowledgements", resourceName: "ATTRIBUTIONS") }
            }
        }
        .navigationTitle("About")
    }

    private static var versionString: String {
        let shortVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
        return "\(shortVersion) (\(build))"
    }
}

/// Renders one of the bundled Markdown docs (`docs/*.md`, bundled as
/// resources via `project.yml`) as plain text — a full Markdown renderer is
/// more machinery than a two-screen About section warrants; `Text`'s own
/// basic Markdown support (bold/lists) already handles these files'
/// actual formatting well enough.
private struct DocumentTextView: View {
    let title: String
    let resourceName: String

    var body: some View {
        ScrollView {
            Text(Self.contents(of: resourceName))
                .textSelection(.enabled)
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .navigationTitle(title)
    }

    private static func contents(of resourceName: String) -> LocalizedStringKey {
        guard let url = Bundle.main.url(forResource: resourceName, withExtension: "md"),
              let text = try? String(contentsOf: url, encoding: .utf8)
        else {
            return "This document couldn't be loaded."
        }
        return LocalizedStringKey(text)
    }
}
