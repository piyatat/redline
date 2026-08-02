package dev.redline.android

import android.util.Log
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import java.util.concurrent.TimeUnit

class FeedbackTransport private constructor() {
    private val client = OkHttpClient.Builder()
        .connectTimeout(15, TimeUnit.SECONDS)
        .readTimeout(15, TimeUnit.SECONDS)
        .writeTimeout(15, TimeUnit.SECONDS)
        .build()

    @Volatile
    var baseUrl: String = defaultFeedbackUrl()
        private set

    @Volatile
    private var configuredApiToken: String? = null

    fun configure(baseUrl: String) {
        this.baseUrl = baseUrl.trim().ifEmpty { defaultFeedbackUrl() }
    }

    /** Prefer install(apiToken=…) over process env on stock Android. */
    fun configureApiToken(token: String?) {
        configuredApiToken = token?.trim()?.takeIf { it.isNotEmpty() }
    }

    suspend fun post(payload: FeedbackPayload) = withContext(Dispatchers.IO) {
        payload.validate()
        val body = payload.toJson().toString()
            .toRequestBody(JSON)
        val builder = Request.Builder()
            .url(baseUrl)
            .post(body)
            .header("Content-Type", "application/json")
        resolveApiToken()?.let { builder.header("Authorization", "Bearer $it") }
        val response = client.newCall(builder.build()).execute()
        response.use {
            if (!it.isSuccessful) {
                throw FeedbackTransportException("Feedback POST failed with HTTP ${it.code}")
            }
        }
        Log.i(TAG, "feedback OK → $baseUrl")
        Unit
    }

    companion object {
        private const val TAG = "Redline"
        private val JSON = "application/json; charset=utf-8".toMediaType()
        val shared = FeedbackTransport()

        fun defaultFeedbackUrl(): String {
            val fromEnv = System.getenv(RedlineDefines.ENV_FEEDBACK_URL)
                ?.trim()
                ?.takeIf { it.isNotEmpty() }
            return fromEnv ?: RedlineDefines.DEFAULT_FEEDBACK_URL
        }

        fun apiToken(): String? = shared.resolveApiToken()
    }

    private fun resolveApiToken(): String? =
        configuredApiToken
            ?: System.getenv(RedlineDefines.ENV_API_TOKEN)
                ?.trim()
                ?.takeIf { it.isNotEmpty() }
}

class FeedbackTransportException(message: String) : Exception(message)
