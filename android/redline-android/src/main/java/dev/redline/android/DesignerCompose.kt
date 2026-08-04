package dev.redline.android

import android.app.Application
import androidx.compose.animation.AnimatedContent
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.slideInVertically
import androidx.compose.animation.slideOutVertically
import androidx.compose.animation.togetherWith
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.gestures.detectDragGestures
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.wrapContentSize
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.Undo
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.CropSquare
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material.icons.filled.Edit
import androidx.compose.material.icons.filled.KeyboardArrowDown
import androidx.compose.material.icons.filled.KeyboardArrowUp
import androidx.compose.material.icons.filled.NorthEast
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.composed
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.zIndex
import kotlin.math.atan2
import kotlin.math.cos
import kotlin.math.sin

private val RegionOrange = Color(0xFFFF8C00)
private val DimOverlay = Color.Black.copy(alpha = 0.28f)
private val ToolbarMaterial = Color(0xE6F2F2F7) // approx ultraThinMaterial on light UI
private val FieldBackground = Color(0xFFE5E5EA)
private val PrimaryInk = Color(0xFF1C1C1E)
private val SecondaryInk = Color(0xFF8E8E93)
private val DividerInk = PrimaryInk.copy(alpha = 0.12f)
private val StrokeWidth = 3f
private val HitSize = 40.dp

/**
 * Tags a composable as a designer region. In designer mode, shows an orange outline and opens markup on tap.
 */
fun Modifier.redlineRegion(name: String): Modifier = composed {
    val owner = remember { Any() }
    DisposableEffect(name) {
        DesignerModeController.registerRegion(owner, name)
        onDispose { DesignerModeController.unregisterRegion(owner, name) }
    }
    val active = DesignerModeController.isDesignerModeActive &&
        !DesignerModeController.showMarkup &&
        !DesignerModeController.isSaving &&
        !DesignerModeController.isCapturing
    if (!active) {
        this
    } else {
        this
            .border(2.dp, RegionOrange, RoundedCornerShape(4.dp))
            .background(RegionOrange.copy(alpha = 0.18f), RoundedCornerShape(4.dp))
            .clickable { DesignerModeController.beginMarkup(name) }
    }
}

/**
 * Host root overlay: designer banner + fullscreen markup sheet.
 * Calls [Redline.install] on first composition — no separate Application hook required.
 */
@Composable
fun DesignerOverlay(
    screen: String = "app",
    spec: String? = null,
    state: String? = null,
    context: DesignerContext = EmptyDesignerContext,
    feedbackBaseUrl: String? = null,
    apiToken: String? = null,
    content: @Composable () -> Unit,
) {
    val app = LocalContext.current.applicationContext as Application
    DisposableEffect(screen, spec, state, context, feedbackBaseUrl, apiToken, app) {
        Redline.install(
            application = app,
            screen = screen,
            spec = spec,
            state = state,
            context = context,
            feedbackBaseUrl = feedbackBaseUrl,
            apiToken = apiToken,
        )
        onDispose { }
    }

    Box(modifier = Modifier.fillMaxSize()) {
        content()
        if (DesignerModeController.isDesignerModeActive &&
            !DesignerModeController.showMarkup &&
            !DesignerModeController.isSaving
        ) {
            // wrapContentSize so the banner does not steal hits outside the pill.
            DesignerBanner(
                modifier = Modifier
                    .align(Alignment.TopCenter)
                    .zIndex(10f)
                    .statusBarsPadding()
                    .padding(top = 8.dp)
                    .wrapContentSize(),
            )
        }
        if (DesignerModeController.showMarkup) {
            MarkupSheet(modifier = Modifier.zIndex(20f))
        }
        // After capture only — must not appear in the composite PNG. Shows while POST runs.
        if (DesignerModeController.isSaving && !DesignerModeController.isCapturing) {
            Box(
                modifier = Modifier
                    .fillMaxSize()
                    .background(Color.Black.copy(alpha = 0.35f))
                    .clickable(enabled = true, onClick = {})
                    .zIndex(30f),
                contentAlignment = Alignment.Center,
            ) {
                Column(horizontalAlignment = Alignment.CenterHorizontally) {
                    CircularProgressIndicator(color = RegionOrange)
                    Spacer(modifier = Modifier.height(12.dp))
                    Text(
                        text = "Saving…",
                        color = Color.White,
                        fontWeight = FontWeight.SemiBold,
                    )
                }
            }
        }
    }
}

