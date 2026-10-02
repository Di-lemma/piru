import SwiftUI
import UserNotifications

/// The whole of the legacy build: Piru lives in a new app, and this one only
/// points there. The journal stays out of reach so the build cannot quietly
/// remain someone's journal until TestFlight expires it and takes the app away.
///
/// Before the new app has run on this device it says the move is automatic;
/// after, it says the journal is already there. The handoff itself runs
/// outside this view (``LegacyHandoff``), from `PiruApp`.
struct AppMovedView: View {
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase
    @State private var successorHasImported = LegacyHandoff.successorImportedAt != nil

    var body: some View {
        ScrollView {
            VStack(spacing: Spacing.xxl) {
                Image(systemName: "shippingbox.fill")
                    .font(.system(size: 64))
                    .foregroundStyle(.tint)
                    .accessibilityHidden(true)

                title
                    .font(.piru(.title, weight: .bold))
                    .multilineTextAlignment(.center)
                    .accessibilityAddTraits(.isHeader)

                message
                    .font(.body)
                    .foregroundStyle(Theme.secondaryLabel)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)

                GlassPillButton(title: "Open in TestFlight") {
                    openURL(AppIdentity.successorTestFlightURL)
                }
            }
            .padding(.horizontal, Spacing.xxxl)
            .frame(maxWidth: 480)
            .frame(maxWidth: .infinity)
        }
        .defaultScrollAnchor(.center)
        .scrollBounceBehavior(.basedOnSize)
        .task(id: scenePhase) {
            guard scenePhase == .active else { return }
            successorHasImported = LegacyHandoff.successorImportedAt != nil
            if successorHasImported { await Self.retireReminders() }
        }
    }

    @ViewBuilder
    private var title: some View {
        if successorHasImported {
            Text("Your journal has moved")
        } else {
            Text("Piru has moved")
        }
    }

    @ViewBuilder
    private var message: some View {
        if successorHasImported {
            Text("The new Piru app already has your journal. Open it there to keep logging.")
        } else {
            Text("Piru now lives in a new app. Install it on this device and the first time you open it, your journal, meds and settings come across on their own. Nothing here is deleted.")
        }
    }

    /// Once the new app holds the journal it schedules its own reminders and
    /// Live Activity, so this build's would arrive twice.
    private static func retireReminders() async {
        let center = UNUserNotificationCenter.current()
        center.removeAllPendingNotificationRequests()
        center.removeAllDeliveredNotifications()
        await LiveActivityManager.shared.deleteJournalActivities()
    }
}
