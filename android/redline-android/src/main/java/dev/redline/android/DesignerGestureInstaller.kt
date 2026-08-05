package dev.redline.android

import android.app.Activity
import android.os.Handler
import android.os.Looper
import android.view.MotionEvent
import android.view.Window
import java.util.Collections
import java.util.WeakHashMap

/**
 * Two-finger long-press to toggle designer mode (parity with iOS).
 *
 * Observes touches via [Window.Callback] so Compose-consumed events are still seen.
 * A decor [android.view.View.OnTouchListener] does not work once children handle the stream.
 */
internal object DesignerGestureInstaller {
    private const val HOLD_MS = 450L
    /** Generous — fingers drift during a hold; too-tight slop cancels before fire. */
    private const val SLOP_PX = 120f

    private val installed =
        Collections.newSetFromMap(WeakHashMap<Activity, Boolean>())

    fun attachTo(activity: Activity) {
        val window = activity.window ?: return
        when (val original = window.callback) {
            is ObservingWindowCallback -> {
                installed.add(activity)
                return
            }
            null -> return
            else -> {
                // Re-wrap if another library stole Window.Callback after we attached.
                if (installed.contains(activity) && original !is ObservingWindowCallback) {
                    installed.remove(activity)
                }
                if (!installed.add(activity)) return
                val tracker = TwoFingerLongPressTracker(
                    holdMs = HOLD_MS,
                    slopPx = SLOP_PX,
                    onTriggered = {
                        android.util.Log.i("Redline", "two-finger long-press → toggle designer")
                        activity.runOnUiThread {
                            DesignerModeController.toggleDesignerMode()
                        }
                    },
                )
                window.callback = ObservingWindowCallback(original, tracker)
            }
        }
    }

    fun detachFrom(activity: Activity) {
        if (!installed.remove(activity)) return
        val window = activity.window ?: return
        val callback = window.callback
        if (callback is ObservingWindowCallback) {
            window.callback = callback.wrapped
        }
    }
}

private class ObservingWindowCallback(
    val wrapped: Window.Callback,
    private val tracker: TwoFingerLongPressTracker,
) : Window.Callback by wrapped {
    override fun dispatchTouchEvent(event: MotionEvent): Boolean {
        tracker.onTouchEvent(event)
        return wrapped.dispatchTouchEvent(event)
    }
}

private class TwoFingerLongPressTracker(
    private val holdMs: Long,
    private val slopPx: Float,
    private val onTriggered: () -> Unit,
) {
    private val handler = Handler(Looper.getMainLooper())
    private var anchorA: MotionEvent.PointerCoords? = null
    private var anchorB: MotionEvent.PointerCoords? = null
    private var tracking = false
    private var fired = false

    private val fireRunnable = Runnable {
        if (tracking && !fired) {
            fired = true
            onTriggered()
        }
    }

    fun onTouchEvent(event: MotionEvent) {
        when (event.actionMasked) {
            MotionEvent.ACTION_DOWN,
            MotionEvent.ACTION_POINTER_DOWN -> {
                if (event.pointerCount >= 2) startTracking(event)
            }
            MotionEvent.ACTION_MOVE -> {
                if (tracking && event.pointerCount >= 2) {
                    if (movedTooFar(event)) cancelTracking()
                } else if (tracking) {
                    cancelTracking()
                }
            }
            MotionEvent.ACTION_POINTER_UP -> {
                // pointerCount still includes the lifting finger.
                if (event.pointerCount - 1 < 2) cancelTracking()
            }
            MotionEvent.ACTION_UP,
            MotionEvent.ACTION_CANCEL -> cancelTracking()
        }
    }

    private fun startTracking(event: MotionEvent) {
        cancelTracking()
        if (event.pointerCount < 2) return
        val a = MotionEvent.PointerCoords()
        val b = MotionEvent.PointerCoords()
        event.getPointerCoords(0, a)
        event.getPointerCoords(1, b)
        anchorA = a
        anchorB = b
        tracking = true
        fired = false
        handler.postDelayed(fireRunnable, holdMs)
    }

    private fun cancelTracking() {
        handler.removeCallbacks(fireRunnable)
        tracking = false
        fired = false
        anchorA = null
        anchorB = null
    }

    private fun movedTooFar(event: MotionEvent): Boolean {
        val a0 = anchorA ?: return true
        val b0 = anchorB ?: return true
        if (event.pointerCount < 2) return true
        val a = MotionEvent.PointerCoords()
        val b = MotionEvent.PointerCoords()
        event.getPointerCoords(0, a)
        event.getPointerCoords(1, b)
        return dist(a0, a) > slopPx || dist(b0, b) > slopPx
    }

    private fun dist(p: MotionEvent.PointerCoords, q: MotionEvent.PointerCoords): Float {
        val dx = p.x - q.x
        val dy = p.y - q.y
        return kotlin.math.sqrt(dx * dx + dy * dy)
    }
}
