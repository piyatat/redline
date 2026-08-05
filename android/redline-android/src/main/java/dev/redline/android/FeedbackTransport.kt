package dev.redline.android

import android.util.Log
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import java.net.ConnectException
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
        try {
            val response = client.newCall(builder.build()).execute()
            response.use {
                if (!it.isSuccessful) {
                    val hint = when (it.code) {
                        401 -> " — set DesignerOverlay(apiToken=…) or REDLINE_API_TOKEN to match Redline.app Settings"
                        else -> ""
                    }
                    throw FeedbackTransportException("Feedback POST failed with HTTP ${it.code}$hint")
                }
            }
            Log.i(TAG, "feedback OK → $baseUrl")
        } catch (e: FeedbackTransportException) {
            throw e
        } catch (e: ConnectException) {
            throw FeedbackTransportException(connectFailureMessage(baseUrl), e)
        } catch (e: java.net.SocketTimeoutException) {
            throw FeedbackTransportException(connectFailureMessage(baseUrl), e)
        } catch (e: java.io.IOException) {
            // OkHttp often wraps ConnectException.
            val root = generateSequence(e as Throwable) { it.cause }.firstOrNull { it is ConnectException }
            if (root != null) {
                throw FeedbackTransportException(connectFailureMessage(baseUrl), e)
            }
            throw FeedbackTransportException("${e.message ?: "Network error"} ($baseUrl)", e)
        }
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
            if (fromEnv != null) return fromEnv
            // Emulator: 10.0.2.2 → host Mac loopback. Device: 127.0.0.1 via adb reverse.
            return if (RedlineDefines.isEmulator()) {
                RedlineDefines.EMULATOR_HOST_FEEDBACK_URL
            } else {
                RedlineDefines.DEFAULT_FEEDBACK_URL
            }
        }

        fun apiToken(): String? = shared.resolveApiToken()

        private fun connectFailureMessage(url: String): String {
            val hint = when {
                url.contains("127.0.0.1") && RedlineDefines.isEmulator() ->
                    " Emulator cannot use 127.0.0.1 for the Mac — reinstall so Redline defaults to 10.0.2.2."
                url.contains("127.0.0.1") ->
                    " On a physical device run: adb reverse tcp:8765 tcp:8765"
                else ->
                    " Is Redline.app running on the Mac (127.0.0.1:8765)?"
            }
            return "Failed to connect to $url.$hint"
        }
    }

    private fun resolveApiToken(): String? =
        configuredApiToken
            ?: System.getenv(RedlineDefines.ENV_API_TOKEN)
                ?.trim()
                ?.takeIf { it.isNotEmpty() }
}

class FeedbackTransportException(
    message: String,
    cause: Throwable? = null,
) : Exception(message, cause)
