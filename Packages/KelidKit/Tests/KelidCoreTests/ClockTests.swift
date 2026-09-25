import Foundation
@testable import KelidCore
import Testing

@Suite("Clock")
struct ClockTests {
    @Test("SystemClock returns a current-ish date")
    func systemClockIsCurrent() {
        let clock = SystemClock()
        let before = Date()
        let now = clock.now()
        let after = Date()
        #expect(now >= before)
        #expect(now <= after)
    }

    @Test("TestClock starts at the given date and only moves when told to")
    func clockIsDeterministic() {
        let start = Date(timeIntervalSince1970: 1000)
        let clock = TestClock(now: start)
        #expect(clock.now() == start)

        clock.advance(by: 60)
        #expect(clock.now() == start.addingTimeInterval(60))

        let explicit = Date(timeIntervalSince1970: 5000)
        clock.set(explicit)
        #expect(clock.now() == explicit)
    }
}
