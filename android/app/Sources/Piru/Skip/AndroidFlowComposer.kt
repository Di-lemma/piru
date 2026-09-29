// The Compose side of FlowLayout (Android/FlowLayout+Android.swift): SwiftUI children laid
// out by FlowRow, which wraps them onto as many lines as they need, as the iOS Layout does.
package piru.module

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.runtime.Composable
import androidx.compose.ui.unit.dp
import skip.ui.ComposeBuilder
import skip.ui.ComposeContext
import skip.ui.ContentComposer
import skip.ui.View

class AndroidFlowComposer(private val spacing: Double, bridgedContent: Any) : ContentComposer {
    private val content = ComposeBuilder.from { bridgedContent as View }

    @OptIn(ExperimentalLayoutApi::class)
    @Composable
    override fun Compose(context: ComposeContext) {
        val renderables = content.Evaluate(context = context, options = 0).filter { !it.isSwiftUIEmptyView }
        val contentContext = context.content()
        FlowRow(
            modifier = context.modifier,
            horizontalArrangement = Arrangement.spacedBy(spacing.dp),
            verticalArrangement = Arrangement.spacedBy(spacing.dp),
        ) {
            for (renderable in renderables) {
                renderable.Render(context = contentContext)
            }
        }
    }
}
