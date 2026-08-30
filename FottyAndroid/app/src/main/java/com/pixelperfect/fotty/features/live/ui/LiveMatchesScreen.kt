package com.pixelperfect.fotty.features.live.ui

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.foundation.lazy.grid.GridItemSpan
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.foundation.lazy.grid.items
import androidx.compose.material3.*
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.hilt.navigation.compose.hiltViewModel
import com.pixelperfect.fotty.data.models.Match
import com.pixelperfect.fotty.features.home.viewmodel.HomeViewModel
import com.pixelperfect.fotty.features.home.viewmodel.HomeUiState
import com.pixelperfect.fotty.core.ui.LiveMatchStripItem
import java.util.Locale

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun LiveMatchesScreen(
    viewModel: com.pixelperfect.fotty.features.live.viewmodel.LiveViewModel = hiltViewModel(),
    onMatchClick: (Match) -> Unit
) {
    val uiState by viewModel.uiState.collectAsState()
    val selectedSport by viewModel.selectedSport.collectAsState()

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text("Daily Fixtures") }
            )
        }
    ) { paddingValues ->
        Column(modifier = Modifier.fillMaxSize().padding(paddingValues)) {
            // SPORTS TAB BAR
            val sports = viewModel.sports
            LazyRow(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(vertical = 12.dp),
                contentPadding = PaddingValues(horizontal = 16.dp),
                horizontalArrangement = Arrangement.spacedBy(8.dp)
            ) {
                items(sports) { sport ->
                    SportTabPill(
                        label = sport,
                        isSelected = sport == selectedSport,
                        onClick = { viewModel.setSport(sport) }
                    )
                }
            }

            Box(modifier = Modifier.weight(1f)) {
                when (val state = uiState) {
                    is com.pixelperfect.fotty.features.live.viewmodel.LiveUiState.Success -> {
                        val matches = state.matches
                        val live = matches.filter { it.status == com.pixelperfect.fotty.data.models.MatchStatus.LIVE }
                        val upcoming = matches.filter { it.status == com.pixelperfect.fotty.data.models.MatchStatus.SCHEDULED }
                        
                        LazyVerticalGrid(
                            columns = GridCells.Adaptive(minSize = 320.dp),
                            modifier = Modifier.fillMaxSize(),
                            contentPadding = PaddingValues(16.dp),
                            verticalArrangement = Arrangement.spacedBy(16.dp),
                            horizontalArrangement = Arrangement.spacedBy(16.dp)
                        ) {
                            if (live.isNotEmpty()) {
                                item(span = { GridItemSpan(maxLineSpan) }) {
                                    Text(
                                        text = "LIVE NOW",
                                        style = MaterialTheme.typography.labelSmall.copy(
                                            fontWeight = FontWeight.Black,
                                            letterSpacing = 1.sp
                                        ),
                                        color = MaterialTheme.colorScheme.primary,
                                        modifier = Modifier.padding(bottom = 8.dp)
                                    )
                                }
                                items(live, key = { "live_${it.id}" }) { liveMatch ->
                                    LiveMatchStripItem(
                                        match = liveMatch,
                                        onClick = { onMatchClick(liveMatch) }
                                    )
                                }
                            }

                            if (upcoming.isNotEmpty()) {
                                item(span = { GridItemSpan(maxLineSpan) }) {
                                    Spacer(modifier = Modifier.height(16.dp))
                                    Text(
                                        text = "STARTING SOON",
                                        style = MaterialTheme.typography.labelSmall.copy(
                                            fontWeight = FontWeight.Black,
                                            letterSpacing = 1.sp
                                        ),
                                        color = MaterialTheme.colorScheme.primary,
                                        modifier = Modifier.padding(bottom = 8.dp)
                                    )
                                }
                                items(upcoming, key = { "upcoming_${it.id}" }) { upcomingMatch ->
                                    com.pixelperfect.fotty.core.ui.UpcomingMatchItem(
                                        match = upcomingMatch,
                                        onClick = { onMatchClick(upcomingMatch) }
                                    )
                                }
                            }
                        }
                    }
                    is com.pixelperfect.fotty.features.live.viewmodel.LiveUiState.Loading -> {
                        CircularProgressIndicator(modifier = Modifier.align(Alignment.Center))
                    }
                    is com.pixelperfect.fotty.features.live.viewmodel.LiveUiState.Error -> {
                        Text(
                            text = state.message, 
                            color = MaterialTheme.colorScheme.error, 
                            modifier = Modifier.align(Alignment.Center)
                        )
                    }
                    is com.pixelperfect.fotty.features.live.viewmodel.LiveUiState.Empty -> {
                        Box(modifier = Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                            Text("No fixtures for $selectedSport", style = MaterialTheme.typography.bodyLarge)
                        }
                    }
                }
            }
        }
    }
}

@Composable
private fun SportTabPill(
    label: String,
    isSelected: Boolean,
    onClick: () -> Unit
) {
    Surface(
        onClick = onClick,
        shape = androidx.compose.foundation.shape.CircleShape,
        color = if (isSelected) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.surface,
        contentColor = if (isSelected) MaterialTheme.colorScheme.onPrimary else MaterialTheme.colorScheme.onSurfaceVariant,
        border = if (isSelected) null else androidx.compose.foundation.BorderStroke(0.5.dp, MaterialTheme.colorScheme.outlineVariant),
        modifier = Modifier.height(36.dp)
    ) {
        Box(
            modifier = Modifier.padding(horizontal = 16.dp),
            contentAlignment = Alignment.Center
        ) {
            Text(
                text = label,
                style = MaterialTheme.typography.labelMedium.copy(
                    fontWeight = if (isSelected) FontWeight.ExtraBold else FontWeight.SemiBold,
                    fontSize = 13.sp
                )
            )
        }
    }
}
