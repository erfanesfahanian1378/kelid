import Foundation
import KelidCore

/// Task 7.5: finds a language's bundled `.klm` file. Two real
/// implementations because the keyboard extension and the app find models
/// in different places (the app has no `.klm` of its own — it only ever
/// reads the extension's, e.g. for a future "model info" screen).
public protocol ModelLocator: Sendable {
    func url(for language: LanguageID) -> URL?
}

/// The keyboard extension's own locator — `.klm` files are bundled directly
/// into its `Bundle.main` (task 7.5, verified against a real build: XcodeGen
/// picks up `Keyboard/Resources/LM/*.klm` as bundle resources with no extra
/// `resources:` configuration needed, since they sit under the target's
/// `sources` path and aren't a recognized "compilable" file type).
public struct ExtensionModelLocator: ModelLocator {
    private let bundle: Bundle

    public init(bundle: Bundle = .main) {
        self.bundle = bundle
    }

    public func url(for language: LanguageID) -> URL? {
        bundle.url(forResource: language.rawValue, withExtension: "klm")
    }
}

/// The app's locator — reaches into the keyboard extension's `.appex`
/// bundle via `Bundle.main.builtInPlugInsURL` (task 7.5's own words), since
/// the app itself never bundles a `.klm` copy.
public struct AppModelLocator: ModelLocator {
    private let mainBundle: Bundle

    public init(mainBundle: Bundle = .main) {
        self.mainBundle = mainBundle
    }

    public func url(for language: LanguageID) -> URL? {
        // `FileManager` itself isn't `Sendable`, so `.default` (documented
        // as thread-safe) is used directly here rather than stored as a
        // property this `Sendable` struct would need to carry around.
        guard let pluginsURL = mainBundle.builtInPlugInsURL,
              let entries = try? FileManager.default.contentsOfDirectory(at: pluginsURL, includingPropertiesForKeys: nil)
        else {
            return nil
        }
        for entry in entries where entry.pathExtension == "appex" {
            if let bundle = Bundle(url: entry), let modelURL = bundle.url(forResource: language.rawValue, withExtension: "klm") {
                return modelURL
            }
        }
        return nil
    }
}
