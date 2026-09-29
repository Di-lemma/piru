// Piru/Views/Components/FlowLayout.swift for Android. The upstream type is a custom `Layout`,
// a protocol SkipFuseUI does not provide, so the children are handed to Compose's FlowRow
// (Skip/AndroidFlowComposer.kt), which wraps them the same way. Call sites are unchanged:
// `FlowLayout(spacing:) { … }` reaches `callAsFunction`, as a Layout's does.

import SkipBridge
import SwiftUI

struct FlowLayout {
    var spacing: CGFloat = 8

    func callAsFunction<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        let children = content().Java_viewOrEmpty
        return ComposeView {
            try! AnyDynamicObject(className: "piru.module.AndroidFlowComposer", Double(spacing), children)
        }
    }
}
