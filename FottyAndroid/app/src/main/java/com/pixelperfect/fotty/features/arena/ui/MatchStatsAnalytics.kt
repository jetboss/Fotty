package com.pixelperfect.fotty.features.arena.ui

import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.tween
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Info
import androidx.compose.material.icons.filled.Notifications
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.pixelperfect.fotty.ui.components.*
import androidx.compose.ui.unit.sp
import com.pixelperfect.fotty.core.theme.Accent
import com.pixelperfect.fotty.core.theme.Background
import com.pixelperfect.fotty.core.network.models.football.APIFootballTeamStats
import com.pixelperfect.fotty.core.theme.*

@Composable
fun MatchStatisticsList(
    homeTeamName: String,
    awayTeamName: String,
    stats: List<APIFootballTeamStats>,
    modifier: Modifier = Modifier
) {
    if (stats.isEmpty()) return
    
    val normalizer = com.pixelperfect.fotty.core.util.TeamNameNormalizer
    
    val homeStats = stats.find { normalizer.fuzzyMatch(it.team.name, homeTeamName) }?.statistics ?: emptyList()
    val awayStats = stats.find { normalizer.fuzzyMatch(it.team.name, awayTeamName) }?.statistics ?: emptyList()

    Column(
        modifier = modifier
            .fillMaxWidth()
            .clip(MaterialTheme.shapes.extraLarge)
            .background(MaterialTheme.colorScheme.surface)
            .padding(24.dp),
        verticalArrangement = Arrangement.spacedBy(20.dp)
    ) {
        SectionHeader(title = "MATCH DATA STREAMS")

        val commonStats = listOf(
            "Expected Goals (xG)" to "EXPECTED GOALS",
            "xG on Target (xGoT)" to "TARGET QUALITY",
            "Ball Possession" to "POSSESSION",
            "Big Chances Created" to "BIG CHANCES",
            "Total Shots" to "TOTAL SHOTS",
            "Shots on Target" to "ON TARGET",
            "Corner Kicks" to "CORNERS"
        )

        commonStats.forEach { (type, label) ->
            val homeStat = homeStats.find { it.type == type }
            val awayStat = awayStats.find { it.type == type }
            
            val homeVal = homeStat?.value?.toString()?.replace("%", "")?.toFloatOrNull() ?: 0f
            val awayVal = awayStat?.value?.toString()?.replace("%", "")?.toFloatOrNull() ?: 0f
            
            StatRow(
                label = label,
                homeValue = homeVal,
                awayValue = awayVal,
                isPercentage = type.contains("Possession")
            )
        }
    }
}

@Composable
fun StatRow(
    label: String,
    homeValue: Float,
    awayValue: Float,
    isPercentage: Boolean
) {
    val total = if (homeValue + awayValue == 0f) 1f else homeValue + awayValue
    val progress = homeValue / total

    val displayHome = if (isPercentage) "${homeValue.toInt()}%" else if (homeValue % 1 == 0f) "${homeValue.toInt()}" else "%.2f".format(homeValue)
    val displayAway = if (isPercentage) "${awayValue.toInt()}%" else if (awayValue % 1 == 0f) "${awayValue.toInt()}" else "%.2f".format(awayValue)

    Column(modifier = Modifier.fillMaxWidth()) {
        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.SpaceBetween,
            verticalAlignment = Alignment.Bottom
        ) {
            Text(
                text = displayHome,
                color = MaterialTheme.colorScheme.primary,
                style = MaterialTheme.typography.titleLarge.copy(fontWeight = FontWeight.Black)
            )
            Text(
                text = label,
                style = MaterialTheme.typography.labelSmall.copy(color = MaterialTheme.colorScheme.onSurfaceVariant)
            )
            Text(
                text = displayAway,
                color = MaterialTheme.colorScheme.onSurface,
                style = MaterialTheme.typography.titleLarge.copy(fontWeight = FontWeight.Black)
            )
        }
        
        Spacer(modifier = Modifier.height(8.dp))
        
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .height(4.dp)
                .clip(CircleShape)
                .background(MaterialTheme.colorScheme.surfaceVariant)
        ) {
            Box(
                modifier = Modifier
                    .fillMaxHeight()
                    .weight(progress.coerceAtLeast(0.01f))
                    .background(MaterialTheme.colorScheme.primary)
            )
            Box(
                modifier = Modifier
                    .fillMaxHeight()
                    .weight((1f - progress).coerceAtLeast(0.01f))
                    .background(MaterialTheme.colorScheme.outlineVariant)
            )
        }
    }
}

