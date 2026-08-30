package com.pixelperfect.fotty.features.live.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.material3.*
import androidx.compose.material3.TabRowDefaults.tabIndicatorOffset
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.input.nestedscroll.nestedScroll
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.hilt.navigation.compose.hiltViewModel
import com.pixelperfect.fotty.core.theme.*
import com.pixelperfect.fotty.core.ui.components.MaterialLiveCard
import com.pixelperfect.fotty.features.live.viewmodel.LiveUiState
import com.pixelperfect.fotty.core.theme.*
import com.pixelperfect.fotty.data.models.Match
import com.pixelperfect.fotty.features.live.viewmodel.LiveViewModel
import com.pixelperfect.fotty.core.network.models.nexus.NexusAEvent
import com.pixelperfect.fotty.ui.components.*
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.ErrorOutline
import androidx.compose.material.icons.filled.EventBusy

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun LiveScreen(
    viewModel: LiveViewModel = hiltViewModel(),
    onMatchClick: (Match) -> Unit
) {
    val uiState by viewModel.uiState.collectAsState()
    val selectedSport by viewModel.selectedSport.collectAsState()
    val leagues by viewModel.leagues.collectAsState()
    val selectedLeague by viewModel.selectedLeague.collectAsState()

    val scrollBehavior = TopAppBarDefaults.exitUntilCollapsedScrollBehavior()

    Scaffold(
        modifier = Modifier.nestedScroll(scrollBehavior.nestedScrollConnection),
        containerColor = MaterialTheme.colorScheme.background,
        topBar = {
            LargeTopAppBar(
                title = { 
                    Column {
                        Text(
                            "PITCH", 
                            style = MaterialTheme.typography.displaySmall.copy(
                                fontWeight = FontWeight.Black,
                                letterSpacing = 2.sp,
                                color = MaterialTheme.colorScheme.primary
                            )
                        )
                        Text(
                            "LIVE GLOBAL FIXTURES",
                            style = MaterialTheme.typography.labelSmall.copy(
                                color = MaterialTheme.colorScheme.onSurfaceVariant,
                                letterSpacing = 1.sp
                            )
                        )
                    }
                },
                scrollBehavior = scrollBehavior,
                colors = TopAppBarDefaults.largeTopAppBarColors(
                    containerColor = Color.Transparent,
                    scrolledContainerColor = MaterialTheme.colorScheme.surface.copy(alpha = 0.95f)
                )
            )
        }
    ) { padding ->
        LazyColumn(
            modifier = Modifier
                .fillMaxSize()
                .padding(padding),
            contentPadding = PaddingValues(bottom = 120.dp)
        ) {
            // Sport & League Selectors
            item {
                SportSelector(
                    sports = viewModel.sports,
                    selectedSport = selectedSport,
                    onSportSelected = { viewModel.setSport(it) }
                )
                
                if (selectedSport == "Football") {
                    LeagueSelector(
                        leagues = leagues,
                        selectedLeague = selectedLeague,
                        onLeagueSelected = { viewModel.setLeague(it) }
                    )
                }
                Spacer(modifier = Modifier.height(16.dp))
            }

            // Main Feed
            when (val state = uiState) {
                is LiveUiState.Loading -> {
                    items(5) {
                        Box(
                            modifier = Modifier
                                .padding(horizontal = 16.dp, vertical = 8.dp)
                                .fillMaxWidth()
                                .height(140.dp)
                                .clip(MaterialTheme.shapes.extraLarge)
                                .shimmerEffect()
                        )
                    }
                }
                is LiveUiState.Error -> {
                    item {
                        ErrorState(message = state.message, onRetry = { viewModel.refresh() })
                    }
                }
                is LiveUiState.Empty -> {
                    item {
                        EmptyState(onRefresh = { viewModel.refresh() })
                    }
                }
                is LiveUiState.Success -> {
                    item {
                        SectionHeader(
                            title = if (state.matches.any { it.status == com.pixelperfect.fotty.data.models.MatchStatus.LIVE }) "LIVE NOW" else "TODAY'S FIXTURES", 
                            modifier = Modifier.padding(start = 24.dp, end = 24.dp, bottom = 12.dp)
                        )
                    }
                    items(state.matches) { match ->
                        com.pixelperfect.fotty.core.ui.LiveMatchLargeCard(
                            match = match,
                            onClick = { onMatchClick(match) }
                        )
                    }
                }
            }
        }
    }
}

