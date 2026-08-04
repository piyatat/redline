package dev.redline.android

import android.os.Build

object RedlineDefines {
    const val FEEDBACK_DEFAULT_PORT = 8765
    const val FEEDBACK_ROUTE = "/feedback"
    /** Physical device / adb reverse. Emulators should use [EMULATOR_HOST_FEEDBACK_URL]. */
    const val DEFAULT_FEEDBACK_URL = "http://127.0.0.1:$FEEDBACK_DEFAULT_PORT$FEEDBACK_ROUTE"
    /** Android emulator alias for the host machine’s loopback (Mac Redline.app). */
    const val EMULATOR_HOST = "10.0.2.2"
    const val EMULATOR_HOST_FEEDBACK_URL =
        "http://$EMULATOR_HOST:$FEEDBACK_DEFAULT_PORT$FEEDBACK_ROUTE"
    const val ENV_FEEDBACK_URL = "REDLINE_FEEDBACK_URL"
    const val ENV_API_TOKEN = "REDLINE_API_TOKEN"
    const val SCREEN_REGION = "Screen"

    /** True on AVD / common emulators — `127.0.0.1` is the guest, not the Mac. */
    fun isEmulator(): Boolean {
        val fingerprint = Build.FINGERPRINT
        val model = Build.MODEL
        val product = Build.PRODUCT
        val hardware = Build.HARDWARE
        val manufacturer = Build.MANUFACTURER
        return fingerprint.startsWith("generic")
            || fingerprint.contains("emulator", ignoreCase = true)
            || fingerprint.contains("unknown", ignoreCase = true)
            || model.contains("google_sdk", ignoreCase = true)
            || model.contains("Emulator", ignoreCase = true)
            || model.contains("Android SDK built for", ignoreCase = true)
            || manufacturer.contains("Genymotion", ignoreCase = true)
            || hardware.contains("goldfish", ignoreCase = true)
            || hardware.contains("ranchu", ignoreCase = true)
            || product.contains("sdk", ignoreCase = true)
            || product.contains("emulator", ignoreCase = true)
            || product.contains("simulator", ignoreCase = true)
            || Build.BOARD.contains("nova", ignoreCase = true)
    }
}
