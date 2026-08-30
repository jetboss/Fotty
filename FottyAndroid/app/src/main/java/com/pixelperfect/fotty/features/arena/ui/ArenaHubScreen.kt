package com.pixelperfect.fotty.features.arena.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import coil.compose.AsyncImage
import com.pixelperfect.fotty.core.network.models.football.APIFootballFixture
import com.pixelperfect.fotty.features.arena.viewmodel.InsightsViewModel
import com.pixelperfect.fotty.core.theme.*
import com.pixelperfect.fotty.ui.components.*

@Composable
fun ArenaHubScreen(
    viewModel: InsightsViewModel,
    onWatch: (APIFootballFixture) -> Unit
) {
    val liveMatches by viewModel.liveMatches.collectAsState()
    val isLoading by viewModel.isLoading.collectAsState()
    var selectedFixture by remember { mutableStateOf<APIFootballFixture?>(null) }
    
    val groupedMatches = remember(liveMatches) {
        liveMatches.groupBy { it.league.name }
    }

    Box(
        modifier = Modifier
            .fillMaxSize()
            .background(MaterialTheme.colorScheme.background)
    ) {
        Column(modifier = Modifier.fillMaxSize()) {
            // 1. TACTICAL ANALYTICS HEADER
            Box(
                modifier = Modifier
                    .fillMaxWidth()
                    .statusBarsPadding()
                    .monolithSurface(borderColor = Color.White.copy(alpha = 0.1f))
                    .padding(horizontal = 24.dp, vertical = 20.dp)
            ) {
                Column {
                    Text(
                        text = "ARENA",
                        style = MaterialTheme.typography.displaySmall.copy(
                            fontWeight = FontWeight.Black,
                            letterSpacing = 2.sp,
                            color = MaterialTheme.colorScheme.primary,
                            fontFamily = androidx.compose.ui.text.font.FontFamily.Monospace
                        )
                    )
                    Text(
                        text = "INTELLIGENCE LAYER ACTIVE",
                        style = MaterialTheme.typography.labelSmall.copy(
                            color = Color.Gray,
                            letterSpacing = 1.5.sp,
                            fontFamily = androidx.compose.ui.text.font.FontFamily.Monospace
                        )
                    )
                }
            }

            if (selectedFixture == null) {
                if (isLoading && liveMatches.isEmpty()) {
                    Box(modifier = Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                        CircularProgressIndicator(color = MaterialTheme.colorScheme.primary, strokeWidth = 1.dp)
                    }
                } else {
                    LazyColumn(
                        modifier = Modifier.fillMaxSize(),
                        contentPadding = PaddingValues(bottom = 120.dp, start = 16.dp, end = 16.dp, top = 24.dp),
                        verticalArrangement = Arrangement.spacedBy(16.dp)
                    ) {
                        groupedMatches.forEach { (leagueName, matches) ->
                            item(key = leagueName) {
                                Text(
                                    text = leagueName.uppercase(),
                                    style = MaterialTheme.typography.labelSmall.copy(
                                        color = Color.Gray,
                                        letterSpacing = 2.sp,
                                        fontWeight = FontWeight.Bold,
                                        fontFamily = androidx.compose.ui.text.font.FontFamily.Monospace
                                    ),
                                    modifier = Modifier.padding(bottom = 8.dp, start = 8.dp)
                                )
                            }
                            items(matches, key = { it.fixture.id }) { fixture ->
                                MonolithInsightCard(fixture = fixture) {
                                    selectedFixture = fixture
                                }
                            }
                        }
                    }
                }
            } else {
                // Detail view with flick to dismiss
                Box(modifier = Modifier.fillMaxSize().flickToDismiss { selectedFixture = null }) {
                    MatchDetailInsightsView(
                        fixture = selectedFixture!!,
                        viewModel = viewModel,
                        onBack = { selectedFixture = null },
                        onWatch = onWatch
                    )
                }
            }
        }
    }
}