@Composable
fun MomentumChart(
    momentum: List<Float>,
    modifier: Modifier = Modifier
) {
    Column(
        modifier = modifier
            .fillMaxWidth()
            .clip(MaterialTheme.shapes.extraLarge)
            .background(MaterialTheme.colorScheme.surface)
            .padding(24.dp)
    ) {
        SectionHeader(title = "ATTACKING MOMENTUM")
        Spacer(modifier = Modifier.height(24.dp))
        
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .height(100.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(2.dp)
        ) {
            val displayMomentum = if (momentum.isEmpty()) List(60) { (kotlin.random.Random.nextFloat() * 2 - 1) * 10 } else momentum
            displayMomentum.forEach { value ->
                val height = (kotlin.math.abs(value) * 5).coerceIn(2f, 100f)
                val isPositive = value >= 0f
                
                Box(
                    modifier = Modifier
                        .weight(1f)
                        .height(height.dp)
                        .clip(CircleShape)
                        .background(
                            if (isPositive) MaterialTheme.colorScheme.primary.copy(alpha = 0.8f) 
                            else MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.3f)
                        )
                )
            }
        }
        
        Spacer(modifier = Modifier.height(16.dp))
        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.SpaceBetween
        ) {
            Text("DOMINANCE", style = MaterialTheme.typography.labelSmall.copy(color = MaterialTheme.colorScheme.primary))
            Text("60' / 90'", style = MaterialTheme.typography.labelSmall.copy(color = MaterialTheme.colorScheme.onSurfaceVariant))
        }
    }
}


@Composable
fun MatchTimeline(
    events: List<com.pixelperfect.fotty.core.network.models.football.APIFootballEvent>,
    modifier: Modifier = Modifier
) {
    Column(
        modifier = modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(12.dp))
            .background(MaterialTheme.colorScheme.surface)
            .padding(16.dp),
        verticalArrangement = Arrangement.spacedBy(16.dp)
    ) {
        Text(
            text = "Match Timeline",
            color = MaterialTheme.colorScheme.onSurface,
            fontWeight = FontWeight.Bold,
            fontSize = 16.sp
        )

        if (events.isEmpty()) {
            Text("No events recorded yet.", color = MaterialTheme.colorScheme.onSurfaceVariant, fontSize = 12.sp)
        } else {
            events.forEach { event ->
                EventRow(event = event)
            }
        }
    }
}

@Composable
fun EventRow(event: com.pixelperfect.fotty.core.network.models.football.APIFootballEvent) {
    Row(
        modifier = Modifier.fillMaxWidth(),
        verticalAlignment = Alignment.CenterVertically
    ) {
        // Time
        Text(
            text = "${event.time.elapsed}'",
            color = MaterialTheme.colorScheme.primary,
            fontWeight = FontWeight.Bold,
            fontSize = 14.sp,
            modifier = Modifier.width(36.dp)
        )

        // Event Icon
        Box(
            modifier = Modifier
                .size(24.dp)
                .clip(CircleShape)
                .background(Color.Black.copy(alpha = 0.2f)),
            contentAlignment = Alignment.Center
        ) {
            val iconText = when (event.type.lowercase()) {
                "goal" -> "⚽"
                "card" -> if (event.detail.contains("Yellow")) "🟨" else "🟥"
                "subst" -> "🔄"
                else -> "•"
            }
            Text(iconText, fontSize = 12.sp)
        }

        Spacer(modifier = Modifier.width(12.dp))

        // Details
        Column {
            Text(
                text = event.player.name,
                color = MaterialTheme.colorScheme.onSurface,
                fontSize = 14.sp,
                fontWeight = FontWeight.Medium
            )
            if (event.assist?.name != null) {
                Text(
                    text = "Assist: ${event.assist.name}",
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    fontSize = 11.sp
                )
            } else if (event.detail.isNotEmpty()) {
                Text(
                    text = event.detail,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    fontSize = 11.sp
                )
            }
        }
    }
}

