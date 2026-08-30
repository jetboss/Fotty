package com.pixelperfect.fotty.features.arena.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.ArrowBack
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.hilt.navigation.compose.hiltViewModel
import com.pixelperfect.fotty.core.storage.AuthPreferenceStore
import com.pixelperfect.fotty.core.theme.*
import com.pixelperfect.fotty.features.arena.viewmodel.ArenaViewModel
import com.pixelperfect.fotty.ui.components.*
import com.pixelperfect.fotty.core.ui.components.FottyPlayer
import androidx.compose.material3.TabRowDefaults.tabIndicatorOffset
import com.pixelperfect.fotty.data.models.Match
import com.pixelperfect.fotty.core.network.models.football.*

import androidx.compose.material.icons.filled.Menu

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun MatchDetailScreen(
    fixtureId: String,
    onBack: () -> Unit,
    viewModel: com.pixelperfect.fotty.features.arena.viewmodel.InsightsViewModel = hiltViewModel(),
    arenaViewModel: ArenaViewModel = hiltViewModel(),
    authStore: AuthPreferenceStore
) {
    var selectedTab by remember { mutableIntStateOf(0) }
    val tabs = listOf("OVERVIEW", "STATS", "LINEUPS", "ARENA", "INSIGHTS")
    val id = fixtureId.toIntOrNull() ?: 0
    
    val liveMatches by viewModel.liveMatches.collectAsState()
    val fixture = liveMatches.find { it.fixture.id == id }
    
    val stats by viewModel.selectedMatchStats.collectAsState()
    val lineups by viewModel.selectedMatchLineups.collectAsState()
    val events by viewModel.selectedMatchEvents.collectAsState()
    val momentum by viewModel.matchMomentum.collectAsState()
    val isLoading by viewModel.isLoading.collectAsState()

    LaunchedEffect(id) {
        if (id != 0) {
            viewModel.loadMatchInsights(id)
        }
    }
    
    val followedTeams by viewModel.followedTeams.collectAsState()
    
    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text("MATCH CENTER", style = MaterialTheme.typography.labelLarge.copy(letterSpacing = 2.sp)) },
                navigationIcon = {
                    IconButton(onClick = onBack) {
                        Icon(Icons.Default.ArrowBack, contentDescription = "Back")
                    }
                },
                colors = TopAppBarDefaults.topAppBarColors(containerColor = MaterialTheme.colorScheme.background)
            )
        }
    ) { padding ->
        Column(modifier = Modifier.padding(padding).fillMaxSize()) {
            // 1. DYNAMIC SCORE HEADER
            MatchScoreHeader(
                fixture = fixture,
                followedTeams = followedTeams,
                onToggleFollow = { viewModel.toggleFollowTeam(it) }
            )
            
            // 2. MACHINED TAB ROW
            ScrollableTabRow(
                selectedTabIndex = selectedTab,
                containerColor = MaterialTheme.colorScheme.background,
                edgePadding = 16.dp,
                divider = {},
                indicator = { tabPositions ->
                    TabRowDefaults.SecondaryIndicator(
                        Modifier.tabIndicatorOffset(tabPositions[selectedTab]),
                        color = MaterialTheme.colorScheme.primary
                    )
                }
            ) {
                tabs.forEachIndexed { index, title ->
                    Tab(
                        selected = selectedTab == index,
                        onClick = { selectedTab = index },
                        text = {
                            Text(
                                text = title,
                                style = MaterialTheme.typography.labelSmall.copy(
                                    fontWeight = if (selectedTab == index) FontWeight.Black else FontWeight.Medium
                                )
                            )
                        }
                    )
                }
            }
            
            // 3. TAB CONTENT
            Box(modifier = Modifier.weight(1f)) {
                if (isLoading && events.isEmpty() && stats.isEmpty()) {
                    Box(modifier = Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                        CircularProgressIndicator(color = MaterialTheme.colorScheme.primary)
                    }
                } else {
                    when (selectedTab) {
                        0 -> OverviewTab(events)
                        1 -> StatsTab(stats)
                        2 -> LineupsTab(lineups)
                        3 -> ArenaTab(fixtureId, arenaViewModel, authStore)
                        4 -> InsightsTab(momentum)
                    }
                }
            }
        }
    }
}

