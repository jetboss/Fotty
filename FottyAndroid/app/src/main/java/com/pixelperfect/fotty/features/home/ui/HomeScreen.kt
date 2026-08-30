package com.pixelperfect.fotty.features.home.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.material3.*
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import coil.compose.AsyncImage
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.input.nestedscroll.nestedScroll
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.graphics.Color
import androidx.hilt.navigation.compose.hiltViewModel
import com.pixelperfect.fotty.core.theme.*
import com.pixelperfect.fotty.core.ui.HeroMatchCard
import com.pixelperfect.fotty.core.ui.LiveMatchStripItem
import com.pixelperfect.fotty.core.ui.UpcomingMatchItem
import com.pixelperfect.fotty.features.home.viewmodel.HomeViewModel
import com.pixelperfect.fotty.features.home.viewmodel.HomeUiState
import com.pixelperfect.fotty.data.models.Match
import com.pixelperfect.fotty.data.models.NewsItem
import com.pixelperfect.fotty.ui.components.*

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun HomeScreen(
    viewModel: HomeViewModel = hiltViewModel(),
    onMatchClick: (Match) -> Unit,
    onNewsClick: (com.pixelperfect.fotty.data.models.NewsItem) -> Unit,
    onExploreClick: () -> Unit
) {
    val uiState by viewModel.uiState.collectAsState()
    val scrollBehavior = TopAppBarDefaults.exitUntilCollapsedScrollBehavior()

    Surface(
        modifier = Modifier.fillMaxSize(),
        color = MaterialTheme.colorScheme.background
    ) {
    Scaffold(
        modifier = Modifier.nestedScroll(scrollBehavior.nestedScrollConnection),
        topBar = {
            LargeTopAppBar(
                title = { 
                    Column {
                        Text(
                            text = androidx.compose.ui.res.stringResource(com.pixelperfect.fotty.R.string.home_hub_title), 
                            style = MaterialTheme.typography.headlineLarge
                        )
                        Text(
                            text = androidx.compose.ui.res.stringResource(com.pixelperfect.fotty.R.string.home_hub_subtitle),
                            style = MaterialTheme.typography.labelMedium,
                            color = MaterialTheme.colorScheme.onSurfaceVariant
                        )
                    }
                },
                scrollBehavior = scrollBehavior
            )
        }
    ) { padding ->
        Box(
            modifier = Modifier
                .fillMaxSize()
                .padding(padding)
        ) {
            when (val state = uiState) {
                is HomeUiState.Loading -> {
                    LoadingState()
                }
                is HomeUiState.Error -> {
                    ErrorState(message = state.message)
                }
                is HomeUiState.Success -> {
                    LazyColumn(
                        modifier = Modifier.fillMaxSize(),
                        contentPadding = PaddingValues(bottom = 120.dp)
                    ) {
                        item {
                            val hero = state.heroMatch
                            if (hero != null) {
                                HeroMatchCard(match = hero, onClick = { onMatchClick(hero) })
                            }
                        }

                        if (state.liveMatches.isNotEmpty()) {
                            item {
                                SectionHeader(
                                    title = "Live Pulse", 
                                    modifier = Modifier.padding(horizontal = 24.dp, vertical = 16.dp)
                                )
                                LazyRow(
                                    contentPadding = PaddingValues(horizontal = 16.dp),
                                    horizontalArrangement = Arrangement.spacedBy(12.dp)
                                ) {
                                    items(state.liveMatches, key = { it.id }) { liveMatch ->
                                        LiveMatchStripItem(match = liveMatch, onClick = { onMatchClick(liveMatch) })
                                    }
                                }
                                Spacer(modifier = Modifier.height(24.dp))
                            }
                        }

                        if (state.newsFeed.isNotEmpty()) {
                            item {
                                SectionHeader(
                                    title = "Intelligence Feed", 
                                    modifier = Modifier.padding(horizontal = 24.dp, vertical = 16.dp)
                                )
                            }
                            
                            items(state.newsFeed, key = { it.id }) { newsItem ->
                                NewsCard(newsItem = newsItem, onClick = { onNewsClick(newsItem) })
                            }
                        }
                    }
                }
                else -> {}
            }
        }
    }
    }
}

@Composable
private fun NewsCard(newsItem: NewsItem, onClick: () -> Unit) {
    Box(
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = 16.dp, vertical = 8.dp)
            .clip(MaterialTheme.shapes.extraLarge)
            .background(MaterialTheme.colorScheme.surfaceVariant.copy(alpha = 0.5f))
            .clickable { onClick() }
    ) {
        Column {
            if (newsItem.imageUrl != null) {
                AsyncImage(
                    model = newsItem.imageUrl,
                    contentDescription = null,
                    modifier = Modifier
                        .fillMaxWidth()
                        .height(180.dp)
                        .clip(MaterialTheme.shapes.extraLarge),
                    contentScale = androidx.compose.ui.layout.ContentScale.Crop
                )
            }
            
            Column(modifier = Modifier.padding(20.dp)) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Surface(
                        color = when(newsItem.category) {
                            "Tactical" -> Color.Cyan.copy(alpha = 0.2f)
                            "Statistical" -> MaterialTheme.colorScheme.primary.copy(alpha = 0.2f)
                            else -> MaterialTheme.colorScheme.secondary.copy(alpha = 0.2f)
                        },
                        shape = MaterialTheme.shapes.small,
                        modifier = Modifier.padding(bottom = 4.dp)
                    ) {
                        Text(
                            text = newsItem.category.uppercase(),
                            modifier = Modifier.padding(horizontal = 8.dp, vertical = 4.dp),
                            style = MaterialTheme.typography.labelSmall.copy(
                                fontWeight = FontWeight.Black,
                                letterSpacing = 1.sp
                            ),
                            color = when(newsItem.category) {
                                "Tactical" -> Color.Cyan
                                "Statistical" -> MaterialTheme.colorScheme.primary
                                else -> MaterialTheme.colorScheme.secondary
                            }
                        )
                    }
                    Spacer(modifier = Modifier.weight(1f))
                    Text(
                        text = newsItem.sourceName,
                        style = MaterialTheme.typography.labelSmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.6f)
                    )
                }
                
                Spacer(modifier = Modifier.height(8.dp))
                
                Text(
                    text = newsItem.title,
                    style = MaterialTheme.typography.titleMedium.copy(fontWeight = FontWeight.Bold),
                    color = MaterialTheme.colorScheme.onSurface
                )
                
                Spacer(modifier = Modifier.height(8.dp))
                
                Text(
                    text = newsItem.summary,
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    maxLines = 2,
                    overflow = androidx.compose.ui.text.style.TextOverflow.Ellipsis
                )
            }
        }
    }
}

@Composable
private fun LoadingState() {
    Column(
        modifier = Modifier.fillMaxSize().padding(24.dp),
        verticalArrangement = Arrangement.spacedBy(24.dp)
    ) {
        Box(modifier = Modifier.fillMaxWidth().height(280.dp).clip(MaterialTheme.shapes.extraLarge).shimmerEffect())
        Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
            repeat(2) { Box(modifier = Modifier.weight(1f).height(130.dp).clip(MaterialTheme.shapes.extraLarge).shimmerEffect()) }
        }
    }
}

@Composable
private fun ErrorState(message: String) {
    Box(modifier = Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
        Text(text = message, color = MaterialTheme.colorScheme.error, style = MaterialTheme.typography.bodyLarge)
    }
}

