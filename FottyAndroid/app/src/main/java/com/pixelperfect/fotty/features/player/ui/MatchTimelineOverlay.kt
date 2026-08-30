package com.pixelperfect.fotty.features.player.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material3.*
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.pixelperfect.fotty.core.network.models.football.APIFootballEvent
import com.pixelperfect.fotty.core.theme.Accent

@Composable
fun MatchTimelineOverlay(
    events: List<APIFootballEvent>,
    currentMinute: Int,
    modifier: Modifier = Modifier
) {
    Column(
        modifier = modifier
            .fillMaxWidth()
            .padding(horizontal = 16.dp, vertical = 8.dp)
    ) {
        Text(
            text = "MATCH TIMELINE",
            style = MaterialTheme.typography.labelSmall,
            color = Color.White.copy(alpha = 0.5f),
            fontWeight = FontWeight.Black,
            letterSpacing = 1.5.sp
        )
        
        Spacer(modifier = Modifier.height(12.dp))
        
        Box(
            modifier = Modifier
                .fillMaxWidth()
                .height(4.dp)
                .background(Color.White.copy(alpha = 0.1f), CircleShape)
        ) {
            // Progress Bar
            val progress = (currentMinute.toFloat() / 90f).coerceIn(0f, 1f)
            Box(
                modifier = Modifier
                    .fillMaxWidth(progress)
                    .fillMaxHeight()
                    .background(Accent, CircleShape)
            )
            
            // Event Markers
            events.forEach { event ->
                val eventProgress = (event.time.elapsed.toFloat() / 90f).coerceIn(0f, 1f)
                val markerColor = when (event.type.lowercase()) {
                    "goal" -> Color.Yellow
                    "card" -> if (event.detail.lowercase().contains("red")) Color.Red else Color(0xFFFFCC00)
                    else -> Color.White
                }
                
                Box(
                    modifier = Modifier
                        .align(Alignment.CenterStart)
                        .padding(start = (eventProgress * 100).let { if (it > 95) 0.dp else 0.dp }) // Basic alignment
                        .offset(x = (eventProgress * 300).dp) // This is a simplification, ideally use BoxWithConstraints
                        .size(6.dp)
                        .background(markerColor, CircleShape)
                )
            }
        }
    }
}