@Composable
private fun SportSelector(
    sports: List<String>,
    selectedSport: String,
    onSportSelected: (String) -> Unit
) {
    ScrollableTabRow(
        selectedTabIndex = sports.indexOf(selectedSport),
        containerColor = Color.Transparent,
        edgePadding = 16.dp,
        divider = {},
        indicator = { tabPositions ->
            TabRowDefaults.SecondaryIndicator(
                Modifier.tabIndicatorOffset(tabPositions[sports.indexOf(selectedSport)]),
                color = MaterialTheme.colorScheme.primary
            )
        }
    ) {
        sports.forEach { sport ->
            Tab(
                selected = selectedSport == sport,
                onClick = { onSportSelected(sport) },
                text = {
                    Text(
                        text = sport.uppercase(),
                        style = MaterialTheme.typography.labelSmall.copy(
                            fontWeight = if (selectedSport == sport) FontWeight.Black else FontWeight.Medium
                        )
                    )
                }
            )
        }
    }
}

@Composable
private fun LeagueSelector(
    leagues: List<String>,
    selectedLeague: String?,
    onLeagueSelected: (String) -> Unit
) {
    LazyRow(
        contentPadding = PaddingValues(horizontal = 16.dp, vertical = 12.dp),
        horizontalArrangement = Arrangement.spacedBy(8.dp)
    ) {
        items(leagues) { league ->
            val isSelected = selectedLeague == league
            FilterChip(
                selected = isSelected,
                onClick = { onLeagueSelected(league) },
                label = { Text(league) },
                shape = MaterialTheme.shapes.extraLarge,
                colors = FilterChipDefaults.filterChipColors(
                    selectedContainerColor = MaterialTheme.colorScheme.primaryContainer,
                    selectedLabelColor = MaterialTheme.colorScheme.onPrimaryContainer
                )
            )
        }
    }
}

@Composable
private fun ErrorState(message: String, onRetry: () -> Unit) {
    Box(modifier = Modifier.fillMaxWidth().padding(48.dp), contentAlignment = Alignment.Center) {
        Column(horizontalAlignment = Alignment.CenterHorizontally) {
            Icon(
                imageVector = Icons.Default.ErrorOutline,
                contentDescription = null,
                tint = MaterialTheme.colorScheme.error,
                modifier = Modifier.size(48.dp)
            )
            Spacer(modifier = Modifier.height(16.dp))
            Text(text = message, color = MaterialTheme.colorScheme.error, textAlign = androidx.compose.ui.text.style.TextAlign.Center)
            Spacer(modifier = Modifier.height(16.dp))
            Button(onClick = onRetry) {
                Text("RETRY")
            }
        }
    }
}

@Composable
private fun EmptyState(onRefresh: () -> Unit) {
    Box(modifier = Modifier.fillMaxWidth().height(400.dp), contentAlignment = Alignment.Center) {
        Column(horizontalAlignment = Alignment.CenterHorizontally, modifier = Modifier.padding(32.dp)) {
            Icon(
                imageVector = Icons.Default.EventBusy,
                contentDescription = null,
                tint = MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.5f),
                modifier = Modifier.size(64.dp)
            )
            Spacer(modifier = Modifier.height(24.dp))
            Text("NO MATCHES FOUND", style = MaterialTheme.typography.titleMedium.copy(fontWeight = FontWeight.Black))
            Spacer(modifier = Modifier.height(8.dp))
            Text(
                "There are no live or scheduled matches matching your current filters.", 
                style = MaterialTheme.typography.bodySmall, 
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                textAlign = androidx.compose.ui.text.style.TextAlign.Center
            )
            Spacer(modifier = Modifier.height(24.dp))
            OutlinedButton(onClick = onRefresh) {
                Text("REFRESH PITCH")
            }
        }
    }
}

