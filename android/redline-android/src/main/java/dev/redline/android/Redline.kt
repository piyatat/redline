package dev.redline.android

import android.app.Activity
import android.app.Application
import android.content.pm.ApplicationInfo
import android.content.res.Configuration
import android.graphics.Bitmap
import android.graphics.Canvas
import android.os.Build
import android.os.Bundle
import android.util.Base64
import android.util.Log
import android.view.View
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateListOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch
import java.io.ByteArrayOutputStream
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.TimeZone
import java.util.WeakHashMap
import java.util.concurrent.atomic.AtomicReference

/**
 * Debug-only designer capture for Android (markup → Feedback v1 → Redline.app).
 * No hierarchy TCP — that remains iOS-only.
 * Two-finger long-press (~450ms) toggles designer mode (same as iOS).
 */
object Redline {
    private const val TAG = "Redline"

    @Volatile
    var installed: Boolean = false
        private set

    var runtimeUserInfo: Map<String, String> = emptyMap()
        private set
    var runtimeNotes: String? = null

    private val applicationRef = AtomicReference<Application?>(null)
    private val activityRef = AtomicReference<Activity?>(null)
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)

    fun install(
        application: Application,
        screen: String = "app",
        spec: String? = null,
        state: String? = null,
        context: DesignerContext = EmptyDesignerContext,
        feedbackBaseUrl: String? = null,
        apiToken: String? = null,
    ) {
        if (!isDebuggable(application)) {
            Log.i(TAG, "install skipped — not a debug build")
            return
        }
        if (installed) {
            DesignerModeController.activate(screen, spec, state, context)
            feedbackBaseUrl?.trim()?.takeIf { it.isNotEmpty() }?.let {
                FeedbackTransport.shared.configure(it)
            }
            apiToken?.let { FeedbackTransport.shared.configureApiToken(it) }
            return
        }
        applicationRef.set(application)
        val url = feedbackBaseUrl?.trim()?.takeIf { it.isNotEmpty() }
            ?: FeedbackTransport.defaultFeedbackUrl()
        FeedbackTransport.shared.configure(url)
        apiToken?.let { FeedbackTransport.shared.configureApiToken(it) }
        DesignerModeController.activate(
            screen = screen,
            spec = spec,
            state = state,
            context = context,
        )
        application.registerActivityLifecycleCallbacks(activityCallbacks)
        installed = true
        Log.i(
            TAG,
            "installed → ${FeedbackTransport.shared.baseUrl}" +
                if (RedlineDefines.isEmulator()) " (emulator→host)" else " (device; use adb reverse)",
        )    }

    fun updateScreen(screen: String, spec: String? = null, state: String? = null) {
        if (!installed) return
        DesignerModeController.updateScreen(screen, spec, state)
    }

    fun setRuntimeUserInfo(info: Map<String, String>) {
        runtimeUserInfo = info
    }

    fun currentActivity(): Activity? = activityRef.get()

    fun application(): Application? = applicationRef.get()

    internal fun postFeedbackAsync(payload: FeedbackPayload, onResult: (Result<Unit>) -> Unit) {
        scope.launch(Dispatchers.IO) {
            val result = runCatching { FeedbackTransport.shared.post(payload) }
            launch(Dispatchers.Main) { onResult(result) }
        }
    }

    private fun isDebuggable(application: Application): Boolean =
        (application.applicationInfo.flags and ApplicationInfo.FLAG_DEBUGGABLE) != 0

    private val activityCallbacks = object : Application.ActivityLifecycleCallbacks {
        override fun onActivityResumed(activity: Activity) {
            activityRef.set(activity)
            // Post so we wrap after Activity / AndroidX finish setting Window.Callback.
            activity.window?.decorView?.post {
                if (activityRef.get() === activity) {
                    DesignerGestureInstaller.attachTo(activity)
                }
            }
        }

        override fun onActivityPaused(activity: Activity) {
            DesignerGestureInstaller.detachFrom(activity)
            if (activityRef.get() === activity) activityRef.set(null)
        }

        override fun onActivityCreated(activity: Activity, savedInstanceState: Bundle?) {}
        override fun onActivityStarted(activity: Activity) {}
        override fun onActivityStopped(activity: Activity) {}
        override fun onActivitySaveInstanceState(activity: Activity, outState: Bundle) {}
        override fun onActivityDestroyed(activity: Activity) {
            DesignerGestureInstaller.detachFrom(activity)
            if (activityRef.get() === activity) activityRef.set(null)
        }
    }
}

