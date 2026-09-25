@testable import KelidCore
import Testing

@Suite("AppGroup")
struct AppGroupTests {
    @Test("reading the identifier never crashes, even without the Info.plist key")
    func identifierReadDoesNotCrash() {
        // In a `swift test` host there is no KelidAppGroupID key at all, so
        // this is expected to be nil — the point of the test is that
        // reading it is always safe, which is what every caller relies on.
        _ = AppGroup.identifier
    }
}
