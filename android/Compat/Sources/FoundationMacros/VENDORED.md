# FoundationMacros

Copied from [swiftlang/swift-foundation](https://github.com/swiftlang/swift-foundation)
at tag `swift-6.4.0-RELEASE`, `Sources/FoundationMacros/`, under the Apache License 2.0 with
Runtime Library Exception (the repository's LICENSE.md).

Two changes from upstream: `BundleMacro.swift` is left out and its entry removed from
`FoundationMacros.swift`'s macro list. `#bundle` is unused here, and its source needs a newer
swift-syntax than the 602.x that Skip's tool pins in the same package graph.

It is the plugin that expands `#Predicate` and `#Expression`. Apple platforms load it from the
SDK and the swift.org macOS toolchain does not ship it, so a build for Android compiles it from
this copy. Its version must match the Foundation the Android SDK carries (the same tag as the
Swift SDK for Android): the expansion names API of that Foundation.

Refresh with the SDK: copy the directory from the new tag, redo the two changes above, and
update the tag.
