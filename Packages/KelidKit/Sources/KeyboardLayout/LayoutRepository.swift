import Foundation
import KelidCore

public enum LayoutRepositoryError: Error, Sendable, Equatable {
    case notFound(String)
}

/// Loads, validates and caches layout files by id (task 2.3). An invalid
/// bundled file logs an error and falls back to `en.qwerty` rather than
/// crashing the keyboard.
public final class LayoutRepository: @unchecked Sendable {
    public static let shared = LayoutRepository()

    public static let allLayoutIDs = ["fa.standard", "fa.compact", "en.qwerty", "fa.symbols", "en.symbols", "numpad"]
    public static let fallbackLayoutID = "en.qwerty"

    private let log = Log.logger(.keyboardLayout)
    private let bundle: Bundle
    private let lock = NSLock()
    private var cache: [String: KeyboardLayoutFile] = [:]

    /// `bundle` defaults to this module's own resource bundle. Written as
    /// `nil` + a body assignment rather than `= .module` in the parameter
    /// list: `Bundle.module` is SPM-generated as `internal`, and an
    /// `internal` symbol can't appear in a `public` initializer's default
    /// argument *expression* (evaluated at each external call site), even
    /// though referencing it from the body is fine.
    public init(bundle: Bundle? = nil) {
        self.bundle = bundle ?? .module
    }

    public func layout(id: String) -> KeyboardLayoutFile {
        lock.lock()
        if let cached = cache[id] {
            lock.unlock()
            return cached
        }
        lock.unlock()

        do {
            let file = try loadAndValidate(id: id)
            lock.lock()
            cache[id] = file
            lock.unlock()
            return file
        } catch {
            log
                .error(
                    "layout \(id, privacy: .public) failed to load/validate (\(String(describing: error), privacy: .public)) — falling back to \(Self.fallbackLayoutID, privacy: .public)"
                )
            if id != Self.fallbackLayoutID {
                return layout(id: Self.fallbackLayoutID)
            }
            // The bundled fallback itself must always be valid — a build-time
            // guarantee, not a runtime possibility, so this is the one place
            // in KeyboardLayout allowed to fatalError (rule 5.1.2).
            fatalError("bundled fallback layout \(Self.fallbackLayoutID).json failed to load or validate: \(error)")
        }
    }

    private func loadAndValidate(id: String) throws -> KeyboardLayoutFile {
        guard let url = bundle.url(forResource: id, withExtension: "json") else {
            throw LayoutRepositoryError.notFound(id)
        }
        let data = try Data(contentsOf: url)
        let file = try JSONDecoder().decode(KeyboardLayoutFile.self, from: data)
        try LayoutValidator.validate(file)
        return file
    }
}
