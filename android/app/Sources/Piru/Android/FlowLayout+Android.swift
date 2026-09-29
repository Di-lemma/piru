// Piru/Views/Components/FlowLayout.swift for Android. The upstream type is a custom `Layout`,
// a protocol SkipFuseUI does not provide, so this one lays chips out in an adaptive grid:
// they wrap into as many columns as fit, aligned to a column grid instead of packed tight.
// Call sites are unchanged: `FlowLayout(spacing:) { … }` reaches `callAsFunction`, as a
// Layout's does.

import SwiftUI

struct FlowLayout {
    var spacing: CGFloat = 8

    func callAsFunction<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 96), spacing: spacing, alignment: .leading)],
            alignment: .leading,
            spacing: spacing
        ) {
            content()
        }
    }
}
