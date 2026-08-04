package dev.redline.android.demo

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import dev.redline.android.DesignerModeController
import dev.redline.android.DesignerOverlay
import dev.redline.android.redlineRegion

class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContent {
            MaterialTheme {
                Surface(modifier = Modifier.fillMaxSize()) {
                    DesignerOverlay(
                        context = DemoDesignerContext,
                    ) {
                        DemoHomeScreen()
                    }
                }
            }
        }
    }
}

@Composable
private fun DemoHomeScreen() {
    val designerActive = DesignerModeController.isDesignerModeActive
    val markupOpen = DesignerModeController.showMarkup

    Column(
        modifier = Modifier
            .fillMaxSize()
            // Leave room for the designer banner so Header stays tappable.
            .padding(top = 72.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(24.dp),
    ) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .padding(vertical = 12.dp)
                .redlineRegion("Header"),
            horizontalAlignment = Alignment.CenterHorizontally,
        ) {
            Text(
                "Redline Android Demo",
                fontSize = 28.sp,
                fontWeight = FontWeight.Bold,
            )
            Text(
                if (designerActive) {
                    "Tap a region or Whole screen to markup."
                } else {
                    "Two-finger long-press (or Enter designer), then pick a region."
                },
                color = Color.Gray,
                textAlign = TextAlign.Center,
                modifier = Modifier.padding(horizontal = 24.dp, vertical = 8.dp),
            )
        }

        Box(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 16.dp)
                .height(120.dp)
                .clip(RoundedCornerShape(12.dp))
                .background(Color(0xFF1565C0).copy(alpha = 0.15f))
                .redlineRegion("Hero"),
            contentAlignment = Alignment.Center,
        ) {
            Text("Design feedback, live")
        }

        // Region clickable must wrap the Button — Material3 Button consumes taps.
        Box(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 16.dp)
                .redlineRegion("CTA"),
            contentAlignment = Alignment.Center,
        ) {
            Button(
                onClick = {},
                enabled = !designerActive,
                modifier = Modifier.fillMaxWidth(),
            ) {
                Text("Leave design feedback")
            }
        }

        Spacer(modifier = Modifier.weight(1f))

        Button(
            onClick = { DesignerModeController.toggleDesignerMode() },
            enabled = !markupOpen,
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 16.dp)
                .padding(bottom = 24.dp),
            colors = ButtonDefaults.buttonColors(
                containerColor = if (designerActive) Color(0xFFFF8C00) else MaterialTheme.colorScheme.primary,
            ),
        ) {
            Text(if (designerActive) "Exit designer" else "Enter designer")
        }
    }
}
