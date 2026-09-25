@testable import KelidCore
import Testing

@Suite("Signposts")
struct SignpostsTests {
    @Test("begin/end/event do not crash and round-trip an id")
    func signpostsRoundTrip() {
        let id = Signposts.begin("test.interval")
        Signposts.event("test.event")
        Signposts.end("test.interval", id: id)
    }
}
