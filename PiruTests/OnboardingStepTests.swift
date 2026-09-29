import Testing
@testable import Piru

@Suite("OnboardingStep")
struct OnboardingStepTests {
    @Test
    func `With Health available, depth leads to the Health step`() {
        let flow = OnboardingStep.flow(healthAvailable: true)
        #expect(OnboardingStep.depth.next(in: flow) == .health)
        #expect(OnboardingStep.health.next(in: flow) == .reminders)
        #expect(OnboardingStep.progressSteps(in: flow).contains(.health))
    }

    @Test
    func `Without Health, depth leads straight to reminders`() {
        let flow = OnboardingStep.flow(healthAvailable: false)
        #expect(!flow.contains(.health))
        #expect(OnboardingStep.depth.next(in: flow) == .reminders)
        #expect(OnboardingStep.progressSteps(in: flow)
            == [.privacy, .tour, .depth, .reminders, .importData, .skins])
    }

    @Test(arguments: [true, false])
    func `The flow runs from welcome to done`(healthAvailable: Bool) {
        let flow = OnboardingStep.flow(healthAvailable: healthAvailable)
        #expect(flow.first == .welcome)
        #expect(flow.last == .done)
        #expect(OnboardingStep.done.next(in: flow) == nil)
    }
}