object DesignerModeController {
    const val SCREEN_REGION = RedlineDefines.SCREEN_REGION

    var isDesignerModeActive by mutableStateOf(false)
        private set
    var activeRegion by mutableStateOf<String?>(null)
        private set
    var showMarkup by mutableStateOf(false)
        private set
    var markupComment by mutableStateOf("")
    var strokes = mutableStateListOf<MarkupStroke>()
    var toolsUsed = mutableStateListOf<String>()
    var saveError by mutableStateOf<String?>(null)
        private set
    var isSaving by mutableStateOf(false)
        private set
    /** True only while decor is snapshotted — hides Saving overlay / region chrome from the PNG. */
    var isCapturing by mutableStateOf(false)
        private set
    var screenName: String = "app"
        private set
    var specPath: String? = null
        private set
    private var stateName: String? = null
    private var context: DesignerContext = EmptyDesignerContext

    private val regionCounts = WeakHashMap<Any, MutableMap<String, Int>>()

    fun activate(
        screen: String,
        spec: String?,
        state: String?,
        context: DesignerContext,
    ) {
        screenName = screen
        specPath = spec
        stateName = state
        this.context = context
    }

    fun updateScreen(screen: String, spec: String? = null, state: String? = null) {
        screenName = screen
        if (spec != null) specPath = spec
        if (state != null) stateName = state
    }

    fun toggleDesignerMode() {
        if (isSaving) return
        if (isDesignerModeActive) {
            isDesignerModeActive = false
            showMarkup = false
            activeRegion = null
            return
        }
        isDesignerModeActive = true
        if (RegionRegistry.regionCount == 0) {
            beginMarkup(SCREEN_REGION)
        }
    }

    fun beginScreenMarkup() = beginMarkup(SCREEN_REGION)

    fun beginMarkup(region: String) {
        if (isSaving) return
        activeRegion = region
        strokes.clear()
        toolsUsed.clear()
        markupComment = ""
        saveError = null
        showMarkup = true
        isDesignerModeActive = true
    }

    fun cancelMarkup() {
        if (isSaving) return
        showMarkup = false
        activeRegion = null
        saveError = null
    }

    fun pins(region: String): List<DesignerPin> = context.pins(screenName, region)

    fun registerRegion(owner: Any, name: String) {
        val map = regionCounts.getOrPut(owner) { mutableMapOf() }
        map[name] = (map[name] ?: 0) + 1
        RegionRegistry.refresh(regionCounts.values.flatMap { it.keys }.toSet())
    }

    fun unregisterRegion(owner: Any, name: String) {
        val map = regionCounts[owner] ?: return
        val next = (map[name] ?: 1) - 1
        if (next <= 0) map.remove(name) else map[name] = next
        if (map.isEmpty()) regionCounts.remove(owner)
        RegionRegistry.refresh(regionCounts.values.flatMap { it.keys }.toSet())
    }

