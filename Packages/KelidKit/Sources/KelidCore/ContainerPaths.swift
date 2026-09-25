import Foundation

/// Resolves where Kelid's shared files live (PLAN.md §6.11.1): the App
/// Group container when Full Access is on and the group is reachable, or a
/// per-process local container otherwise (§2.1 C2 — the keyboard must work
/// without Full Access, just without shared clips/personal-model sync).
///
/// `baseURL` is always a *container root* in both cases, so every subpath
/// below is built the same way regardless of which one was resolved.
public struct ContainerPaths: Sendable, Equatable {
    public let baseURL: URL

    public init(baseURL: URL) {
        self.baseURL = baseURL
    }

    /// - Parameters:
    ///   - fullAccess: whether the host process currently has Full Access.
    ///   - appGroupIdentifier: defaults to `AppGroup.identifier`; overridable for tests.
    ///   - sharedContainerLookup: defaults to the real
    ///     `FileManager.containerURL(forSecurityApplicationGroupIdentifier:)`.
    ///     Injectable because that call only actually returns `nil` inside a
    ///     real App Sandbox without the entitlement — an unsandboxed
    ///     `swift test` host resolves *any* identifier to a path, which
    ///     would make the "unreachable" branch untestable otherwise.
    ///   - localBaseURL: defaults to the process's own sandbox container
    ///     root; overridable for tests. Built from `NSHomeDirectory()`, not
    ///     `FileManager.homeDirectoryForCurrentUser` — the latter is
    ///     unavailable on iOS.
    public static func resolve(
        fullAccess: Bool,
        appGroupIdentifier: String? = AppGroup.identifier,
        sharedContainerLookup: (String) -> URL? = { FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: $0) },
        localBaseURL: @autoclosure () -> URL = URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
    ) -> ContainerPaths {
        if fullAccess,
           let appGroupIdentifier,
           let sharedURL = sharedContainerLookup(appGroupIdentifier)
        {
            return ContainerPaths(baseURL: sharedURL)
        }
        return ContainerPaths(baseURL: localBaseURL())
    }

    public var databaseURL: URL {
        subpath("Library/Application Support/Kelid/kelid.sqlite")
    }

    public var themesDirectoryURL: URL {
        subpath("Library/Application Support/Kelid/Themes", isDirectory: true)
    }

    public var clipImagesDirectoryURL: URL {
        subpath("Library/Application Support/Kelid/Clips/images", isDirectory: true)
    }

    public var clipThumbsDirectoryURL: URL {
        subpath("Library/Application Support/Kelid/Clips/thumbs", isDirectory: true)
    }

    /// Cleaned on launch (PLAN.md §6.11.1).
    public var temporaryDirectoryURL: URL {
        subpath("tmp", isDirectory: true)
    }

    private func subpath(_ path: String, isDirectory: Bool = false) -> URL {
        baseURL.appendingPathComponent(path, isDirectory: isDirectory)
    }
}