@Composable
private fun MonolithInsightCard(
    fixture: APIFootballFixture,
    onClick: () -> Unit
) {
    Box(
        modifier = Modifier
            .fillMaxWidth()
            .monolithSurface(borderColor = Color.White.copy(alpha = 0.08f))
            .clickable { onClick() }
            .padding(12.dp)
    ) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            TeamBadge(crestUrl = fixture.teams.home.logo, name = fixture.teams.home.name, size = 24.dp)
            Spacer(modifier = Modifier.width(12.dp))
            Column(modifier = Modifier.weight(1f)) {
                Text(
                    text = "${fixture.teams.home.name.uppercase()} — ${fixture.teams.away.name.uppercase()}",
                    style = MaterialTheme.typography.bodyMedium.copy(
                        fontWeight = FontWeight.Black,
                        fontFamily = androidx.compose.ui.text.font.FontFamily.Monospace
                    ),
                    color = Color.White,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis
                )
                Text(
                    text = "PRECISION ANALYTICS READY",
                    style = MaterialTheme.typography.labelSmall.copy(
                        fontSize = 8.sp,
                        fontFamily = androidx.compose.ui.text.font.FontFamily.Monospace
                    ),
                    color = MaterialTheme.colorScheme.primary
                )
            }
            val isLive = fixture.fixture.status.short in listOf("1H", "2H", "ET", "P", "BT", "HT", "LIVE")
            
            Column(horizontalAlignment = Alignment.End) {
                if (isLive) {
                    Surface(
                        color = MaterialTheme.colorScheme.error,
                        shape = RoundedCornerShape(4.dp)
                    ) {
                        Text(
                            text = "LIVE",
                            modifier = Modifier.padding(horizontal = 6.dp, vertical = 2.dp),
                            style = MaterialTheme.typography.labelSmall.copy(
                                fontWeight = FontWeight.Black,
                                fontSize = 10.sp,
                                fontFamily = androidx.compose.ui.text.font.FontFamily.Monospace
                            ),
                            color = Color.White
                        )
                    }
                    Spacer(modifier = Modifier.height(4.dp))
                    Text(
                        text = "${fixture.fixture.status.elapsed ?: 0}'",
                        style = MaterialTheme.typography.titleMedium.copy(
                            fontWeight = FontWeight.Black,
                            fontFamily = androidx.compose.ui.text.font.FontFamily.Monospace
                        ),
                        color = MaterialTheme.colorScheme.primary
                    )
                } else {
                    Text(
                        text = com.pixelperfect.fotty.core.util.DateUtils.formatIsoTime(fixture.fixture.date),
                        style = MaterialTheme.typography.titleMedium.copy(
                            fontWeight = FontWeight.Black,
                            fontFamily = androidx.compose.ui.text.font.FontFamily.Monospace
                        ),
                        color = Color.Gray
                    )
                }
            }
            Spacer(modifier = Modifier.width(12.dp))
            TeamBadge(crestUrl = fixture.teams.away.logo, name = fixture.teams.away.name, size = 24.dp)
        }
    }
}

