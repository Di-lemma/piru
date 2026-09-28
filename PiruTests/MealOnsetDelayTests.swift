import Foundation
import Testing
@testable import Piru

@Suite("Meal onset delay")
struct MealOnsetDelayTests {
    private let base = DurationProfile(
        onset: DurationRange(min: 20, max: 40),
        comeup: DurationRange(min: 30, max: 30),
        peak: DurationRange(min: 120, max: 180),
        offset: DurationRange(min: 60, max: 60),
        afterglow: nil,
        total: DurationRange(min: 240, max: 300),
    )

    @Test
    func `A delay lengthens only the onset and moves every boundary by it`() {
        let shifted = base.delayingOnset(by: 45)
        #expect(shifted.onset == DurationRange(min: 65, max: 85))
        #expect(shifted.comeup == base.comeup)
        #expect(shifted.peak == base.peak)
        #expect(shifted.offset == base.offset)
        #expect(shifted.total == DurationRange(min: 285, max: 345))
        #expect(shifted.phaseBoundaries.comeupEnd == base.phaseBoundaries.comeupEnd + 45)
        #expect(shifted.phaseBoundaries.offsetEnd == base.phaseBoundaries.offsetEnd + 45)
    }

    @Test
    func `A profile with no onset gains one of the delay's length`() {
        let noOnset = DurationProfile(
            onset: nil, comeup: base.comeup, peak: base.peak, offset: base.offset, afterglow: nil, total: nil,
        )
        #expect(noOnset.delayingOnset(by: 30).onset == DurationRange(min: 30, max: 30))
    }

    @Test
    func `A zero delay returns the profile unchanged`() {
        #expect(base.delayingOnset(by: 0) == base)
    }

    @Test
    func `Fasted applies none of the delay, a snack half, a meal all of it`() {
        #expect(MealState.empty.fedFraction == 0)
        #expect(MealState.light.fedFraction == 0.5)
        #expect(MealState.full.fedFraction == 1)
    }

    @Test @MainActor
    func `Only an oral dose waits on the stomach`() {
        for route in RouteOfAdministration.allCases where route != .oral {
            #expect(MealState.full.onsetDelay(forSubstance: "Amphetamine", product: nil, route: route) == nil)
        }
    }

    @Test @MainActor
    func `An entry without a meal draws its profile unshifted`() {
        let entry = DoseEntry(substance: "Amphetamine", amount: 10, route: .oral)
        #expect(entry.applyingMeal(to: base) == base)
    }

    @Test @MainActor
    func `The bundled table answers by product, then substance, then the generic estimate`() throws {
        let adderallXR = try #require(MealState.full.onsetDelay(forSubstance: "Amphetamine", product: "Adderall XR", route: .oral))
        #expect(adderallXR == MealOnsetDelay(minutes: 150, isGeneric: false))

        let marinolByName = try #require(MealState.full.onsetDelay(forSubstance: "Marinol", product: nil, route: .oral))
        #expect(marinolByName.minutes == 232)

        let methylphenidate = try #require(MealState.full.onsetDelay(forSubstance: "Methylphenidate", product: nil, route: .oral))
        #expect(methylphenidate == MealOnsetDelay(minutes: 0, isGeneric: false))

        let mdmaSnack = try #require(MealState.light.onsetDelay(forSubstance: "MDMA", product: nil, route: .oral))
        #expect(mdmaSnack.minutes == 57)

        let unstudied = try #require(MealState.full.onsetDelay(forSubstance: "Sertraline", product: nil, route: .oral))
        #expect(unstudied.isGeneric)

        #expect(MealState.full.onsetDelay(forSubstance: "Alcohol", product: nil, route: .oral) == nil)
    }

    @Test @MainActor
    func `A logged meal shifts the entry's curve and a fasted one leaves it`() {
        let fed = DoseEntry(substance: "MDMA", amount: 100, route: .oral, meal: .full)
        #expect(fed.applyingMeal(to: base)?.onset == DurationRange(min: 134, max: 154))
        let fasted = DoseEntry(substance: "MDMA", amount: 100, route: .oral, meal: .empty)
        #expect(fasted.applyingMeal(to: base) == base)
        let snorted = DoseEntry(substance: "MDMA", amount: 100, route: .insufflation, meal: .full)
        #expect(snorted.applyingMeal(to: base) == base)
    }
}