    fun saveMarkup(onDone: ((Boolean) -> Unit)? = null) {
        val region = activeRegion ?: return
        if (isSaving) return
        isSaving = true
        saveError = null

        val comment = markupComment.trim().ifEmpty { "(no comment)" }
        val pins = pins(region)
        val strokeSnapshot = strokes.toList()
        val tools = toolsUsed.distinct()

        // Hide markup chrome for a clean UI shot, then bake strokes into the PNG for Mac/agent.
        showMarkup = false
        isCapturing = true
        val mainHandler = android.os.Handler(android.os.Looper.getMainLooper())
        val started = java.util.concurrent.atomic.AtomicBoolean(false)
        val captureAndPost = Runnable {
            if (!started.compareAndSet(false, true)) return@Runnable
            if (!isSaving) {
                isCapturing = false
                return@Runnable
            }
            val composite = SnapshotRenderer.captureDecorViewPngBase64(strokeSnapshot)
            isCapturing = false
            if (composite.isNullOrBlank()) {
                showMarkup = true
                isSaving = false
                saveError = "Could not capture screenshot"
                onDone?.invoke(false)
                return@Runnable
            }

            val payload = FeedbackPayload(
                screen = screenName,
                region = region,
                state = stateName,
                platform = "android",
                mode = currentUiMode(),
                spec = specPath,
                capturedTs = isoNow(),
                comment = comment,
                pins = pins,
                toolsUsed = tools,
                strokes = strokeSnapshot,
                compositePngBase64 = composite,
                runtime = RuntimeContextCapture.capture(),
            )

            Redline.postFeedbackAsync(payload) { result ->
                isSaving = false
                result.onSuccess {
                    activeRegion = null
                    markupComment = ""
                    strokes.clear()
                    toolsUsed.clear()
                    saveError = null
                    onDone?.invoke(true)
                }.onFailure { err ->
                    showMarkup = true
                    saveError = err.message ?: "Save failed"
                    Log.e("Redline", "saveMarkup failed", err)
                    onDone?.invoke(false)
                }
            }
        }

        // Wait for Compose to remove MarkupSheet (next pre-draw), then one frame — mirrors iOS yield+delay.
        // Always schedule on the main Handler so Activity/decor teardown cannot drop isSaving forever.
        val decor = Redline.currentActivity()?.window?.decorView
        if (decor != null) {
            val observer = decor.viewTreeObserver
            observer.addOnPreDrawListener(object : android.view.ViewTreeObserver.OnPreDrawListener {
                override fun onPreDraw(): Boolean {
                    if (observer.isAlive) {
                        observer.removeOnPreDrawListener(this)
                    }
                    mainHandler.postDelayed(captureAndPost, 50L)
                    return true
                }
            })
            decor.invalidate()
            // Safety net if pre-draw never fires (detached view).
            mainHandler.postDelayed(captureAndPost, 200L)
        } else {
            mainHandler.postDelayed(captureAndPost, 50L)
        }
    }

    private fun currentUiMode(): String {
        val app = Redline.application() ?: return "light"
        val night = app.resources.configuration.uiMode and Configuration.UI_MODE_NIGHT_MASK
        return if (night == Configuration.UI_MODE_NIGHT_YES) "dark" else "light"
    }

    private fun isoNow(): String {
        val fmt = SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss'Z'", Locale.US)
        fmt.timeZone = TimeZone.getTimeZone("UTC")
        return fmt.format(Date())
    }
}

object RegionRegistry {
    var regionCount: Int = 0
        private set
    var regions: Set<String> = emptySet()
        private set

    fun refresh(names: Set<String>) {
        regions = names
        regionCount = names.size
    }
}

object SnapshotRenderer {
    private const val StrokeWidthPx = 3f

