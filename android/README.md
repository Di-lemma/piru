# Piru on Android

The iOS app, built for Android from the same sources. Nothing is ported by hand: the build
stages `Piru/` and `Shared/` into a Skip Fuse package (native Swift on Android, SwiftUI bridged
to Jetpack Compose) and applies a fixed set of changes, the way ungoogled-chromium carries a
patch series over upstream. A Piru release is an Android release: rebuild, and fix any patch
that no longer applies.

## Where it stands (2026-09-29)

- **The whole app runs on an Android 36 emulator.** Onboarding, Journal (vertical timeline, PK
  curves, My Meds, the session accessory), Library, Tools and Insights render from the iOS views.
  Search renders without its field and its class grid.
- **The iOS tree carries no Android code.** Every difference is one of:

| Where | What | Count |
|---|---|---|
| `exclude.txt` | iOS/macOS-only files the stage leaves out (`+iOS`, widgets, HealthKit, StoreKit, …) | 14 globs |
| `patches/series` | `git apply` patches, each with its reason on line 1 | 12 |
| `substitutions.txt` | regex rewrites applied to every staged file after the patches | 78 rules |
| `app/Sources/Piru/Android/` | stand-ins for what SkipFuseUI lacks (Canvas, Charts, Grid, …) | 23 files |
| `symbols.tsv` | SF Symbol → Material Symbol, fetched at a pinned commit | 286 rows |
| `vendor/` | patches to GRDB, skip and skipstone, served through SwiftPM mirrors | 5 |
| `Compat/` | SwiftData over GRDB (`PortableData`), `os`, CryptoKit, CoreLocation | 8 modules |

## Building

```bash
android/tools/setup.sh         # once: toolchain, Android SDK/NDK, emulator (~6 GB, on the SSD)
pipeline/fetch-db.sh           # the catalog, as for any checkout
android/tools/build-app.sh     # stage + both Skip phases; ~3 min incremental, ~9 min clean
android/tools/package-apk.sh   # Gradle → APK, installs on a running emulator
android/tools/launch.sh shot   # restart, screenshot to $PIRU_ANDROID/build/shot.png, fatal lines
```

`PIRU_CONFIG=release` on both scripts builds the optimized APK. The debug build's deep
bridged view stacks can overflow the main thread's stack (quick log did).

### Driving the emulator

`android/tools/droid` is the `axe` of this setup: adb and uiautomator, nothing to install.
Labels are the SwiftUI accessibility labels, as Compose reports them.

```bash
android/tools/droid restart                       # force-stop and relaunch Piru
android/tools/droid wait --label Journal          # until it is up
android/tools/droid tap --label "Record an entry" # --index N when a label repeats
android/tools/droid tree                          # labels with center coordinates
android/tools/droid shot quicklog                 # → $PIRU_ANDROID/build/quicklog.png
android/tools/droid logs                          # the app's fatal and error lines
```

"The UI never went idle" means the app is hung or animating without end. The emulator needs
6 GB (`setup.sh` sets it): at 2 GB the app's startup is killed under memory pressure.

`build-app.sh` writes every compiler error to `$PIRU_ANDROID/build/app.errors`. To change an
upstream file for Android: edit it in place, `android/tools/mkpatch.py <name> <paths> --message
"why"`, then `git checkout -- <paths>`. `stage.py --check` reports patches that no longer apply.

### What the build does that Skip's own tooling would

- **Two phases, run by hand.** Phase 1 is Skip's iOS-triple pre-build: its skipstone plugin
  writes the Kotlin side before anything compiles, and the compile after it fails by design.
  Phase 2 is the bridge build, in its own scratch path, into the jni-libs Gradle packages.
  Gradle's own Swift build is disabled because it would resolve an unpatched skipstone.
- **Resources:** `Bundle.module` is SwiftPM's Darwin accessor, which no Android bundle answers;
  `AndroidResources.bundle` maps to the module assets, and file resources (the catalog) are
  copied out of the APK. Info.plist values are generated from `Piru/Info.plist`.
- **Assets:** SkipUI finds an asset by folder name alone, so the catalog is flattened to
  namespaced names (`surface__background`) and the generated symbols ask for those.

## Known gaps

- **Skins:** none on Android (patch 0014): no Skins menu entries, and the app wears the piru
  skin.
- **Not wired on Android:** sharing files (ACTION_SEND), file import/export, notification
  actions, Health Connect, location search, widgets.
- **Material Symbols' license** is staged into `Resources/Licenses` but not listed in About.

## The shared core (the earlier headless build)

### The compatibility layers

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
