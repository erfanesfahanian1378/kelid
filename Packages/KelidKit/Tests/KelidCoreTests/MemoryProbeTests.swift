@testable import KelidCore
import Testing

@Suite("MemoryProbe")
struct MemoryProbeTests {
    @Test("footprintMB returns a plausible positive value")
    func footprintIsPositive() {
        let mb = MemoryProbe.footprintMB()
        // A `swift test` process footprint is comfortably in double digits
        // of MB and nowhere near the keyboard's own budget; this just
        // guards against task_info failing (which returns -1).
        #expect(mb > 0)
        #expect(mb < 10000)
    }
}