@Composable
fun JusticeTableCard(
    homeTeamName: String,
    awayTeamName: String,
    homeGoals: Int,
    awayGoals: Int,
    homeXG: Float,
    awayXG: Float,
    events: List<com.pixelperfect.fotty.core.network.models.football.APIFootballEvent> = emptyList(),
    modifier: Modifier = Modifier
) {
    val expectedWinner = if (homeXG > awayXG + 0.3f) homeTeamName else if (awayXG > homeXG + 0.3f) awayTeamName else "Draw"
    val actualWinner = if (homeGoals > awayGoals) homeTeamName else if (awayGoals > homeGoals) awayTeamName else "Draw"
    val isUnjust = expectedWinner != actualWinner

    Column(
        modifier = modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(12.dp))
            .background(Surface)
            .padding(16.dp)
    ) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Text(
                text = "Justice Table",
                color = MaterialTheme.colorScheme.onSurface,
                fontWeight = FontWeight.Bold,
                fontSize = 16.sp
            )
            Spacer(modifier = Modifier.width(8.dp))
            if (isUnjust) {
                Surface(
                    color = MaterialTheme.colorScheme.error.copy(alpha = 0.2f),
                    shape = RoundedCornerShape(4.dp)
                ) {
                    Text(
                        "UNJUST RESULT",
                        modifier = Modifier.padding(horizontal = 6.dp, vertical = 2.dp),
                        color = MaterialTheme.colorScheme.error,
                        fontSize = 8.sp,
                        fontWeight = FontWeight.ExtraBold
                    )
                }
            }
        }
        
        Spacer(modifier = Modifier.height(16.dp))
        
        Text(
            text = "Based on match quality (xG), the expected outcome was a ${if (expectedWinner == "Draw") "Draw" else "$expectedWinner Win"}.",
            color = Color.Gray,
            fontSize = 12.sp,
            lineHeight = 18.sp
        )
        
        Spacer(modifier = Modifier.height(20.dp))
        
        Row(modifier = Modifier.fillMaxWidth()) {
            Column(modifier = Modifier.weight(1f)) {
                Text("ACTUAL", color = MaterialTheme.colorScheme.onSurfaceVariant, fontSize = 9.sp, fontWeight = FontWeight.Bold)
                Text(
                    text = if (actualWinner == "Draw" && homeGoals == 0 && awayGoals == 0) "LIVE" else "$homeGoals - $awayGoals", 
                    color = MaterialTheme.colorScheme.onSurface, 
                    fontSize = 24.sp, 
                    fontWeight = FontWeight.ExtraBold
                )
            }
            Column(modifier = Modifier.weight(1f), horizontalAlignment = Alignment.End) {
                Text("EXPECTED (xG)", color = MaterialTheme.colorScheme.primary, fontSize = 9.sp, fontWeight = FontWeight.Bold)
                Text("%.2f - %.2f".format(homeXG, awayXG), color = MaterialTheme.colorScheme.primary, fontSize = 24.sp, fontWeight = FontWeight.ExtraBold)
            }
        }

        Spacer(modifier = Modifier.height(24.dp))
        
        // xG Timeline
        Text("xG Timeline", color = MaterialTheme.colorScheme.onSurfaceVariant, fontSize = 11.sp, fontWeight = FontWeight.Bold)
        Spacer(modifier = Modifier.height(8.dp))
        XGTimeline(events = events, homeXG = homeXG, awayXG = awayXG)

        Spacer(modifier = Modifier.height(24.dp))
        
        // Tactical Heatmap Placeholder / Visualization
        Text("Tactical Dominance", color = MaterialTheme.colorScheme.onSurfaceVariant, fontSize = 11.sp, fontWeight = FontWeight.Bold)
        Spacer(modifier = Modifier.height(8.dp))
        TacticalHeatmap(homeTeamName = homeTeamName, awayTeamName = awayTeamName)
    }
}

