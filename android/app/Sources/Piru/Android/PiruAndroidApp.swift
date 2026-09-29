// The Android entry point, standing in for Piru/PiruApp.swift (excluded: its `@main App`
// is Darwin-only). Skip's generated MainActivity shows `PiruRootView` and forwards the
// activity lifecycle to `PiruAppDelegate`. The launch work is PiruApp's, minus what Android
// has no counterpart for: widgets, Live Activities, the watch, background tasks, HealthKit.

import Foundation
import SkipFuse
import SwiftData
import SwiftUI

/* SKIP @bridge */public struct PiruRootView: View {
    /* SKIP @bridge */public init() {}

    public var body: some View {
        ContentView()
            .modelContainer(PiruAndroidLaunch.container)
            .task {
                await PiruAndroidLaunch.afterFirstFrame()
            }
    }
}

/* SKIP @bridge */public final class PiruAppDelegate: Sendable {
    /* SKIP @bridge */public static let shared = PiruAppDelegate()

    private init() {}

    /* SKIP @bridge */public func onInit() {}
    /* SKIP @bridge */public func onLaunch() {}
    /* SKIP @bridge */public func onResume() {}
    /* SKIP @bridge */public func onPause() {}
    /* SKIP @bridge */public func onStop() {}
    /* SKIP @bridge */public func onDestroy() {}
    /* SKIP @bridge */public func onLowMemory() {}
}

@MainActor
enum PiruAndroidLaunch {
    static let container: ModelContainer = {
        // iOS creates an app's Documents folder with its sandbox; Android's files/Documents
        // exists only once made, and the stores inside it cannot open without it.
        for directory in [FileManager.SearchPathDirectory.documentDirectory, .applicationSupportDirectory, .cachesDirectory] {
            if let url = FileManager.default.urls(for: directory, in: .userDomainMask).first {
                try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            }
        }
        let storeURL = StoreRecovery.canonicalStoreURL()
        let container: ModelContainer
        do {
            container = try ModelContainer(
                for: Schema(PiruSchema.models),
                configurations: ModelConfiguration(url: storeURL, cloudKitDatabase: .none),
            )
        } catch {
            fatalError("Failed to open the journal store: \(error)")
        }
        UserProfileStore.shared.configure(container: container)
        ToleranceStore.shared.configure(container: container)
        BodyLevelsManager.shared.configure(container: container)
        CustomSubstanceStore.shared.configure(container: container)
        CustomUnitStore.shared.configure(container: container)
        NotificationPreferencesStore.shared.configure(container: container)
        SkinStore.activate()
        return container
    }()

    /// PiruApp's launch `.task`, for the parts with an Android counterpart.
    static func afterFirstFrame() async {
        _ = SubstanceStore.shared.count
        await SubstanceStore.shared.ensureAllLoaded()
        SubstanceColorStore.installCatalogTints()
        SubstanceColorStore.refreshDefaults(in: container.mainContext)
        _ = SearchHistoryStore.shared.recent
        SessionService.ensureSessionsPopulated(in: container.mainContext)
        // Folded routines first, then the reminder horizon rolled forward, as PiruApp does.
        MedsMigrator.foldRoutinesIfNeeded(context: container.mainContext)
        await DoseNotificationManager.syncMedRemindersIfNeeded(container: container)
        #if DEBUG
            if !DemoData.insertImportFileData(container: container),
               !DemoData.insertPersonaData(container: container) {
                DemoData.insertDefaultData(container: container)
            }
        #endif
    }
}
