package dev.redline.android.demo

import dev.redline.android.DesignerContext
import dev.redline.android.DesignerPin

object DemoDesignerContext : DesignerContext {
    override fun pins(screen: String, region: String): List<DesignerPin> = when (region) {
        "Header" -> listOf(DesignerPin(component = "Title", pin = "size=lg"))
        "Hero" -> listOf(DesignerPin(component = "Card", pin = "elevation=2"))
        "CTA" -> listOf(DesignerPin(component = "Button", pin = "color=red, fillWidth=true"))
        else -> emptyList()
    }
}
