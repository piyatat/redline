package dev.redline.android

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.gestures.detectDragGestures
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
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.wrapContentSize
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
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
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.zIndex
import kotlin.math.atan2
import kotlin.math.cos
import kotlin.math.sin

private val RegionOrange = Color(0xFFFF8C00)
private val DimOverlay = Color.Black.copy(alpha = 0.28f)

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
 */
@Composable
fun DesignerOverlay(
    screen: String,
    spec: String? = null,
    state: String? = null,
    context: DesignerContext = EmptyDesignerContext,
    content: @Composable () -> Unit,
) {
    DisposableEffect(screen, spec, state, context) {
        DesignerModeController.activate(screen, spec, state, context)
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

private enum class MarkupTool(val id: String) {
    Pen("pen"),
    Arrow("arrow"),
    Rect("rect"),
}

private enum class MarkupColor(val id: String, val color: Color) {
    Red("red", Color(0xFFE53935)),
    Green("green", Color(0xFF43A047)),
    Neutral("neutral", Color(0xFF212121)),
}

@Composable
private fun MarkupSheet(modifier: Modifier = Modifier) {
    var tool by remember { mutableStateOf(MarkupTool.Pen) }
    var color by remember { mutableStateOf(MarkupColor.Red) }
    var draftPoints by remember { mutableStateOf<List<Offset>>(emptyList()) }
    val isWholeScreen = DesignerModeController.activeRegion == DesignerModeController.SCREEN_REGION

    Box(
        modifier = modifier
            .fillMaxSize()
            .background(if (isWholeScreen) Color.Transparent else DimOverlay),
    ) {
        Canvas(
            modifier = Modifier
                .fillMaxSize()
                .pointerInput(tool, color) {
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
                },
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
                        drawPath(path, c, style = Stroke(width = 4f, cap = StrokeCap.Round))
                    }
                    "arrow" -> {
                        if (points.size < 2) return
                        val start = points.first()
                        val end = points.last()
                        drawLine(c, start, end, strokeWidth = 4f, cap = StrokeCap.Round)
                        val angle = atan2(end.y - start.y, end.x - start.x)
                        val arrowLen = 24f
                        val a1 = Offset(
                            end.x - arrowLen * cos(angle - 0.4).toFloat(),
                            end.y - arrowLen * sin(angle - 0.4).toFloat(),
                        )
                        val a2 = Offset(
                            end.x - arrowLen * cos(angle + 0.4).toFloat(),
                            end.y - arrowLen * sin(angle + 0.4).toFloat(),
                        )
                        drawLine(c, end, a1, strokeWidth = 4f, cap = StrokeCap.Round)
                        drawLine(c, end, a2, strokeWidth = 4f, cap = StrokeCap.Round)
                    }
                    "rect" -> {
                        if (points.size < 2) return
                        val a = points.first()
                        val b = points.last()
                        val left = minOf(a.x, b.x)
                        val top = minOf(a.y, b.y)
                        val w = kotlin.math.abs(a.x - b.x)
                        val h = kotlin.math.abs(a.y - b.y)
                        drawRect(c, Offset(left, top), Size(w, h), style = Stroke(width = 4f))
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

        Column(
            modifier = Modifier
                .align(Alignment.BottomCenter)
                .fillMaxWidth()
                .background(Color.White.copy(alpha = 0.95f))
                .padding(12.dp),
        ) {
            Text(
                text = "Markup · ${DesignerModeController.activeRegion ?: "?"}",
                fontWeight = FontWeight.SemiBold,
                fontSize = 14.sp,
            )
            Spacer(modifier = Modifier.height(8.dp))
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                MarkupTool.entries.forEach { t ->
                    val selected = tool == t
                    OutlinedButton(
                        onClick = { tool = t },
                        colors = if (selected) {
                            ButtonDefaults.outlinedButtonColors(containerColor = RegionOrange.copy(alpha = 0.2f))
                        } else {
                            ButtonDefaults.outlinedButtonColors()
                        },
                    ) { Text(text = t.id) }
                }
            }
            Spacer(modifier = Modifier.height(8.dp))
            Row(
                horizontalArrangement = Arrangement.spacedBy(12.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                MarkupColor.entries.forEach { c ->
                    Box(
                        modifier = Modifier
                            .size(28.dp)
                            .clip(CircleShape)
                            .background(c.color)
                            .border(
                                width = if (color == c) 3.dp else 1.dp,
                                color = if (color == c) RegionOrange else Color.Gray,
                                shape = CircleShape,
                            )
                            .clickable { color = c },
                    )
                }
                Spacer(modifier = Modifier.weight(1f))
                TextButton(
                    onClick = {
                        if (DesignerModeController.strokes.isNotEmpty()) {
                            DesignerModeController.strokes.removeAt(DesignerModeController.strokes.lastIndex)
                        }
                    },
                ) { Text(text = "Undo") }
                TextButton(onClick = {
                    DesignerModeController.strokes.clear()
                    DesignerModeController.toolsUsed.clear()
                }) { Text(text = "Clear") }
            }
            Spacer(modifier = Modifier.height(8.dp))
            OutlinedTextField(
                value = DesignerModeController.markupComment,
                onValueChange = { DesignerModeController.markupComment = it },
                modifier = Modifier.fillMaxWidth(),
                placeholder = { Text(text = "Feedback for agent…") },
                enabled = !DesignerModeController.isSaving,
                singleLine = false,
                maxLines = 3,
            )
            DesignerModeController.saveError?.let { err ->
                Text(
                    text = err,
                    color = Color(0xFFC62828),
                    fontSize = 12.sp,
                    modifier = Modifier.padding(top = 6.dp),
                )
            }
            Spacer(modifier = Modifier.height(8.dp))
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                OutlinedButton(
                    onClick = { DesignerModeController.cancelMarkup() },
                    enabled = !DesignerModeController.isSaving,
                    modifier = Modifier.weight(1f),
                ) { Text(text = "Cancel") }
                Button(
                    onClick = { DesignerModeController.saveMarkup() },
                    enabled = !DesignerModeController.isSaving,
                    modifier = Modifier.weight(1f),
                    colors = ButtonDefaults.buttonColors(containerColor = RegionOrange),
                ) {
                    if (DesignerModeController.isSaving) {
                        CircularProgressIndicator(
                            modifier = Modifier.size(18.dp),
                            strokeWidth = 2.dp,
                            color = Color.White,
                        )
                        Spacer(modifier = Modifier.width(8.dp))
                    }
                    Text(text = "Send")
                }
            }
        }
    }
}
