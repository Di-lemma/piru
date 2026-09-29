import Foundation
import Testing
@testable import Piru

/// ``TimelineStripBuilder/relativeWeights(states:lookback:)`` — the per-dose
/// weights behind the relative ``TimelineCurveScale`` choices: each dose is
/// measured against the tallest crest in the window before it.
@Suite("TimelineCurveScale")
struct TimelineCurveScaleTests {
    private let start = Date(timeIntervalSinceReferenceDate: 800_000_000)
    private let day: TimeInterval = 86400

    /// A four-hour curve peaking between 30 and 120 minutes.
    private func dose(daysIn: Double, magnitude: Double, amount: Double = 1, unscaled: Bool = false) -> ActiveSubstanceState {
        ActiveSubstanceState(
            substanceName: "Amphetamine",
            tint: P3Color(red: 0.929, green: 0.439, blue: 0.660),
            doseTimestamp: start.addingTimeInterval(daysIn * day),
            amount: amount,
            unit: "mg",
            route: "oral",
            onsetEndMinutes: 20,
            comeupEndMinutes: 30,
            peakEndMinutes: 120,
            offsetEndMinutes: 240,
            afterglowEndMinutes: nil,
            totalMinutes: 240,
            doseIntensity: min(magnitude, 1),
            doseMagnitude: magnitude,
            doseIsUnscaled: unscaled,
            tachyphylaxis: 0,
            comeupSpreadMinutes: nil,
            peakSpreadMinutes: nil,
            offsetSpreadMinutes: nil,
        )
    }

    @Test
    func `A lone dose fills the lane whatever its strength`() {
        let weights = TimelineStripBuilder.relativeWeights(states: [dose(daysIn: 0, magnitude: 0.2)], lookback: 7 * day)
        let crestShape = TimelineCurveModel.intensity(at: 75, for: dose(daysIn: 0, magnitude: 0.2))
        #expect(abs(weights[0] * crestShape - 1) < 1e-9)
    }

    @Test
    func `A lighter dose inside the window reads as a fraction of the larger one`() {
        let states = [dose(daysIn: 0, magnitude: 0.8), dose(daysIn: 3, magnitude: 0.4)]
        let weights = TimelineStripBuilder.relativeWeights(states: states, lookback: 7 * day)
        #expect(abs(weights[1] / weights[0] - 0.5) < 1e-9)
    }

    @Test
    func `A larger dose that has aged out of the window no longer shrinks the new one`() {
        let states = [dose(daysIn: 0, magnitude: 0.8), dose(daysIn: 10, magnitude: 0.4)]
        let week = TimelineStripBuilder.relativeWeights(states: states, lookback: 7 * day)
        #expect(abs(week[1] - week[0]) < 1e-9)
        let month = TimelineStripBuilder.relativeWeights(states: states, lookback: 30 * day)
        #expect(abs(month[1] / month[0] - 0.5) < 1e-9)
    }

    @Test
    func `All time measures an earlier dose against a later, larger one too`() {
        let states = [dose(daysIn: 0, magnitude: 0.4), dose(daysIn: 100, magnitude: 0.8)]
        let weights = TimelineStripBuilder.relativeWeights(states: states, lookback: .infinity)
        #expect(abs(weights[0] / weights[1] - 0.5) < 1e-9)
    }

    @Test
    func `A substance with no ladder is measured by its amounts`() {
        let states = [
            dose(daysIn: 0, magnitude: 0.6, amount: 200, unscaled: true),
            dose(daysIn: 1, magnitude: 0.6, amount: 50, unscaled: true),
        ]
        let weights = TimelineStripBuilder.relativeWeights(states: states, lookback: 7 * day)
        #expect(abs(weights[1] / weights[0] - 0.25) < 1e-9)
    }

    @Test
    func `A redose that stacks sets a taller reference than either dose alone`() {
        let single = TimelineStripBuilder.relativeWeights(states: [dose(daysIn: 0, magnitude: 0.5)], lookback: 7 * day)
        let redosed = TimelineStripBuilder.relativeWeights(
            states: [dose(daysIn: 0, magnitude: 0.5), dose(daysIn: 1.0 / 24, magnitude: 0.5)],
            lookback: 7 * day,
        )
        #expect(redosed[0] < single[0])
    }
}
