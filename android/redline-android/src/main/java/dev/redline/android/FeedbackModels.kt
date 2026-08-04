package dev.redline.android

import org.json.JSONArray
import org.json.JSONObject

data class DesignerPin(
    val component: String,
    val pin: String,
)

fun interface DesignerContext {
    fun pins(screen: String, region: String): List<DesignerPin>
}

object EmptyDesignerContext : DesignerContext {
    override fun pins(screen: String, region: String): List<DesignerPin> = emptyList()
}

data class MarkupStroke(
    val tool: String,
    val color: String,
    val points: List<List<Double>>,
)

data class AppRuntimeContext(
    val bundleId: String? = null,
    val appName: String? = null,
    val appVersion: String? = null,
    val buildNumber: String? = null,
    val deviceModel: String? = null,
    val systemName: String? = null,
    val systemVersion: String? = null,
    val isSimulator: Boolean? = null,
    val localeIdentifier: String? = null,
    val timeZoneIdentifier: String? = null,
    val screenBounds: String? = null,
    val orientation: String? = null,
    val interfaceStyle: String? = null,
    val userInfo: Map<String, String>? = null,
    val notes: String? = null,
)

data class FeedbackPayload(
    val schema: Int = CURRENT_SCHEMA,
    val screen: String,
    val region: String,
    val state: String? = null,
    val platform: String = "android",
    val mode: String? = null,
    val spec: String? = null,
    val capturedTs: String,
    val comment: String,
    val pins: List<DesignerPin> = emptyList(),
    val toolsUsed: List<String> = emptyList(),
    /** Vector strokes (also rasterized into [compositePngBase64] on device before POST). */
    val strokes: List<MarkupStroke> = emptyList(),
    /** Base64 PNG with markup strokes baked in — Mac Inbox and agents display this as-is. */
    val compositePngBase64: String,
    val runtime: AppRuntimeContext? = null,
) {
    companion object {
        const val CURRENT_SCHEMA = 1
    }

    fun validate() {
        require(schema == CURRENT_SCHEMA) { "unsupported schema $schema" }
        require(screen.isNotBlank()) { "screen required" }
        require(region.isNotBlank()) { "region required" }
        require(comment.isNotBlank()) { "comment required" }
        require(compositePngBase64.isNotBlank()) { "compositePngBase64 required" }
    }

    fun toJson(): JSONObject {
        val obj = JSONObject()
        obj.put("schema", schema)
        obj.put("screen", screen)
        obj.put("region", region)
        if (state != null) obj.put("state", state)
        obj.put("platform", platform)
        if (mode != null) obj.put("mode", mode)
        if (spec != null) obj.put("spec", spec)
        obj.put("capturedTs", capturedTs)
        obj.put("comment", comment)
        obj.put("pins", JSONArray().apply {
            pins.forEach { pin ->
                put(JSONObject().put("component", pin.component).put("pin", pin.pin))
            }
        })
        obj.put("toolsUsed", JSONArray(toolsUsed))
        obj.put("strokes", JSONArray().apply {
            strokes.forEach { stroke ->
                put(
                    JSONObject()
                        .put("tool", stroke.tool)
                        .put("color", stroke.color)
                        .put(
                            "points",
                            JSONArray().apply {
                                stroke.points.forEach { pt ->
                                    put(JSONArray(pt))
                                }
                            },
                        ),
                )
            }
        })
        obj.put("compositePngBase64", compositePngBase64)
        runtime?.let { obj.put("runtime", it.toJson()) }
        return obj
    }
}

private fun AppRuntimeContext.toJson(): JSONObject {
    val obj = JSONObject()
    fun putOpt(key: String, value: Any?) {
        if (value != null) obj.put(key, value)
    }
    putOpt("bundleId", bundleId)
    putOpt("appName", appName)
    putOpt("appVersion", appVersion)
    putOpt("buildNumber", buildNumber)
    putOpt("deviceModel", deviceModel)
    putOpt("systemName", systemName)
    putOpt("systemVersion", systemVersion)
    putOpt("isSimulator", isSimulator)
    putOpt("localeIdentifier", localeIdentifier)
    putOpt("timeZoneIdentifier", timeZoneIdentifier)
    putOpt("screenBounds", screenBounds)
    putOpt("orientation", orientation)
    putOpt("interfaceStyle", interfaceStyle)
    putOpt("notes", notes)
    userInfo?.takeIf { it.isNotEmpty() }?.let { map ->
        obj.put(
            "userInfo",
            JSONObject().apply { map.forEach { (k, v) -> put(k, v) } },
        )
    }
    return obj
}