@Composable
fun XGTimeline(
    events: List<com.pixelperfect.fotty.core.network.models.football.APIFootballEvent>,
    homeXG: Float,
    awayXG: Float
) {
    Box(
        modifier = Modifier
            .fillMaxWidth()
            .height(120.dp)
            .clip(RoundedCornerShape(8.dp))
            .background(Color.Black.copy(alpha = 0.3f))
            .padding(8.dp)
    ) {
        val outlineVariant = MaterialTheme.colorScheme.outlineVariant
        val primaryColor = MaterialTheme.colorScheme.primary
        
        // Simple step chart simulation
        androidx.compose.foundation.Canvas(modifier = Modifier.fillMaxSize()) {
            val width = size.width
            val height = size.height
            val maxMinutes = 90f
            val maxXG = (homeXG + awayXG).coerceAtLeast(1f)
            
            // Draw baseline
            drawLine(outlineVariant.copy(alpha = 0.2f), start = androidx.compose.ui.geometry.Offset(0f, height/2), end = androidx.compose.ui.geometry.Offset(width, height/2), strokeWidth = 1f)
            
            // Home xG (Top half)
            var currentHomeXG = 0f
            val homePath = androidx.compose.ui.graphics.Path().apply {
                moveTo(0f, height/2)
                events.filter { it.type.lowercase() == "goal" }.sortedBy { it.time.elapsed }.forEach { event ->
                    val x = (event.time.elapsed / maxMinutes) * width
                    lineTo(x, height/2 - (currentHomeXG / maxXG) * (height/2))
                    currentHomeXG += 0.5f // Simulate step
                    lineTo(x, height/2 - (currentHomeXG / maxXG) * (height/2))
                }
                lineTo(width, height/2 - (currentHomeXG / maxXG) * (height/2))
            }
            drawPath(homePath, primaryColor, style = androidx.compose.ui.graphics.drawscope.Stroke(2f))

            // Away xG (Bottom half)
            var currentAwayXG = 0f
            val awayPath = androidx.compose.ui.graphics.Path().apply {
                moveTo(0f, height/2)
                events.filter { it.type.lowercase() == "goal" }.sortedBy { it.time.elapsed }.forEach { event ->
                    val x = (event.time.elapsed / maxMinutes) * width
                    lineTo(x, height/2 + (currentAwayXG / maxXG) * (height/2))
                    currentAwayXG += 0.5f // Simulate step
                    lineTo(x, height/2 + (currentAwayXG / maxXG) * (height/2))
                }
                lineTo(width, height/2 + (currentAwayXG / maxXG) * (height/2))
            }
            drawPath(awayPath, Color.White.copy(alpha = 0.6f), style = androidx.compose.ui.graphics.drawscope.Stroke(2f))
        }
    }
}

@Composable
fun TacticalHeatmap(homeTeamName: String, awayTeamName: String) {
    Box(
        modifier = Modifier
            .fillMaxWidth()
            .height(180.dp)
            .clip(RoundedCornerShape(8.dp))
            .background(Color(0xFF1B3B1B)) // Football pitch dark green
            .padding(12.dp)
    ) {
        // Pitch markings
        androidx.compose.foundation.Canvas(modifier = Modifier.fillMaxSize()) {
            val w = size.width
            val h = size.height
            drawRect(Color.White.copy(alpha = 0.3f), style = androidx.compose.ui.graphics.drawscope.Stroke(1f))
            drawLine(Color.White.copy(alpha = 0.3f), start = androidx.compose.ui.geometry.Offset(w/2, 0f), end = androidx.compose.ui.geometry.Offset(w/2, h), strokeWidth = 1f)
            drawCircle(Color.White.copy(alpha = 0.3f), radius = 30.dp.toPx(), center = androidx.compose.ui.geometry.Offset(w/2, h/2), style = androidx.compose.ui.graphics.drawscope.Stroke(1f))
        }
        
        // Simulated Heat Clusters
        Row(modifier = Modifier.fillMaxSize()) {
            Box(modifier = Modifier.weight(1f).fillMaxHeight()) {
                // Home pressure (left)
                Box(modifier = Modifier.size(60.dp).align(Alignment.Center).background(Accent.copy(alpha = 0.2f), CircleShape))
                Box(modifier = Modifier.size(30.dp).align(Alignment.Center).background(Accent.copy(alpha = 0.4f), CircleShape))
            }
            Box(modifier = Modifier.weight(1f).fillMaxHeight()) {
                // Away pressure (right)
                Box(modifier = Modifier.size(80.dp).align(Alignment.Center).background(Color.White.copy(alpha = 0.1f), CircleShape))
                Box(modifier = Modifier.size(40.dp).align(Alignment.Center).background(Color.White.copy(alpha = 0.2f), CircleShape))
            }
        }
        
        Row(
            modifier = Modifier.fillMaxSize(),
            verticalAlignment = Alignment.Bottom,
            horizontalArrangement = Arrangement.SpaceBetween
        ) {
            Text(homeTeamName.uppercase(), color = MaterialTheme.colorScheme.primary, fontSize = 9.sp, fontWeight = FontWeight.Black)
            Text(awayTeamName.uppercase(), color = Color.White.copy(alpha = 0.7f), fontSize = 9.sp, fontWeight = FontWeight.Black)
        }
    }
}
