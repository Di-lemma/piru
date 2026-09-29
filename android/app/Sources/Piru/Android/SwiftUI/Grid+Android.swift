// LazyVGrid for Android (substitutions.txt renames it). Skip's lazy grid lays out nothing
// inside a scroll view, which is where every upstream grid sits, so the children are handed
// to Compose's FlowRow as rows of equal cells (Skip/AndroidGridComposer.kt). Every upstream
// grid has flexible columns; the first column's spacing separates cells.

import SkipBridge
import SwiftUI

struct AndroidVGrid<Content: View>: View {
    let columns: [GridItem]
    let spacing: CGFloat?
    let content: Content

    init(
        columns: [GridItem], alignment _: HorizontalAlignment = .center, spacing: CGFloat? = nil,
        pinnedViews _: PinnedScrollableViews = PinnedScrollableViews(), @ViewBuilder content: () -> Content,
    ) {
        self.columns = columns
        self.spacing = spacing
        self.content = content()
    }

    var body: some View {
        let children = content.Java_viewOrEmpty
        let columnCount = columns.count
        let columnSpacing = Double(columns.first?.spacing ?? 8)
        let rowSpacing = Double(spacing ?? 8)
        return ComposeView {
            try! AnyDynamicObject(
                className: "piru.module.AndroidGridComposer", columnCount, columnSpacing, rowSpacing, children,
            )
        }
    }
}
