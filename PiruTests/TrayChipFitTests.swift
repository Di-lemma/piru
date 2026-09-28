import CoreGraphics
import Testing
@testable import Piru

@Suite("Tray chip fit")
struct TrayChipFitTests {
    /// Widths measured off the simulator: When 93, Tags icon 42, "Food" 79 / icon 37,
    /// "Location" 105 / icon 40.
    private func fit(available: CGFloat) -> TrayChipFit {
        TrayChipFit(
            available: available, when: 93, tags: 42,
            mealLabeled: 79, mealIcon: 37, locationLabeled: 105, locationIcon: 40,
        )
    }

    @Test
    func `Every title shows when the row has room`() {
        #expect(fit(available: 354).tier(showsMeal: true, mealSet: false, locationSet: false) == 0)
    }

    @Test
    func `An unset Location gives up its title first`() {
        let fit = fit(available: 327)
        let tier = fit.tier(showsMeal: true, mealSet: false, locationSet: false)
        #expect(tier == 1)
        #expect(TrayChipFit.mealShowsLabel(tier: tier, isSet: false))
        #expect(!TrayChipFit.locationShowsLabel(tier: tier, isSet: false))
    }

    @Test
    func `A set chip keeps its value until the last tier`() {
        #expect(TrayChipFit.locationShowsLabel(tier: 2, isSet: true))
        #expect(TrayChipFit.mealShowsLabel(tier: 2, isSet: true))
        #expect(!TrayChipFit.mealShowsLabel(tier: 2, isSet: false))
        #expect(!TrayChipFit.locationShowsLabel(tier: 3, isSet: true))
    }

    @Test
    func `Without an oral dose the Food chip takes no room`() {
        #expect(fit(available: 260).tier(showsMeal: false, mealSet: false, locationSet: false) == 0)
    }

    @Test
    func `An unmeasured row draws every title`() {
        #expect(fit(available: 0).tier(showsMeal: true, mealSet: true, locationSet: true) == 0)
    }
}
