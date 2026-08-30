package com.pixelperfect.fotty.features.player.ui

import androidx.compose.animation.*
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.*
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.pixelperfect.fotty.data.models.MatchIntelligence
import com.pixelperfect.fotty.core.theme.Accent

import androidx.compose.material3.windowsizeclass.WindowWidthSizeClass
import androidx.compose.ui.platform.LocalContext
import android.app.Activity
import androidx.compose.material3.windowsizeclass.calculateWindowSizeClass
import androidx.compose.material3.windowsizeclass.ExperimentalMaterial3WindowSizeClassApi

@OptIn(ExperimentalMaterial3WindowSizeClassApi::class)
@Composable
fun PlayerIntelligenceOverlay(
    intelligence: MatchIntelligence,
    isVisible: Boolean,
    category: String = "football",
    modifier: Modifier = Modifier
) {
    val context = LocalContext.current
    val windowSizeClass = calculateWindowSizeClass(context as Activity)
    val horizontalPadding = if (windowSizeClass.widthSizeClass == WindowWidthSizeClass.Compact) 16.dp else 120.dp
    val bottomPadding = if (windowSizeClass.widthSizeClass == WindowWidthSizeClass.Compact) 64.dp else 32.dp

    val xgLabel = when(category.lowercase()) {
        "football" -> "EXPECTED GOALS (xG)"
        "basketball" -> "SHOOTING ACCURACY"
        "mma" -> "STRIKE EFFICIENCY"
        else -> "EXPECTED PERFORMANCE"
    }

    AnimatedVisibility(
        visible = isVisible,
        enter = fadeIn() + slideInVertically { it / 2 },
        exit = fadeOut() + slideOutVertically { it / 2 },
        modifier = modifier
    ) {
        Box(
            modifier = Modifier.fillMaxSize()
        ) {
            // Material 3 Surface Panel with Adaptive Layout
            Surface(
                modifier = Modifier
                    .align(Alignment.BottomCenter)
                    .padding(horizontal = horizontalPadding, vertical = bottomPadding)
                    .fillMaxWidth(),
                color = MaterialTheme.colorScheme.surface,
                tonalElevation = 12.dp,
                shape = MaterialTheme.shapes.extraLarge,
                shadowElevation = 4.dp
            ) {
                Column(modifier = Modifier.padding(24.dp)) {
                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        horizontalArrangement = Arrangement.SpaceBetween,
                        verticalAlignment = Alignment.CenterVertically
                    ) {
                        Text(
                            text = "TACTICAL INTELLIGENCE",
                            style = MaterialTheme.typography.labelSmall,
                            color = MaterialTheme.colorScheme.primary,
                            fontWeight = FontWeight.Black,
                            letterSpacing = 1.5.sp
                        )
                        Badge(containerColor = MaterialTheme.colorScheme.primary)
                    }

                    Spacer(modifier = Modifier.height(24.dp))

                    // Possession Bar
                    IntelligenceMetricRow(
                        label = if (category == "mma") "CONTROL TIME" else "POSSESSION",
                        homeValue = if (category == "mma") "4:12" else "${intelligence.possessionHome}%",
                        awayValue = if (category == "mma") "1:45" else "${intelligence.possessionAway}%",
                        progress = intelligence.possessionHome / 100f
                    )

                    Spacer(modifier = Modifier.height(24.dp))

                    // Adaptive Metric
                    IntelligenceMetricRow(
                        label = xgLabel,
                        homeValue = if (category == "football") "%.2f".format(intelligence.xGHome) else "48%",
                        awayValue = if (category == "football") "%.2f".format(intelligence.xGAway) else "42%",
                        progress = if (intelligence.xGHome + intelligence.xGAway > 0) 
                            intelligence.xGHome / (intelligence.xGHome + intelligence.xGAway) 
                        else 0.5f
                    )

                    Spacer(modifier = Modifier.height(24.dp))

                    // Win Probability
                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        horizontalArrangement = Arrangement.SpaceEvenly
                    ) {
                        ProbabilityItem(if (category == "mma") "WIN PROB" else "HOME WIN", intelligence.winProbabilityHome)
                        if (category != "mma") {
                            ProbabilityItem("DRAW", (1f - intelligence.winProbabilityHome - intelligence.winProbabilityAway).coerceAtLeast(0f))
                        }
                        ProbabilityItem(if (category == "mma") "FINISH PROB" else "AWAY WIN", intelligence.winProbabilityAway)
                    }
                }
            }
        }
    }
}

@Composable
private fun IntelligenceMetricRow(
    label: String,
    homeValue: String,
    awayValue: String,
    progress: Float
) {
    Column {
        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.SpaceBetween
        ) {
            Text(homeValue, color = Color.White, fontSize = 14.sp, fontWeight = FontWeight.Black, fontFamily = androidx.compose.ui.text.font.FontFamily.Monospace)
            Text(label, color = Color.Gray, fontSize = 9.sp, fontWeight = FontWeight.Bold, fontFamily = androidx.compose.ui.text.font.FontFamily.Monospace)
            Text(awayValue, color = Color.White, fontSize = 14.sp, fontWeight = FontWeight.Black, fontFamily = androidx.compose.ui.text.font.FontFamily.Monospace)
        }
        Spacer(modifier = Modifier.height(6.dp))
        LinearProgressIndicator(
            progress = progress,
            modifier = Modifier
                .fillMaxWidth()
                .height(2.dp),
            color = MaterialTheme.colorScheme.primary,
            trackColor = Color.White.copy(alpha = 0.05f)
        )
    }
}

@Composable
private fun ProbabilityItem(label: String, value: Float) {
    Column(horizontalAlignment = Alignment.CenterHorizontally) {
        Text(label, color = Color.Gray, fontSize = 8.sp, fontWeight = FontWeight.Bold, fontFamily = androidx.compose.ui.text.font.FontFamily.Monospace)
        Text("${(value * 100).toInt()}%", color = Color.White, fontSize = 18.sp, fontWeight = FontWeight.Black, fontFamily = androidx.compose.ui.text.font.FontFamily.Monospace)
    }
}
