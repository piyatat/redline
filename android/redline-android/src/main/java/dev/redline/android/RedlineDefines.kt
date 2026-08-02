package dev.redline.android

object RedlineDefines {
    const val FEEDBACK_DEFAULT_PORT = 8765
    const val FEEDBACK_ROUTE = "/feedback"
    const val DEFAULT_FEEDBACK_URL = "http://127.0.0.1:$FEEDBACK_DEFAULT_PORT$FEEDBACK_ROUTE"
    const val ENV_FEEDBACK_URL = "REDLINE_FEEDBACK_URL"
    const val ENV_API_TOKEN = "REDLINE_API_TOKEN"
    const val SCREEN_REGION = "Screen"
}
