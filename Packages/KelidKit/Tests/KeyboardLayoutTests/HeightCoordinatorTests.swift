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

    // MARK: - §6.3.3 clamp (task 4.1)

    @Test("under-budget metrics pass through unchanged")
    func underBudgetMetricsUnchanged() {
        let metrics = KeyboardMetrics(sizeProfile: .portraitDefault)
        let clamped = HeightCoordinator.clampedMetrics(
            metrics, rowCount: 4, toolbarVisible: true, screenHeight: 900, orientation: .portrait
        )
        #expect(clamped == metrics)
    }

    @Test("over-budget metrics reduce bottomLift first")
    func overBudgetReducesLiftFirst() {
        var profile = SizeProfile.portraitDefault
        profile.rowHeight = 54
        profile.toolbarHeight = 44
        profile.bottomLift = 40
        let metrics = KeyboardMetrics(sizeProfile: profile)
        // Unclamped total: 44+4+4*54+4+40 = 308. Budget at screenHeight 500, portrait (60%) = 300.
        // Reducing lift by 8 (40 -> 32) exactly closes the 8pt gap without touching rowHeight.
        let clamped = HeightCoordinator.clampedMetrics(
            metrics, rowCount: 4, toolbarVisible: true, screenHeight: 500, orientation: .portrait
        )
        #expect(clamped.bottomLift == 32)
        #expect(clamped.rowHeight == 54)
        let height = HeightCoordinator.totalHeight(rowCount: 4, metrics: clamped, toolbarVisible: true)
        #expect(abs(height - 300) < 0.001)
    }

    @Test("reducing bottomLift to zero is not enough: rowHeight is also reduced, never below its floor")
    func overBudgetAlsoReducesRowHeight() {
        var profile = SizeProfile.portraitDefault
        profile.rowHeight = 70
        profile.toolbarHeight = 44
        profile.bottomLift = 20
        let metrics = KeyboardMetrics(sizeProfile: profile)
        // Unclamped total: 44+4+4*70+4+20 = 352. Budget at screenHeight 500, portrait = 300.
        // Zeroing lift removes 20, leaving 32 still over budget -> rowHeight drops by 32/4 = 8, to 62.
        let clamped = HeightCoordinator.clampedMetrics(
            metrics, rowCount: 4, toolbarVisible: true, screenHeight: 500, orientation: .portrait
        )
        #expect(clamped.bottomLift == 0)
        #expect(abs(clamped.rowHeight - 62) < 0.001)
        #expect(clamped.rowHeight >= 38) // never below §6.1.3's portrait floor
    }

    @Test("rowHeight is never reduced below its orientation floor even when still over budget")
    func rowHeightNeverBelowFloor() {
        var profile = SizeProfile.portraitDefault
        profile.rowHeight = 40
        profile.toolbarHeight = 44
        profile.bottomLift = 0
        let metrics = KeyboardMetrics(sizeProfile: profile)
        // Unclamped total with 6 rows: 44+4+6*40+4+0 = 292. An unrealistically tiny screen
        // (screenHeight 100, budget 60) can't be reached even at the rowHeight floor (38) —
        // the clamp should stop at the floor rather than go lower or negative.
        let clamped = HeightCoordinator.clampedMetrics(
            metrics, rowCount: 6, toolbarVisible: true, screenHeight: 100, orientation: .portrait
        )
        #expect(clamped.rowHeight == 38)
    }
}