@Composable
private fun DesignerBanner(modifier: Modifier = Modifier) {
    Row(
        modifier = modifier
            .clip(RoundedCornerShape(20.dp))
            .background(RegionOrange)
            .padding(horizontal = 12.dp, vertical = 8.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        Text(
            text = "Designer mode",
            color = Color.White,
            fontWeight = FontWeight.SemiBold,
            fontSize = 13.sp,
        )
        TextButton(onClick = { DesignerModeController.beginScreenMarkup() }) {
            Text(text = "Whole screen", color = Color.White, fontSize = 13.sp)
        }
        TextButton(onClick = { DesignerModeController.toggleDesignerMode() }) {
            Text(text = "Exit", color = Color.White, fontSize = 13.sp)
        }
    }
}

private enum class MarkupTool(val id: String, val icon: ImageVector, val label: String) {
    Pen("pen", Icons.Filled.Edit, "pen"),
    Arrow("arrow", Icons.Filled.NorthEast, "arrow"),
    Rect("rect", Icons.Filled.CropSquare, "rect"),
}

private enum class MarkupColor(val id: String, val color: Color) {
    Red("red", Color(0xFFFF3B30)),
    Green("green", Color(0xFF34C759)),
    Neutral("neutral", Color(0xFF737373)),
}

@Composable
private fun MarkupSheet(modifier: Modifier = Modifier) {
    var tool by remember { mutableStateOf(MarkupTool.Pen) }
    var color by remember { mutableStateOf(MarkupColor.Red) }
    var draftPoints by remember { mutableStateOf<List<Offset>>(emptyList()) }
    var toolbarVisible by remember { mutableStateOf(true) }
    val isWholeScreen = DesignerModeController.activeRegion == DesignerModeController.SCREEN_REGION
    val isSaving = DesignerModeController.isSaving
    val canUndo = DesignerModeController.strokes.isNotEmpty()

    val capturing = DesignerModeController.isCapturing

    Box(
        modifier = modifier
            .fillMaxSize()
            // Dim is chrome — omit from the composite PNG while capturing.
            .background(if (isWholeScreen || capturing) Color.Transparent else DimOverlay),
    ) {
        Canvas(
            modifier = Modifier
                .fillMaxSize()
                .then(
                    if (capturing) {
                        Modifier
                    } else {
                        Modifier.pointerInput(tool, color) {
                            detectDragGestures(
                                onDragStart = { offset ->
                                    draftPoints = listOf(offset)
                                    val id = tool.id
                                    if (id !in DesignerModeController.toolsUsed) {
                                        DesignerModeController.toolsUsed.add(id)
                                    }
                                },
                                onDrag = { change, _ ->
                                    change.consume()
                                    draftPoints = draftPoints + change.position
                                },
                                onDragEnd = {
                                    val pts = draftPoints
                                    if (pts.size >= 2) {
                                        val stroke = when (tool) {
                                            MarkupTool.Pen -> MarkupStroke(
                                                tool = tool.id,
                                                color = color.id,
                                                points = pts.map { listOf(it.x.toDouble(), it.y.toDouble()) },
                                            )
                                            MarkupTool.Arrow -> MarkupStroke(
                                                tool = tool.id,
                                                color = color.id,
                                                points = listOf(
                                                    listOf(pts.first().x.toDouble(), pts.first().y.toDouble()),
                                                    listOf(pts.last().x.toDouble(), pts.last().y.toDouble()),
                                                ),
                                            )
                                            MarkupTool.Rect -> {
                                                val a = pts.first()
                                                val b = pts.last()
                                                MarkupStroke(
                                                    tool = tool.id,
                                                    color = color.id,
                                                    points = listOf(
                                                        listOf(a.x.toDouble(), a.y.toDouble()),
                                                        listOf(b.x.toDouble(), b.y.toDouble()),
                                                    ),
                                                )
                                            }
                                        }
                                        DesignerModeController.strokes.add(stroke)
                                    }
                                    draftPoints = emptyList()
                                },
                                onDragCancel = { draftPoints = emptyList() },
                            )
                        }
                    },
                ),
        ) {
            fun strokeColor(id: String): Color = when (id) {
                "red" -> MarkupColor.Red.color
                "green" -> MarkupColor.Green.color
                else -> MarkupColor.Neutral.color
            }

            fun drawStroke(stroke: MarkupStroke, points: List<Offset>) {
                val c = strokeColor(stroke.color)
                when (stroke.tool) {
                    "pen" -> {
                        if (points.size < 2) return
                        val path = Path().apply {
                            moveTo(points.first().x, points.first().y)
                            for (i in 1 until points.size) lineTo(points[i].x, points[i].y)
                        }
                        drawPath(path, c, style = Stroke(width = StrokeWidth, cap = StrokeCap.Round))
                    }
                    "arrow" -> {
                        if (points.size < 2) return
                        val start = points.first()
                        val end = points.last()
                        drawLine(c, start, end, strokeWidth = StrokeWidth, cap = StrokeCap.Round)
                        val angle = atan2(end.y - start.y, end.x - start.x)
                        val arrowLen = 14f
                        val a1 = Offset(
                            end.x - arrowLen * cos(angle - Math.PI / 6).toFloat(),
                            end.y - arrowLen * sin(angle - Math.PI / 6).toFloat(),
                        )
                        val a2 = Offset(
                            end.x - arrowLen * cos(angle + Math.PI / 6).toFloat(),
                            end.y - arrowLen * sin(angle + Math.PI / 6).toFloat(),
                        )
                        drawLine(c, end, a1, strokeWidth = StrokeWidth, cap = StrokeCap.Round)
                        drawLine(c, end, a2, strokeWidth = StrokeWidth, cap = StrokeCap.Round)
                    }
                    "rect" -> {
                        if (points.size < 2) return
                        val a = points.first()
                        val b = points.last()
                        val left = minOf(a.x, b.x)
                        val top = minOf(a.y, b.y)
                        val w = kotlin.math.abs(a.x - b.x)
                        val h = kotlin.math.abs(a.y - b.y)
                        drawRect(c, Offset(left, top), Size(w, h), style = Stroke(width = StrokeWidth))
                    }
                }
            }

            DesignerModeController.strokes.forEach { stroke ->
                val pts = stroke.points.map { Offset(it[0].toFloat(), it[1].toFloat()) }
                drawStroke(stroke, pts)
            }
            if (draftPoints.isNotEmpty()) {
                drawStroke(
                    MarkupStroke(tool.id, color.id, emptyList()),
                    draftPoints,
                )
            }
        }

        // Toolbar chrome is omitted from the composite PNG while capturing.
        if (!capturing) {
            Column(
                modifier = Modifier
                    .align(Alignment.TopCenter)
                    .fillMaxWidth()
                    .statusBarsPadding()
                    .padding(top = 4.dp, start = 12.dp, end = 12.dp),
            ) {
                AnimatedContent(
                    targetState = toolbarVisible,
                    transitionSpec = {
                        (slideInVertically { -it / 3 } + fadeIn()) togetherWith
                            (slideOutVertically { -it / 3 } + fadeOut())
                    },
                    label = "markupToolbar",
                ) { visible ->
                    if (visible) {
                        MarkupToolbar(
                            regionLabel = DesignerModeController.activeRegion ?: "?",
                            tool = tool,
                            onToolChange = { tool = it },
                            color = color,
                            onColorChange = { color = it },
                            comment = DesignerModeController.markupComment,
                            onCommentChange = { DesignerModeController.markupComment = it },
                            canUndo = canUndo,
                            isSaving = isSaving,
                            saveError = DesignerModeController.saveError,
                            onUndo = {
                                if (DesignerModeController.strokes.isNotEmpty()) {
                                    DesignerModeController.strokes.removeAt(
                                        DesignerModeController.strokes.lastIndex,
                                    )
                                }
                            },
                            onClear = { DesignerModeController.strokes.clear() },
                            onHide = { toolbarVisible = false },
                            onCancel = { DesignerModeController.cancelMarkup() },
                            onSend = { DesignerModeController.saveMarkup() },
                        )
                    } else {
                        ShowToolsCapsule(
                            enabled = !isSaving,
                            onClick = { toolbarVisible = true },
                        )
                    }
                }
            }
        }
    }
}

@Composable
private fun ShowToolsCapsule(
    enabled: Boolean,
    onClick: () -> Unit,
) {
    Row(modifier = Modifier.fillMaxWidth()) {
        Row(
            modifier = Modifier
                .shadow(6.dp, RoundedCornerShape(50), ambientColor = Color.Black.copy(alpha = 0.1f))
                .clip(RoundedCornerShape(50))
                .background(ToolbarMaterial)
                .clickable(enabled = enabled, onClick = onClick)
                .padding(horizontal = 14.dp, vertical = 10.dp)
                .semantics { contentDescription = "Show tools" },
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(4.dp),
        ) {
            Icon(
                imageVector = Icons.Filled.KeyboardArrowDown,
                contentDescription = null,
                tint = PrimaryInk.copy(alpha = if (enabled) 1f else 0.3f),
                modifier = Modifier.size(16.dp),
            )
            Text(
                text = "Show tools",
                color = PrimaryInk.copy(alpha = if (enabled) 1f else 0.3f),
                fontSize = 12.sp,
                fontWeight = FontWeight.SemiBold,
            )
        }
        Spacer(modifier = Modifier.weight(1f))
    }
}

@Composable
private fun MarkupToolbar(
    regionLabel: String,
    tool: MarkupTool,
    onToolChange: (MarkupTool) -> Unit,
    color: MarkupColor,
    onColorChange: (MarkupColor) -> Unit,
    comment: String,
    onCommentChange: (String) -> Unit,
    canUndo: Boolean,
    isSaving: Boolean,
    saveError: String?,
    onUndo: () -> Unit,
    onClear: () -> Unit,
    onHide: () -> Unit,
    onCancel: () -> Unit,
    onSend: () -> Unit,
) {
    Column(
        modifier = Modifier.fillMaxWidth(),
        verticalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        Row(
            modifier = Modifier.fillMaxWidth(),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(8.dp),
        ) {
            BasicTextField(
                value = comment,
                onValueChange = onCommentChange,
                enabled = !isSaving,
                singleLine = true,
                textStyle = TextStyle(
                    color = PrimaryInk,
                    fontSize = 14.sp,
                ),
                cursorBrush = SolidColor(RegionOrange),
                modifier = Modifier
                    .weight(1f)
                    .clip(RoundedCornerShape(10.dp))
                    .background(FieldBackground)
                    .padding(horizontal = 12.dp, vertical = 10.dp),
                decorationBox = { inner ->
                    Box {
                        if (comment.isEmpty()) {
                            Text(
                                text = "Feedback for agent…",
                                color = SecondaryInk,
                                fontSize = 14.sp,
                            )
                        }
                        inner()
                    }
                },
            )
            Box(
                modifier = Modifier
                    .clip(RoundedCornerShape(10.dp))
                    .background(RegionOrange)
                    .clickable(enabled = !isSaving, onClick = onSend)
                    .padding(horizontal = 16.dp, vertical = 10.dp)
                    .semantics { contentDescription = "Send feedback" },
                contentAlignment = Alignment.Center,
            ) {
                if (isSaving) {
                    CircularProgressIndicator(
                        modifier = Modifier.size(16.dp),
                        strokeWidth = 2.dp,
                        color = Color.White,
                    )
                } else {
                    Text(
                        text = "Send",
                        color = Color.White,
                        fontSize = 14.sp,
                        fontWeight = FontWeight.SemiBold,
                    )
                }
            }
        }

        if (!saveError.isNullOrEmpty()) {
            Text(
                text = saveError,
                color = Color(0xFFFF3B30),
                fontSize = 12.sp,
                modifier = Modifier.padding(horizontal = 4.dp),
            )
        }

        Column(
            modifier = Modifier
                .fillMaxWidth()
                .shadow(6.dp, RoundedCornerShape(16.dp), ambientColor = Color.Black.copy(alpha = 0.1f))
                .clip(RoundedCornerShape(16.dp))
                .background(ToolbarMaterial)
                .padding(horizontal = 6.dp, vertical = 4.dp),
        ) {
            Row(
                modifier = Modifier.fillMaxWidth(),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Text(
                    text = regionLabel,
                    color = SecondaryInk,
                    fontSize = 11.sp,
                    fontWeight = FontWeight.SemiBold,
                    maxLines = 1,
                    modifier = Modifier.padding(start = 8.dp),
                )
                Spacer(modifier = Modifier.weight(1f))
                MarkupTool.entries.forEach { t ->
                    ToolIconButton(
                        icon = t.icon,
                        label = t.label,
                        selected = tool == t,
                        enabled = !isSaving,
                        onClick = { onToolChange(t) },
                    )
                }
                ThinDivider()
                MarkupColor.entries.forEach { c ->
                    ColorSwatch(
                        color = c.color,
                        selected = color == c,
                        enabled = !isSaving,
                        label = c.id,
                        onClick = { onColorChange(c) },
                    )
                }
            }

            Row(
                modifier = Modifier.fillMaxWidth(),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.Center,
            ) {
                ToolbarIconButton(
                    icon = Icons.AutoMirrored.Filled.Undo,
                    label = "Undo",
                    enabled = canUndo && !isSaving,
                    onClick = onUndo,
                )
                ToolbarIconButton(
                    icon = Icons.Filled.Delete,
                    label = "Clear",
                    enabled = canUndo && !isSaving,
                    onClick = onClear,
                )
                ThinDivider()
                ToolbarIconButton(
                    icon = Icons.Filled.Close,
                    label = "Cancel",
                    enabled = !isSaving,
                    onClick = onCancel,
                )
                ThinDivider()
                ToolbarIconButton(
                    icon = Icons.Filled.KeyboardArrowUp,
                    label = "Hide toolbar",
                    enabled = !isSaving,
                    onClick = onHide,
                )
            }
        }
    }
}

@Composable
private fun ThinDivider() {
    Box(
        modifier = Modifier
            .padding(horizontal = 2.dp)
            .width(1.dp)
            .height(22.dp)
            .clip(RoundedCornerShape(50))
            .background(DividerInk),
    )
}

@Composable
private fun ToolIconButton(
    icon: ImageVector,
    label: String,
    selected: Boolean,
    enabled: Boolean,
    onClick: () -> Unit,
) {
    Box(
        modifier = Modifier
            .size(HitSize)
            .clip(CircleShape)
            .background(if (selected) RegionOrange else Color.Transparent)
            .clickable(
                enabled = enabled,
                indication = null,
                interactionSource = remember { MutableInteractionSource() },
                onClick = onClick,
            )
            .semantics { contentDescription = label },
        contentAlignment = Alignment.Center,
    ) {
        Icon(
            imageVector = icon,
            contentDescription = null,
            tint = when {
                !enabled -> PrimaryInk.copy(alpha = 0.3f)
                selected -> Color.White
                else -> PrimaryInk
            },
            modifier = Modifier.size(18.dp),
        )
    }
}

@Composable
private fun ColorSwatch(
    color: Color,
    selected: Boolean,
    enabled: Boolean,
    label: String,
    onClick: () -> Unit,
) {
    Box(
        modifier = Modifier
            .size(HitSize)
            .clickable(
                enabled = enabled,
                indication = null,
                interactionSource = remember { MutableInteractionSource() },
                onClick = onClick,
            )
            .semantics { contentDescription = label },
        contentAlignment = Alignment.Center,
    ) {
        if (selected) {
            Box(
                modifier = Modifier
                    .size(26.dp)
                    .border(2.dp, PrimaryInk.copy(alpha = 0.8f), CircleShape),
            )
        }
        Box(
            modifier = Modifier
                .size(18.dp)
                .clip(CircleShape)
                .background(color.copy(alpha = if (enabled) 1f else 0.3f)),
        )
    }
}

@Composable
private fun ToolbarIconButton(
    icon: ImageVector,
    label: String,
    enabled: Boolean,
    onClick: () -> Unit,
) {
    Box(
        modifier = Modifier
            .size(HitSize)
            .clip(CircleShape)
            .clickable(
                enabled = enabled,
                indication = null,
                interactionSource = remember { MutableInteractionSource() },
                onClick = onClick,
            )
            .semantics { contentDescription = label },
        contentAlignment = Alignment.Center,
    ) {
        Icon(
            imageVector = icon,
            contentDescription = null,
            tint = PrimaryInk.copy(alpha = if (enabled) 1f else 0.3f),
            modifier = Modifier.size(18.dp),
        )
    }
}
