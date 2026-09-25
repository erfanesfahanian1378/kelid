import Foundation
@testable import KelidCore
import Testing

/// A `@Sendable` handler passed to `observe` may run concurrently as far as
/// the type checker is concerned, so a plain captured `var` isn't allowed.
/// This tiny lock-protected box is test-only plumbing for that.
private final class Box<Value: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: Value

    init(_ value: Value) {
        storage = value
    }

    var value: Value {
        get {
            lock.lock()
            defer { lock.unlock() }
            return storage
        }
        set {
            lock.lock()
            storage = newValue
            lock.unlock()
        }
    }
}

@Suite("DarwinNotifier")
struct DarwinNotifierTests {
    @Test("observe receives a matching in-process post, on the main thread")
    @MainActor
    func observeReceivesInProcessPost() {
        let notifier = DarwinNotifier.shared
        let received = Box(false)
        let token = notifier.observe(.settingsChanged, appGroupIdentifier: nil) {
            received.value = true
        }
        defer { token.cancel() }

        notifier.postInProcess(.settingsChanged)
        #expect(received.value)
    }

    @Test("a cancelled token stops receiving posts")
    @MainActor
    func cancelledTokenStopsReceiving() {
        let notifier = DarwinNotifier.shared
        let receiveCount = Box(0)
        let token = notifier.observe(.clipsChanged, appGroupIdentifier: nil) {
            receiveCount.value += 1
        }

        notifier.postInProcess(.clipsChanged)
        #expect(receiveCount.value == 1)

        token.cancel()
        notifier.postInProcess(.clipsChanged)
        #expect(receiveCount.value == 1)
    }

    @Test("post without an app group identifier is a no-op, not a crash")
    func postWithoutIdentifierIsNoOp() {
        DarwinNotifier.shared.post(.themesChanged, appGroupIdentifier: nil)
    }
}
