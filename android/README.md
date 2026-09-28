# Piru on Android — the shared core

The app's own Swift, compiled for Android from the same files the iOS build compiles. Nothing
here is a port: `PiruCore/Sources/Piru/` is a directory of symlinks into `Piru/` and `Shared/`,
and every difference between the platforms lives in a small module named after the Apple
framework it stands in for, so each shared file keeps its `import` line and its call sites.

## Where it stands (2026-09-29)

- **The core builds for Android arm64.** 107 files, 26k lines: the PK/PD engines, pharmacology,
  domain types, the substance catalog store (GRDB), the interaction checker, and ten SwiftData
  models.
- **It runs.** `tools/run-smoke.sh` runs `piru-smoke` on an Android 36 emulator. It resolves
  caffeine from the real 18 MB catalog, runs the PK model, saves and reloads a journal through
  SwiftData's API, and reads zh-Hans from `Localizable.xcstrings`. The output is identical to
  the same binary on macOS.
- **iOS is unchanged in behavior.** The refactors this needed (below) build for every target
  and pass all 2,218 tests.
- **Size:** the stripped release smoke binary is 62 MB (≈25 MB gzipped). Most of that is the
  statically linked Swift runtime, Foundation and ICU, which any Swift-on-Android app carries.

## The compatibility layers

| Apple module | Stand-in | What it does |
|---|---|---|
| `SwiftData` | `PortableData` (+ `PortableDataMacros`) | `@Model`, `ModelContainer`, `ModelContext`, `FetchDescriptor` over one SQLite table. Predicates and sorts are Foundation's own, evaluated in memory |
| `os`, `OSLog` | `Sources/os` | `Logger` to logcat, `OSAllocatedUnfairLock` over `Mutex`, no-op signposts |
| `CryptoKit` | re-export of `swift-crypto` | Apple's API-compatible open-source build |
| `CoreLocation` | `Sources/CoreLocation` | `CLLocationCoordinate2D` |
| Foundation localization | `_Compat/Localization+Portable.swift` | `LocalizedStringResource` and `String(localized:)`, reading the same xcstrings file. Keys are minted the way Xcode extracts them |
| Foundation's Observation re-export | `-import-module Observation` | `@Observable` under `import Foundation`, as on Apple platforms |
| system SQLite | `tools/build-sqlite.sh` | the amalgamation built with Apple's compile options. `USE_URI` is load-bearing: the catalog opens as `file:…?immutable=1` |

## The refactors the app took

Each one also improves the iOS layering; none changes behavior.

1. `Color` members moved into `+SwiftUI.swift` companions for `P3Color`, `SubstanceCategory`,
   `RouteOfAdministration`, `InteractionSeverity` and `SubstanceColor`. The watch target lists
   `P3Color+SwiftUI.swift` explicitly.
2. `import SwiftUI` replaced with `Foundation` where nothing from SwiftUI was used: `Substance`,
   `DoseRange`, `SubstanceMetadata`, `SubstancePharmacology` and `UserProfile`.
3. Models were moved out of view files:
   - `ActiveMetabolite` (it lived in `ActiveMetaboliteCard.swift`) → `Data/Pharmacology/`.
   - `DoseMarker` → `Shared/Engines/`.
   - The `ActiveSubstanceState` builders → `ActiveSubstanceState+Builders.swift`.
4. `StagedDose.lookupReferenceDose` became `Substance.referenceDose(route:unit:…)`.
5. `SubstanceReadModel+Signatures.swift` imports Foundation itself instead of leaning on the
   bridging header's implicit import.

## Things that matter for the next step

- **Models are nonisolated.** SwiftData's `@Model` declares `PersistentModel`, which refines
  `SendableMetatype`, on the class itself, and that keeps it out of `-default-isolation MainActor`.
  `PortableData` mirrors it. Otherwise key paths into a model are not `Sendable`, and
  `#Predicate` and `SortDescriptor` reject them.
- **`PortableData` gaps**, all fine for the smoke test and all needed before a UI:
  - No observation: views would not refresh on edits.
  - An inverse side (`Session.doses`) is rebuilt on load and save, not on assignment.
  - No cascade delete.
  - Contexts do not merge each other's saves.
  - Every save rewrites the working set.
  - No `@Query`.
- **Two identity seams need a host answer on Android:**
  - `SubstanceStore.shared` finds the catalog through `Bundle.main`.
  - `AppIdentity` reads `PiruBundleID` from `Info.plist`.

  Both work today because the smoke binary's directory is its bundle. An APK will need the same.
- **`localizedStandardContains` in a `#Predicate`** is unsupported by open-source Foundation. The
  core does not use it; app views might.
- **FoundationMacros comes from Xcode.** The swift.org macOS toolchain lacks the plugin. Building
  it from swift-foundation would remove the dependency.

## Running it

```bash
android/tools/setup.sh        # once: toolchain, Android SDK, NDK, SQLite, emulator (~6 GB)
android/tools/run-smoke.sh    # build for Android, boot the emulator if needed, run → PASS
cd android/PiruCore && swift test --filter PortableData   # the SwiftData stand-in, on macOS
```

`PIRU_ANDROID` (default `/Volumes/Ugreen/Projects/piru-android`) holds everything large. The
catalog comes from `pipeline/fetch-db.sh` like any checkout.

`tools/closure.py` recomputes which app files the core needs; `tools/split_members.py` does the
`+SwiftUI` split.