    /**
     * Captures the activity window, then draws [strokes] into the PNG so Mac/agent
     * receive markup visually (not only as JSON vectors).
     */
    fun captureDecorViewPngBase64(strokes: List<MarkupStroke> = emptyList()): String? {
        val activity = Redline.currentActivity() ?: return null
        val view = activity.window?.decorView ?: return null
        if (view.width <= 0 || view.height <= 0) {
            view.measure(
                View.MeasureSpec.makeMeasureSpec(view.resources.displayMetrics.widthPixels, View.MeasureSpec.EXACTLY),
                View.MeasureSpec.makeMeasureSpec(view.resources.displayMetrics.heightPixels, View.MeasureSpec.EXACTLY),
            )
            view.layout(0, 0, view.measuredWidth, view.measuredHeight)
        }
        val w = view.width
        val h = view.height
        if (w <= 0 || h <= 0) return null
        val bitmap = Bitmap.createBitmap(w, h, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(bitmap)
        view.draw(canvas)

        if (strokes.isNotEmpty()) {
            // Compose overlay is rooted at the content view; map stroke coords into decor space.
            val content = activity.findViewById<View>(android.R.id.content)
            val origin = IntArray(2)
            content?.getLocationInWindow(origin)
            val ox = origin[0].toFloat()
            val oy = origin[1].toFloat()
            drawStrokes(canvas, strokes, ox, oy)
        }

        val stream = ByteArrayOutputStream()
        bitmap.compress(Bitmap.CompressFormat.PNG, 100, stream)
        bitmap.recycle()
        return Base64.encodeToString(stream.toByteArray(), Base64.NO_WRAP)
    }

    private fun drawStrokes(
        canvas: Canvas,
        strokes: List<MarkupStroke>,
        offsetX: Float,
        offsetY: Float,
    ) {
        val paint = android.graphics.Paint(android.graphics.Paint.ANTI_ALIAS_FLAG).apply {
            style = android.graphics.Paint.Style.STROKE
            strokeWidth = StrokeWidthPx
            strokeCap = android.graphics.Paint.Cap.ROUND
            strokeJoin = android.graphics.Paint.Join.ROUND
        }
        for (stroke in strokes) {
            paint.color = strokeColor(stroke.color)
            val pts = stroke.points.mapNotNull { pair ->
                if (pair.size < 2) null
                else android.graphics.PointF(pair[0].toFloat() + offsetX, pair[1].toFloat() + offsetY)
            }
            if (pts.isEmpty()) continue
            when (stroke.tool) {
                "rect" -> {
                    val a = pts.first()
                    val b = pts.last()
                    canvas.drawRect(
                        minOf(a.x, b.x),
                        minOf(a.y, b.y),
                        maxOf(a.x, b.x),
                        maxOf(a.y, b.y),
                        paint,
                    )
                }
                "arrow" -> {
                    val a = pts.first()
                    val b = pts.last()
                    canvas.drawLine(a.x, a.y, b.x, b.y, paint)
                    val angle = kotlin.math.atan2((b.y - a.y).toDouble(), (b.x - a.x).toDouble())
                    val head = 14.0
                    canvas.drawLine(
                        b.x,
                        b.y,
                        (b.x - head * kotlin.math.cos(angle - Math.PI / 6)).toFloat(),
                        (b.y - head * kotlin.math.sin(angle - Math.PI / 6)).toFloat(),
                        paint,
                    )
                    canvas.drawLine(
                        b.x,
                        b.y,
                        (b.x - head * kotlin.math.cos(angle + Math.PI / 6)).toFloat(),
                        (b.y - head * kotlin.math.sin(angle + Math.PI / 6)).toFloat(),
                        paint,
                    )
                }
                else -> {
                    if (pts.size < 2) continue
                    val path = android.graphics.Path().apply {
                        moveTo(pts.first().x, pts.first().y)
                        for (i in 1 until pts.size) lineTo(pts[i].x, pts[i].y)
                    }
                    canvas.drawPath(path, paint)
                }
            }
        }
    }

    private fun strokeColor(id: String): Int = when (id) {
        "green" -> 0xFF34C759.toInt()
        "neutral" -> 0xFF737373.toInt()
        else -> 0xFFFF3B30.toInt()
    }
}

object RuntimeContextCapture {
    fun capture(): AppRuntimeContext {
        val app = Redline.application()
        val pm = app?.packageManager
        val info = runCatching {
            if (app != null && pm != null) pm.getPackageInfo(app.packageName, 0) else null
        }.getOrNull()
        val metrics = app?.resources?.displayMetrics
        val config = app?.resources?.configuration
        val orientation = when (config?.orientation) {
            Configuration.ORIENTATION_LANDSCAPE -> "landscape"
            Configuration.ORIENTATION_PORTRAIT -> "portrait"
            else -> "unknown"
        }
        val night = config?.uiMode?.and(Configuration.UI_MODE_NIGHT_MASK)
        val style = if (night == Configuration.UI_MODE_NIGHT_YES) "dark" else "light"
        val appLabel = if (app != null && pm != null) {
            app.applicationInfo.loadLabel(pm).toString()
        } else {
            null
        }
        return AppRuntimeContext(
            bundleId = app?.packageName,
            appName = appLabel,
            appVersion = info?.versionName,
            buildNumber = if (Build.VERSION.SDK_INT >= 28) {
                info?.longVersionCode?.toString()
            } else {
                @Suppress("DEPRECATION")
                info?.versionCode?.toString()
            },
            deviceModel = Build.MODEL,
            systemName = "Android",
            systemVersion = Build.VERSION.RELEASE,
            isSimulator = isEmulator(),
            localeIdentifier = Locale.getDefault().toLanguageTag(),
            timeZoneIdentifier = TimeZone.getDefault().id,
            screenBounds = metrics?.let { "${it.widthPixels}x${it.heightPixels}" },
            orientation = orientation,
            interfaceStyle = style,
            userInfo = Redline.runtimeUserInfo.takeIf { it.isNotEmpty() },
            notes = Redline.runtimeNotes,
        )
    }

    private fun isEmulator(): Boolean {
        return (Build.FINGERPRINT.startsWith("generic")
            || Build.FINGERPRINT.lowercase().contains("emulator")
            || Build.MODEL.contains("Emulator")
            || Build.MANUFACTURER.contains("Genymotion")
            || Build.PRODUCT.contains("sdk")
            || Build.HARDWARE.contains("goldfish")
            || Build.HARDWARE.contains("ranchu"))
    }
}
