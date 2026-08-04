package dev.redline.android.demo

import android.app.Application
import dev.redline.android.Redline

class DemoApplication : Application() {
    override fun onCreate() {
        super.onCreate()
        Redline.install(
            application = this,
            screen = "demo-home",
            spec = "screens/demo-home.screen.md",
            context = DemoDesignerContext,
        )
    }
}
