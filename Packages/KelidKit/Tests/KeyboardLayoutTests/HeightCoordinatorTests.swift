import KelidSettings
@testable import KeyboardLayout
import Testing

@Suite("HeightCoordinator")
struct HeightCoordinatorTests {
    @Test("total height sums toolbar, padding, rows and bottom lift")
    func totalHeightFormula() {
        var profile = SizeProfile.portraitDefault
        profile.rowHeight = 54
        profile.toolbarHeight = 44
        profile.bottomLift = 10
        let metrics = KeyboardMetrics(sizeProfile: profile)

        let height = HeightCoordinator.totalHeight(rowCount: 4, metrics: metrics, toolbarVisible: true)
        // toolbar(44) + top(4) + 4*54 + bottom(4) + lift(10) = 44+4+216+4+10 = 278
        #expect(height == 278)
    }

    @Test("hidden toolbar contributes zero height")
    func hiddenToolbarContributesNoHeight() {
        var profile = SizeProfile.portraitDefault
        profile.rowHeight = 50
        profile.toolbarHeight = 44
        profile.bottomLift = 0
        let metrics = KeyboardMetrics(sizeProfile: profile)

        let height = HeightCoordinator.totalHeight(rowCount: 3, metrics: metrics, toolbarVisible: false)
        // 0 + 4 + 150 + 4 + 0 = 158
        #expect(height == 158)
    }

    @Test("adding the number row adds exactly one row's worth of height")
    func numberRowAddsExactlyOneRow() {
        let metrics = KeyboardMetrics(sizeProfile: .portraitDefault)
        let without = HeightCoordinator.totalHeight(rowCount: 4, metrics: metrics, toolbarVisible: true)
        let with = HeightCoordinator.totalHeight(rowCount: 5, metrics: metrics, toolbarVisible: true)
        #expect(abs((with - without) - metrics.rowHeight) < 0.001)
    }
}