@Composable
fun MatchDetailInsightsView(
    fixture: APIFootballFixture,
    viewModel: InsightsViewModel,
    onBack: () -> Unit,
    onWatch: (APIFootballFixture) -> Unit
) {
    val stats by viewModel.selectedMatchStats.collectAsState()
    val lineups by viewModel.selectedMatchLineups.collectAsState()
    val events by viewModel.selectedMatchEvents.collectAsState()
    val momentum by viewModel.matchMomentum.collectAsState()
    val insights by viewModel.insights.collectAsState()

    LaunchedEffect(fixture.fixture.id) {
        viewModel.loadMatchInsights(fixture.fixture.id)
    }

    LazyColumn(
        modifier = Modifier.fillMaxSize().background(MaterialTheme.colorScheme.background),
        contentPadding = PaddingValues(24.dp),
        verticalArrangement = Arrangement.spacedBy(24.dp)
    ) {
        item {
            // SCORE-FREE HEADER
            val isLive = fixture.fixture.status.short in listOf("1H", "2H", "ET", "P", "BT", "HT", "LIVE")
            Column(horizontalAlignment = Alignment.CenterHorizontally, modifier = Modifier.fillMaxWidth()) {
                Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.Center) {
                    TeamBadge(crestUrl = fixture.teams.home.logo, name = fixture.teams.home.name, size = 32.dp)
                    Spacer(modifier = Modifier.width(16.dp))
                    Column(horizontalAlignment = Alignment.CenterHorizontally) {
                        if (isLive) {
                            Surface(
                                color = MaterialTheme.colorScheme.error,
                                shape = RoundedCornerShape(4.dp)
                            ) {
                                Text(
                                    text = "LIVE",
                                    modifier = Modifier.padding(horizontal = 8.dp, vertical = 2.dp),
                                    style = MaterialTheme.typography.labelSmall.copy(
                                        fontWeight = FontWeight.Black,
                                        fontFamily = androidx.compose.ui.text.font.FontFamily.Monospace
                                    ),
                                    color = Color.White
                                )
                            }
                            Spacer(modifier = Modifier.height(4.dp))
                            Text(
                                text = "${fixture.fixture.status.elapsed ?: 0}'",
                                style = MaterialTheme.typography.displaySmall.copy(
                                    fontWeight = FontWeight.Black,
                                    fontFamily = androidx.compose.ui.text.font.FontFamily.Monospace
                                )
                            )
                        } else {
                            Text(
                                text = com.pixelperfect.fotty.core.util.DateUtils.formatIsoTime(fixture.fixture.date),
                                style = MaterialTheme.typography.titleLarge.copy(
                                    fontWeight = FontWeight.Black,
                                    fontFamily = androidx.compose.ui.text.font.FontFamily.Monospace
                                )
                            )
                            Text(
                                text = fixture.fixture.status.long.uppercase(),
                                style = MaterialTheme.typography.labelSmall,
                                color = Color.Gray
                            )
                        }
                    }
                    Spacer(modifier = Modifier.width(16.dp))
                    TeamBadge(crestUrl = fixture.teams.away.logo, name = fixture.teams.away.name, size = 32.dp)
                }
                Spacer(modifier = Modifier.height(8.dp))
                Text(
                    text = "${fixture.teams.home.name.uppercase()} vs ${fixture.teams.away.name.uppercase()}",
                    style = MaterialTheme.typography.labelLarge.copy(fontWeight = FontWeight.Black),
                    color = Color.White.copy(alpha = 0.7f)
                )
            }
        }

        item {
            // TACTICAL PITCH MODULE
            Box(modifier = Modifier.fillMaxWidth().monolithSurface().padding(16.dp)) {
                TacticalPitch(
                    homeLineup = lineups.firstOrNull(),
                    awayLineup = lineups.getOrNull(1)
                )
            }
        }

        item {
            // MOMENTUM MODULE
            MomentumChart(momentum = momentum)
        }

        items(insights) { insight ->
            SmartInsightCard(insight = insight)
        }

        item {
            // WATCH BUTTON (TACTICAL STYLE)
            Box(
                modifier = Modifier
                    .fillMaxWidth()
                    .monolithSurface(borderColor = MaterialTheme.colorScheme.primary)
                    .tacticalPulse()
                    .clickable { onWatch(fixture) }
                    .padding(16.dp),
                contentAlignment = Alignment.Center
            ) {
                Text(
                    "ACCESS LIVE DATA FEED", 
                    style = MaterialTheme.typography.labelSmall, 
                    fontWeight = FontWeight.Black, 
                    fontFamily = androidx.compose.ui.text.font.FontFamily.Monospace,
                    color = Color.White
                )
            }
        }
    }
}

@Composable
fun SmartInsightCard(insight: com.pixelperfect.fotty.features.arena.viewmodel.MatchInsight) {
    Box(
        modifier = Modifier
            .fillMaxWidth()
            .monolithSurface(borderColor = Color.White.copy(alpha = 0.1f))
            .padding(16.dp)
    ) {
        Column {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Box(
                    modifier = Modifier
                        .size(6.dp)
                        .background(
                            when(insight.type) {
                                com.pixelperfect.fotty.features.arena.viewmodel.InsightType.TACTICAL -> Color.Cyan
                                com.pixelperfect.fotty.features.arena.viewmodel.InsightType.STATISTICAL -> MaterialTheme.colorScheme.primary
                                com.pixelperfect.fotty.features.arena.viewmodel.InsightType.MOMENTUM -> Color.Yellow
                            }
                        )
                )
                Spacer(modifier = Modifier.width(12.dp))
                Text(
                    text = insight.title.uppercase(),
                    style = MaterialTheme.typography.labelSmall,
                    color = Color.White,
                    fontWeight = FontWeight.Black,
                    fontFamily = androidx.compose.ui.text.font.FontFamily.Monospace,
                    letterSpacing = 1.sp
                )
            }
            Spacer(modifier = Modifier.height(8.dp))
            Text(
                text = insight.description,
                style = MaterialTheme.typography.bodySmall,
                color = Color.Gray,
                fontFamily = androidx.compose.ui.text.font.FontFamily.Monospace
            )
        }
    }
}

