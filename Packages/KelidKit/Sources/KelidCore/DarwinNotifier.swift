import Foundation

/// Cross-process notification names posted between Kelid's app, keyboard
/// and Share Extension (PLAN.md §4.7). They carry **no payload** —
/// observers always re-read the changed data from shared storage (the
/// settings blob, the database, etc.).
public enum DarwinNotificationName: String, Sendable, CaseIterable {
    case settingsChanged = "settings.changed"
    case clipsChanged = "clips.changed"
    case snippetsChanged = "snippets.changed"
    case userDictChanged = "userdict.changed"
    case themesChanged = "themes.changed"
}

/// Handle returned by `DarwinNotifier.observe`. Call `cancel()` when you no
/// longer want the handler invoked; letting it deinit does *not* cancel —
/// callers must hold and cancel it explicitly (there is no weak reference
/// from the notifier back to a "subscriber" object to key off of).
public final class DarwinObservationToken: Sendable {
    fileprivate let id: UUID
    fileprivate let name: DarwinNotificationName
    private let cancelAction: @Sendable (UUID, DarwinNotificationName) -> Void

    fileprivate init(id: UUID, name: DarwinNotificationName, cancelAction: @escaping @Sendable (UUID, DarwinNotificationName) -> Void) {
        self.id = id
        self.name = name
        self.cancelAction = cancelAction
    }

    public func cancel() {
        cancelAction(id, name)
    }
}

/// Thin wrapper over `CFNotificationCenterGetDarwinNotifyCenter`.
///
/// - `post`/`observe` are safe to call from any thread.
/// - Handlers are always invoked on the main thread, regardless of which
///   thread the system delivered the underlying Darwin notification on.
public final class DarwinNotifier: @unchecked Sendable {
    public static let shared = DarwinNotifier()

    private let lock = NSLock()
    private var handlers: [DarwinNotificationName: [UUID: @Sendable () -> Void]] = [:]
    /// The App Group identifier each name was registered with the system
    /// under — needed to translate an incoming raw Darwin notification name
    /// back to a `DarwinNotificationName` case.
    private var registeredGroupIDs: [DarwinNotificationName: String] = [:]

    private init() {}

    public func post(_ name: DarwinNotificationName, appGroupIdentifier: String? = AppGroup.identifier) {
        guard let appGroupIdentifier else { return }
        CFNotificationCenterPostNotification(
            CFNotificationCenterGetDarwinNotifyCenter(),
            CFNotificationName(Self.fullName(name, appGroupIdentifier: appGroupIdentifier) as CFString),
            nil, nil, true
        )
    }

    @discardableResult
    public func observe(
        _ name: DarwinNotificationName,
        appGroupIdentifier: String? = AppGroup.identifier,
        handler: @escaping @Sendable () -> Void
    ) -> DarwinObservationToken {
        let id = UUID()
        lock.lock()
        handlers[name, default: [:]][id] = handler
        if let appGroupIdentifier, registeredGroupIDs[name] == nil {
            registeredGroupIDs[name] = appGroupIdentifier
            registerWithSystem(name, appGroupIdentifier: appGroupIdentifier)
        }
        lock.unlock()
        return DarwinObservationToken(id: id, name: name) { [weak self] id, name in
            self?.removeHandler(id: id, name: name)
        }
    }

    /// Delivers the notification to every handler registered for `name`
    /// in-process, without going through the system Darwin notify center.
    /// Used so `post`/`observe` also work for same-process delivery (the
    /// system center does not loop a notification back to its own poster),
    /// and is what makes the type unit-testable without a real App Group.
    public func postInProcess(_ name: DarwinNotificationName) {
        deliver(name)
    }

    private func removeHandler(id: UUID, name: DarwinNotificationName) {
        lock.lock()
        handlers[name]?[id] = nil
        lock.unlock()
    }

    private func registerWithSystem(_ name: DarwinNotificationName, appGroupIdentifier: String) {
        let cfName = Self.fullName(name, appGroupIdentifier: appGroupIdentifier)
        let observer = Unmanaged.passUnretained(self).toOpaque()
        CFNotificationCenterAddObserver(
            CFNotificationCenterGetDarwinNotifyCenter(),
            observer,
            { _, observer, cfNotificationName, _, _ in
                guard let observer, let cfNotificationName else { return }
                let notifier = Unmanaged<DarwinNotifier>.fromOpaque(observer).takeUnretainedValue()
                notifier.handleSystemNotification(rawName: cfNotificationName.rawValue as String)
            },
            cfName as CFString,
            nil,
            .deliverImmediately
        )
    }

    private func handleSystemNotification(rawName: String) {
        lock.lock()
        let match = registeredGroupIDs.first { name, groupID in
            Self.fullName(name, appGroupIdentifier: groupID) == rawName
        }?.key
        lock.unlock()
        guard let match else { return }
        deliver(match)
    }

    private func deliver(_ name: DarwinNotificationName) {
        lock.lock()
        let toCall = Array((handlers[name] ?? [:]).values)
        lock.unlock()
        guard !toCall.isEmpty else { return }
        if Thread.isMainThread {
            toCall.forEach { $0() }
        } else {
            DispatchQueue.main.async {
                toCall.forEach { $0() }
            }
        }
    }

    private static func fullName(_ name: DarwinNotificationName, appGroupIdentifier: String) -> String {
        "\(appGroupIdentifier).\(name.rawValue)"
    }
}
