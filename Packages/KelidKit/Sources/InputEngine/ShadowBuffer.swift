import Foundation

/// The last 200 characters *this keyboard* inserted into the current
/// document (§6.4.8) — used when the host's `contextBefore` is `nil`
/// (some hosts don't provide it). Reset on a document change, or corrected
/// when reality no longer matches what we expect (an external edit, or the
/// cursor jumped somewhere we didn't move it).
public struct ShadowBuffer: Sendable, Equatable {
    private static let maxLength = 200

    private var buffer = ""
    public private(set) var documentIdentifier: UUID?

    public init() {}

    public mutating func noteDocument(_ id: UUID) {
        guard id != documentIdentifier else { return }
        documentIdentifier = id
        buffer = ""
    }

    public mutating func recordInsertion(_ text: String) {
        buffer.append(text)
        if buffer.count > Self.maxLength {
            buffer.removeFirst(buffer.count - Self.maxLength)
        }
    }

    public mutating func recordDeletion(count: Int = 1) {
        guard count > 0 else { return }
        buffer.removeLast(min(count, buffer.count))
    }

    /// Call whenever the host's real `contextBefore` is available: if it no
    /// longer ends with our buffer, something outside our control changed
    /// the text (external edit, cursor jump) — resync rather than trust
    /// stale data.
    public mutating func verify(against hostContextBefore: String?) {
        guard let hostContextBefore, !buffer.isEmpty else { return }
        if !hostContextBefore.hasSuffix(buffer) {
            buffer = String(hostContextBefore.suffix(Self.maxLength))
        }
    }

    public var contents: String {
        buffer
    }

    public mutating func reset() {
        buffer = ""
    }
}
