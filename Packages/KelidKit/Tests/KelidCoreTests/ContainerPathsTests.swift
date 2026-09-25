import Foundation
@testable import KelidCore
import Testing

@Suite("ContainerPaths")
struct ContainerPathsTests {
    private let localFallback = URL(fileURLWithPath: "/tmp/kelid-test-local-container", isDirectory: true)
    private let sharedContainer = URL(fileURLWithPath: "/tmp/kelid-test-shared-container", isDirectory: true)

    @Test("full access with a reachable App Group resolves to the shared container")
    func fullAccessResolvesToSharedContainer() {
        let paths = ContainerPaths.resolve(
            fullAccess: true,
            appGroupIdentifier: "group.test.reachable",
            sharedContainerLookup: { _ in sharedContainer },
            localBaseURL: localFallback
        )
        #expect(paths.baseURL == sharedContainer)
    }

    @Test("full access but an unreachable App Group falls back to the local container")
    func unreachableGroupFallsBackLocally() {
        // What a real sandboxed process without the entitlement sees.
        let paths = ContainerPaths.resolve(
            fullAccess: true,
            appGroupIdentifier: "group.test.unreachable",
            sharedContainerLookup: { _ in nil },
            localBaseURL: localFallback
        )
        #expect(paths.baseURL == localFallback)
    }

    @Test("without full access always resolves to the local container")
    func withoutFullAccessResolvesLocally() {
        let paths = ContainerPaths.resolve(
            fullAccess: false,
            appGroupIdentifier: "group.test.reachable",
            sharedContainerLookup: { _ in sharedContainer },
            localBaseURL: localFallback
        )
        #expect(paths.baseURL == localFallback)
    }

    @Test("without an app group identifier always resolves to the local container")
    func withoutIdentifierResolvesLocally() {
        let paths = ContainerPaths.resolve(
            fullAccess: true,
            appGroupIdentifier: nil,
            sharedContainerLookup: { _ in sharedContainer },
            localBaseURL: localFallback
        )
        #expect(paths.baseURL == localFallback)
    }

    @Test("subpaths match §6.11.1 exactly")
    func subpathsMatchSpec() {
        let base = URL(fileURLWithPath: "/tmp/kelid-test-container", isDirectory: true)
        let paths = ContainerPaths(baseURL: base)
        #expect(paths.databaseURL.path == base.appendingPathComponent("Library/Application Support/Kelid/kelid.sqlite").path)
        #expect(paths.themesDirectoryURL.path == base.appendingPathComponent("Library/Application Support/Kelid/Themes").path)
        #expect(paths.clipImagesDirectoryURL.path == base.appendingPathComponent("Library/Application Support/Kelid/Clips/images").path)
        #expect(paths.clipThumbsDirectoryURL.path == base.appendingPathComponent("Library/Application Support/Kelid/Clips/thumbs").path)
        #expect(paths.temporaryDirectoryURL.path == base.appendingPathComponent("tmp").path)
    }
}
