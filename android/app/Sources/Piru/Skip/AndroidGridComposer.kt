// The Compose side of AndroidVGrid (Android/SwiftUI/Grid+Android.swift): SwiftUI children in
// rows of `columns` equal cells, the way a LazyVGrid of flexible columns lays them out.
package piru.module

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import skip.ui.ComposeBuilder
import skip.ui.ComposeContext
import skip.ui.ContentComposer
import skip.ui.View

class AndroidGridComposer(
    private val columns: Int,
    private val columnSpacing: Double,
    private val rowSpacing: Double,
    bridgedContent: Any,
) : ContentComposer {
    private val content = ComposeBuilder.from { bridgedContent as View }

    @OptIn(ExperimentalLayoutApi::class)
    @Composable
    override fun Compose(context: ComposeContext) {
        val renderables = content.Evaluate(context = context, options = 0).filter { !it.isSwiftUIEmptyView }
        val contentContext = context.content()
        val perRow = maxOf(1, columns)
        FlowRow(
            modifier = context.modifier,
            horizontalArrangement = Arrangement.spacedBy(columnSpacing.dp),
            verticalArrangement = Arrangement.spacedBy(rowSpacing.dp),
            maxItemsInEachRow = perRow,
        ) {
            for (renderable in renderables) {
                Box(modifier = Modifier.weight(1f)) { renderable.Render(context = contentContext) }
            }
            // A short last row keeps its cells column-wide instead of stretching across.
            val remainder = renderables.size % perRow
            if (remainder != 0) {
                repeat(perRow - remainder) { Box(modifier = Modifier.weight(1f)) {} }
            }
        }
    }
}