@Composable
private fun MatchScoreHeader(
    fixture: com.pixelperfect.fotty.core.network.models.football.APIFootballFixture?,
    followedTeams: Set<String>,
    onToggleFollow: (String) -> Unit
) {
    Surface(
        modifier = Modifier.fillMaxWidth().padding(16.dp),
        shape = MaterialTheme.shapes.extraLarge,
        color = MaterialTheme.colorScheme.surfaceVariant.copy(alpha = 0.3f)
    ) {
        Row(
            modifier = Modifier.padding(24.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.SpaceBetween
        ) {
            Column(horizontalAlignment = Alignment.CenterHorizontally) {
                TeamBadge(crestUrl = fixture?.teams?.home?.logo, name = fixture?.teams?.home?.name ?: "HOME", size = 64.dp)
                Spacer(modifier = Modifier.height(8.dp))
                FollowButton(
                    isFollowed = followedTeams.contains(fixture?.teams?.home?.id?.toString() ?: ""),
                    onClick = { onToggleFollow(fixture?.teams?.home?.id?.toString() ?: "") }
                )
            }
            
            Column(horizontalAlignment = Alignment.CenterHorizontally) {
                if (fixture?.fixture?.status?.short in listOf("1H", "2H", "HT", "LIVE")) {
                    Text(
                        text = "LIVE",
                        style = MaterialTheme.typography.labelLarge.copy(
                            fontWeight = FontWeight.Black,
                            color = MaterialTheme.colorScheme.error,
                            letterSpacing = 2.sp
                        )
                    )
                    Text(
                        text = "${fixture?.fixture?.status?.elapsed ?: 0}'",
                        style = MaterialTheme.typography.displayMedium.copy(fontWeight = FontWeight.Black)
                    )
                } else {
                    Text(
                        text = fixture?.fixture?.status?.long?.uppercase() ?: "SCHEDULED",
                        style = MaterialTheme.typography.titleMedium.copy(fontWeight = FontWeight.Black),
                        color = MaterialTheme.colorScheme.onSurfaceVariant
                    )
                }
            }
            
            Column(horizontalAlignment = Alignment.CenterHorizontally) {
                TeamBadge(crestUrl = fixture?.teams?.away?.logo, name = fixture?.teams?.away?.name ?: "AWAY", size = 64.dp)
                Spacer(modifier = Modifier.height(8.dp))
                FollowButton(
                    isFollowed = followedTeams.contains(fixture?.teams?.away?.id?.toString() ?: ""),
                    onClick = { onToggleFollow(fixture?.teams?.away?.id?.toString() ?: "") }
                )
            }
        }
    }
}

@Composable
private fun FollowButton(isFollowed: Boolean, onClick: () -> Unit) {
    TextButton(
        onClick = onClick,
        modifier = Modifier.height(32.dp),
        contentPadding = PaddingValues(horizontal = 12.dp, vertical = 0.dp),
        colors = ButtonDefaults.textButtonColors(
            containerColor = if (isFollowed) MaterialTheme.colorScheme.primary.copy(alpha = 0.1f) else Color.Transparent,
            contentColor = if (isFollowed) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.onSurfaceVariant
        )
    ) {
        Text(
            text = if (isFollowed) "FOLLOWING" else "+ FOLLOW",
            style = MaterialTheme.typography.labelSmall.copy(fontWeight = FontWeight.Black)
        )
    }
}

@Composable
private fun OverviewTab(events: List<com.pixelperfect.fotty.core.network.models.football.APIFootballEvent>) {
    Column(modifier = Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(16.dp)) {
        SectionHeader(title = "MATCH TIMELINE")
        Spacer(modifier = Modifier.height(16.dp))
        
        if (events.isEmpty()) {
            Text("No major events reported yet.", style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
        } else {
            events.sortedByDescending { it.time.elapsed }.forEach { event ->
                val icon = when (event.type.lowercase()) {
                    "goal" -> "⚽"
                    "card" -> if (event.detail.contains("Red", ignoreCase = true)) "🟥" else "🟨"
                    "subst" -> "🔄"
                    else -> "•"
                }
                Row(
                    modifier = Modifier.fillMaxWidth().padding(vertical = 8.dp),
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    Text(
                        text = "${event.time.elapsed}'", 
                        style = MaterialTheme.typography.labelMedium.copy(fontWeight = FontWeight.Bold),
                        modifier = Modifier.width(40.dp)
                    )
                    Text(text = icon, modifier = Modifier.padding(horizontal = 12.dp))
                    Column {
                        Text(text = event.player.name, style = MaterialTheme.typography.bodyMedium.copy(fontWeight = FontWeight.Bold))
                        Text(text = "${event.type} - ${event.detail}", style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                    }
                }
            }
        }
    }
}

@Composable
private fun StatsTab(stats: List<com.pixelperfect.fotty.core.network.models.football.APIFootballTeamStats>) {
    Column(modifier = Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(16.dp)) {
        SectionHeader(title = "MATCH STATISTICS")
        Spacer(modifier = Modifier.height(16.dp))
        
        if (stats.isEmpty()) {
            Text("Statistics not available for this match.", style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
        } else {
            // Simplified Stats implementation
            stats.firstOrNull()?.statistics?.forEachIndexed { index, stat ->
                val homeValue = stat.value?.toString()?.replace("\"", "") ?: "0"
                val awayValue = stats.getOrNull(1)?.statistics?.getOrNull(index)?.value?.toString()?.replace("\"", "") ?: "0"
                
                Column(modifier = Modifier.fillMaxWidth().padding(vertical = 12.dp)) {
                    Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
                        Text(text = homeValue, style = MaterialTheme.typography.bodyMedium.copy(fontWeight = FontWeight.Bold))
                        Text(text = stat.type.uppercase(), style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                        Text(text = awayValue, style = MaterialTheme.typography.bodyMedium.copy(fontWeight = FontWeight.Bold))
                    }
                    Spacer(modifier = Modifier.height(4.dp))
                    // Simple progress bar could go here
                    LinearProgressIndicator(
                        progress = {
                            val h = homeValue.replace("%", "").toFloatOrNull() ?: 0f
                            val a = awayValue.replace("%", "").toFloatOrNull() ?: 0f
                            if (h + a == 0f) 0.5f else h / (h + a)
                        },
                        modifier = Modifier.fillMaxWidth(),
                        color = MaterialTheme.colorScheme.primary,
                        trackColor = MaterialTheme.colorScheme.secondary
                    )
                }
            }
        }
    }
}

@Composable
private fun LineupsTab(lineups: List<com.pixelperfect.fotty.core.network.models.football.APIFootballLineup>) {
    Box(modifier = Modifier.fillMaxSize().padding(16.dp)) {
        TacticalPitch(
            homeLineup = lineups.firstOrNull(),
            awayLineup = lineups.getOrNull(1)
        )
    }
}

@Composable
private fun ArenaTab(fixtureId: String, viewModel: ArenaViewModel, authStore: AuthPreferenceStore) {
    ArenaContent(fixtureId = fixtureId, viewModel = viewModel, authStore = authStore)
}

@Composable
private fun InsightsTab(momentum: List<Float>) {
    Column(modifier = Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(16.dp)) {
        SectionHeader(title = "MOMENTUM")
        MomentumChart(momentum = momentum)
        Spacer(modifier = Modifier.height(24.dp))
        SectionHeader(title = "PREDICTION MODELS")
        Text("AI-driven predictions are active for this fixture.", style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
    }
}

@Composable
private fun ArenaContent(fixtureId: String, viewModel: ArenaViewModel, authStore: AuthPreferenceStore) {
    Box(modifier = Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
        Column(horizontalAlignment = Alignment.CenterHorizontally) {
            Icon(Icons.Default.Menu, contentDescription = null, modifier = Modifier.size(48.dp), tint = MaterialTheme.colorScheme.primary)
            Spacer(modifier = Modifier.height(16.dp))
            Text("ARENA CHANNEL ACTIVE", style = MaterialTheme.typography.titleMedium.copy(fontWeight = FontWeight.Black))
            Text("Switch to Arena tab for live discussion", style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
    }
}

