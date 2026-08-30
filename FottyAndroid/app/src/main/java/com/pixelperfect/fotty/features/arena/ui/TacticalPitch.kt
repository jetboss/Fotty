package com.pixelperfect.fotty.features.arena.ui

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.BiasAlignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.pixelperfect.fotty.core.network.models.football.APIFootballLineup
import com.pixelperfect.fotty.core.network.models.football.APIFootballPlayerEntry
import com.pixelperfect.fotty.core.theme.*

@Composable
fun TacticalPitch(
    homeLineup: APIFootballLineup?,
    awayLineup: APIFootballLineup?,
    modifier: Modifier = Modifier
) {
    Box(
        modifier = modifier
            .fillMaxWidth()
            .height(500.dp)
            .padding(16.dp)
            .clip(RoundedCornerShape(16.dp))
            .background(Color(0xFF2E7D32)) // Pitch Green
    ) {
        // Draw Field Lines
        Canvas(modifier = Modifier.fillMaxSize()) {
            val w = size.width
            val h = size.height
            val strokeWidth = 2.dp.toPx()
            val lineColor = Color.White.copy(alpha = 0.6f)

            // Outer Boundary
            drawRect(
                color = lineColor,
                style = Stroke(width = strokeWidth)
            )

            // Center Line
            drawLine(
                color = lineColor,
                start = Offset(0f, h / 2),
                end = Offset(w, h / 2),
                strokeWidth = strokeWidth
            )

            // Center Circle
            drawCircle(
                color = lineColor,
                center = Offset(w / 2, h / 2),
                radius = 50.dp.toPx(),
                style = Stroke(width = strokeWidth)
            )

            // Home Penalty Area (Top)
            drawRect(
                color = lineColor,
                topLeft = Offset(w * 0.2f, 0f),
                size = Size(w * 0.6f, h * 0.15f),
                style = Stroke(width = strokeWidth)
            )

            // Away Penalty Area (Bottom)
            drawRect(
                color = lineColor,
                topLeft = Offset(w * 0.2f, h * 0.85f),
                size = Size(w * 0.6f, h * 0.15f),
                style = Stroke(width = strokeWidth)
            )
        }

        // --- Professional Formation Engine ---
        Box(modifier = Modifier.fillMaxSize()) {
            if (homeLineup != null) {
                FormationLayer(
                    lineup = homeLineup,
                    isHome = true
                )
            }

            if (awayLineup != null) {
                FormationLayer(
                    lineup = awayLineup,
                    isHome = false
                )
            }
            
            // Center Line
            Spacer(
                modifier = Modifier
                    .align(Alignment.Center)
                    .height(1.dp)
                    .fillMaxWidth()
                    .background(Color.White.copy(alpha = 0.15f))
            )
        }
    }
}

@Composable
fun BoxScope.FormationLayer(
    lineup: APIFootballLineup,
    isHome: Boolean
) {
    val players = lineup.startXI
    if (players.isEmpty()) return

    // Group players by row (X) from the API grid, fallback to a balanced 4-row distribution if grid is null
    val rows = players.groupBy { entry ->
        entry.player.grid?.split(":")?.firstOrNull() ?: run {
            // Fallback: Map lineup index to a logical row (1: GK, 2: DEF, 3: MID, 4: ATT)
            val idx = players.indexOf(entry)
            when {
                idx == 0 -> "1"
                idx <= 4 -> "2"
                idx <= 8 -> "3"
                else -> "4"
            }
        }
    }.toSortedMap(compareBy { it.toIntOrNull() ?: 0 })
    
    val rowKeys = rows.keys.toList()
    val maxRow = rowKeys.mapNotNull { it.toIntOrNull() }.maxOrNull() ?: 4
    
    rows.forEach { (rowKey, playersInRow) ->
        val rowIndex = rowKey.toIntOrNull() ?: 1
        val count = playersInRow.size
        
        // Sorting players in row by their Column (Y)
        val sortedPlayers = playersInRow.sortedBy { it.player.grid?.split(":")?.lastOrNull()?.toIntOrNull() ?: players.indexOf(it) }
        
        sortedPlayers.forEachIndexed { playerIndex, entry ->
            // Horizontal: Map column index to pitch width (-0.9 to 0.9)
            val horizontalBias = if (count <= 1) 0f else {
                val step = 1.8f / (count + 1)
                -0.9f + (step * (playerIndex + 1))
            }
            
            // Vertical: Map row index to pitch depth (-0.95 to 0.05 for Home, 0.95 to -0.05 for Away)
            val depthPercent = (rowIndex - 1).toFloat() / (maxRow - 1).coerceAtLeast(1)
            val verticalBias = if (isHome) {
                -0.85f + (depthPercent * 0.7f) // Keep within the top half
            } else {
                0.85f - (depthPercent * 0.7f) // Keep within the bottom half
            }
            
            PlayerIcon(
                player = entry,
                isHome = isHome,
                modifier = Modifier.align(BiasAlignment(horizontalBias, verticalBias))
            )
        }
    }
}

@Composable
fun PlayerIcon(
    player: APIFootballPlayerEntry,
    isHome: Boolean,
    modifier: Modifier = Modifier
) {
    Column(
        modifier = modifier,
        horizontalAlignment = Alignment.CenterHorizontally
    ) {
        Box(
            modifier = Modifier
                .size(22.dp)
                .clip(CircleShape)
                .background(if (isHome) Color.White else Color(0xFF111111)),
            contentAlignment = Alignment.Center
        ) {
            Text(
                text = "${player.player.number ?: ""}",
                color = if (isHome) Color.Black else Color.White,
                fontSize = 9.sp,
                fontWeight = FontWeight.ExtraBold
            )
        }
        Surface(
            color = Color.Black.copy(alpha = 0.4f),
            shape = RoundedCornerShape(2.dp),
            modifier = Modifier.padding(top = 2.dp)
        ) {
            Text(
                text = player.player.name.split(" ").last(),
                modifier = Modifier.padding(horizontal = 4.dp),
                color = Color.White,
                fontSize = 7.sp,
                fontWeight = FontWeight.Bold,
                maxLines = 1
            )
        }
        
        if ((player.player.xg ?: 0f) > 0.1f) {
            Surface(
                color = Accent.copy(alpha = 0.8f),
                shape = RoundedCornerShape(2.dp),
                modifier = Modifier.padding(top = 1.dp)
            ) {
                Text(
                    text = "xG %.1f".format(player.player.xg),
                    modifier = Modifier.padding(horizontal = 3.dp),
                    color = Color.White,
                    fontSize = 6.sp,
                    fontWeight = FontWeight.Black
                )
            }
        }
    }
}
