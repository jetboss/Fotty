package com.pixelperfect.fotty.core.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.material3.*
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import coil.compose.AsyncImage
import com.pixelperfect.fotty.core.theme.*
import com.pixelperfect.fotty.data.models.Match
import com.pixelperfect.fotty.data.models.MatchStatus
import com.pixelperfect.fotty.ui.components.*

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun HeroMatchCard(
    match: Match,
    onClick: () -> Unit
) {
    Surface(
        onClick = onClick,
        modifier = Modifier
            .fillMaxWidth()
            .height(300.dp)
            .padding(horizontal = 16.dp),
        shape = MaterialTheme.shapes.extraLarge,
        color = MaterialTheme.colorScheme.surface,
        tonalElevation = 8.dp // High tonal elevation for deep separation
    ) {
        Box(modifier = Modifier.fillMaxSize()) {
            // Immersive Backdrop (Simulated if no URL)
            StadiumBackdrop(category = match.category ?: "football")

            // Content
            Column(
                modifier = Modifier
                    .fillMaxSize()
                    .padding(24.dp),
                horizontalAlignment = Alignment.CenterHorizontally,
                verticalArrangement = Arrangement.Center
            ) {
                // League Badge (Floating)
                LeagueBadge(
                    name = match.league.name,
                    modifier = Modifier.align(Alignment.Start)
                )
                
                Spacer(modifier = Modifier.weight(1f))

                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.SpaceAround,
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    // Home Team
                    TeamSectionHero(
                        name = match.homeTeam.name,
                        logoUrl = match.homeTeam.logoUrl,
                        teamId = match.homeTeam.id,
                        modifier = Modifier.weight(1f)
                    )

                    // Score Hub
                    Column(
                        horizontalAlignment = Alignment.CenterHorizontally,
                        modifier = Modifier.padding(horizontal = 16.dp)
                    ) {
                        if (match.status == MatchStatus.LIVE) {
                            if (match.category == "cricket") {
                                Text(
                                    text = match.statusText ?: "LIVE",
                                    style = MaterialTheme.typography.displayMedium.copy(
                                        fontWeight = FontWeight.ExtraBold,
                                        color = MaterialTheme.colorScheme.primary,
                                        letterSpacing = (-1).sp
                                    )
                                )
                            } else {
                                Text(
                                    text = "LIVE",
                                    style = MaterialTheme.typography.displayLarge.copy(
                                        fontWeight = FontWeight.ExtraBold,
                                        color = MaterialTheme.colorScheme.primary,
                                        letterSpacing = (-2).sp
                                    )
                                )
                            }
                            Spacer(modifier = Modifier.height(4.dp))
                            Row(verticalAlignment = Alignment.CenterVertically) {
                                LivePulse()
                                if (match.category != "cricket" && match.minute != null) {
                                    Text(
                                        text = " • ${match.minute}'",
                                        style = MaterialTheme.typography.labelLarge,
                                        fontWeight = FontWeight.Black,
                                        color = MaterialTheme.colorScheme.primary
                                    )
                                }
                            }
                        } else {
                            Column(horizontalAlignment = Alignment.CenterHorizontally) {
                                Text(
                                    text = com.pixelperfect.fotty.core.util.DateUtils.formatTime(match.timestamp),
                                    style = MaterialTheme.typography.displayMedium.copy(
                                        fontWeight = FontWeight.Black,
                                        color = MaterialTheme.colorScheme.onSurface
                                    )
                                )
                                Text(
                                    text = "KICK OFF",
                                    style = MaterialTheme.typography.labelSmall,
                                    color = MaterialTheme.colorScheme.primary
                                )
                            }
                        }
                    }

                    // Away Team
                    TeamSectionHero(
                        name = match.awayTeam.name,
                        logoUrl = match.awayTeam.logoUrl,
                        teamId = match.awayTeam.id,
                        modifier = Modifier.weight(1f)
                    )
                }
                
                Spacer(modifier = Modifier.weight(1f))
                
                // Live Metadata
                if (match.status == MatchStatus.LIVE && match.minute != null) {
                    Text(
                        text = "${match.minute}'",
                        style = MaterialTheme.typography.titleMedium,
                        fontWeight = FontWeight.Bold,
                        color = MaterialTheme.colorScheme.primary
                    )
                }
            }
        }
    }
}

@Composable
private fun TeamSectionHero(name: String, logoUrl: String?, teamId: String?, modifier: Modifier = Modifier) {
    Column(
        horizontalAlignment = Alignment.CenterHorizontally,
        modifier = modifier
    ) {
        TeamBadge(crestUrl = logoUrl, name = name, teamId = teamId, size = 72.dp)
        Spacer(modifier = Modifier.height(12.dp))
        Text(
            text = name.uppercase(),
            style = MaterialTheme.typography.labelSmall.copy(
                fontWeight = FontWeight.Black,
                letterSpacing = 1.sp,
                color = MaterialTheme.colorScheme.onSurfaceVariant
            ),
            textAlign = androidx.compose.ui.text.style.TextAlign.Center,
            maxLines = 2,
            lineHeight = 12.sp
        )
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun LiveMatchStripItem(
    match: Match,
    onClick: () -> Unit
) {
    ElevatedCard(
        onClick = onClick,
        modifier = Modifier
            .width(280.dp)
            .height(130.dp),
        shape = MaterialTheme.shapes.extraLarge,
        colors = CardDefaults.elevatedCardColors(
            containerColor = MaterialTheme.colorScheme.surfaceVariant.copy(alpha = 0.5f)
        )
    ) {
        Row(
            modifier = Modifier.fillMaxSize().padding(16.dp),
            verticalAlignment = Alignment.CenterVertically
        ) {
            Column(modifier = Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(12.dp)) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    TeamBadge(crestUrl = match.homeTeam.logoUrl, name = match.homeTeam.name, teamId = match.homeTeam.id, size = 32.dp)
                    Spacer(modifier = Modifier.width(10.dp))
                    Text(
                        text = match.homeTeam.name,
                        style = MaterialTheme.typography.bodyMedium.copy(fontWeight = FontWeight.Bold),
                        maxLines = 1,
                        modifier = Modifier.weight(1f)
                    )
                }
                Row(verticalAlignment = Alignment.CenterVertically) {
                    TeamBadge(crestUrl = match.awayTeam.logoUrl, name = match.awayTeam.name, teamId = match.awayTeam.id, size = 32.dp)
                    Spacer(modifier = Modifier.width(10.dp))
                    Text(
                        text = match.awayTeam.name,
                        style = MaterialTheme.typography.bodyMedium.copy(fontWeight = FontWeight.Bold),
                        maxLines = 1,
                        modifier = Modifier.weight(1f)
                    )
                }
            }
            
            VerticalDivider(
                modifier = Modifier.fillMaxHeight().padding(horizontal = 16.dp),
                color = MaterialTheme.colorScheme.outlineVariant
            )

            Column(horizontalAlignment = Alignment.CenterHorizontally) {
                if (match.status == MatchStatus.LIVE) {
                    LivePulse()
                    if (match.minute != null) {
                        Text(
                            text = "${match.minute}'",
                            style = MaterialTheme.typography.labelSmall,
                            fontWeight = FontWeight.Black,
                            color = MaterialTheme.colorScheme.primary,
                            modifier = Modifier.padding(top = 6.dp)
                        )
                    }
                } else {
                    Text(
                        text = "SOON",
                        style = MaterialTheme.typography.labelSmall,
                        fontWeight = FontWeight.Black,
                        color = MaterialTheme.colorScheme.outline
                    )
                }
            }
        }
    }
}
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun UpcomingMatchItem(
    match: Match,
    onClick: () -> Unit
) {
    Surface(
        onClick = onClick,
        modifier = Modifier
            .padding(horizontal = 16.dp, vertical = 6.dp)
            .fillMaxWidth(),
        shape = MaterialTheme.shapes.extraLarge,
        color = MaterialTheme.colorScheme.surface,
        tonalElevation = 2.dp
    ) {
        Row(
            modifier = Modifier.padding(20.dp),
            verticalAlignment = Alignment.CenterVertically
        ) {
            TeamBadge(crestUrl = match.homeTeam.logoUrl, name = match.homeTeam.name, size = 36.dp)
            Spacer(modifier = Modifier.width(16.dp))
            Text(
                text = match.homeTeam.name,
                style = MaterialTheme.typography.bodyLarge.copy(fontWeight = FontWeight.Bold),
                modifier = Modifier.weight(1f),
                maxLines = 1,
                overflow = androidx.compose.ui.text.style.TextOverflow.Ellipsis
            )
            
            Column(
                modifier = Modifier.padding(horizontal = 12.dp),
                horizontalAlignment = Alignment.CenterHorizontally
            ) {
                Text(
                    text = com.pixelperfect.fotty.core.util.DateUtils.formatTime(match.timestamp),
                    style = MaterialTheme.typography.titleMedium.copy(fontWeight = FontWeight.Black),
                    color = MaterialTheme.colorScheme.primary
                )
                Text(
                    text = com.pixelperfect.fotty.core.util.DateUtils.formatDate(match.timestamp).uppercase(),
                    style = MaterialTheme.typography.labelSmall.copy(fontSize = 8.sp),
                    color = MaterialTheme.colorScheme.outline
                )
            }

            Text(
                text = match.awayTeam.name,
                style = MaterialTheme.typography.bodyLarge.copy(fontWeight = FontWeight.Bold),
                modifier = Modifier.weight(1f),
                textAlign = androidx.compose.ui.text.style.TextAlign.End,
                maxLines = 1,
                overflow = androidx.compose.ui.text.style.TextOverflow.Ellipsis
            )
            Spacer(modifier = Modifier.width(16.dp))
            TeamBadge(crestUrl = match.awayTeam.logoUrl, name = match.awayTeam.name, size = 36.dp)
        }
    }
}
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun LiveMatchLargeCard(
    match: Match,
    onClick: () -> Unit
) {
    Surface(
        onClick = onClick,
        modifier = Modifier
            .padding(horizontal = 16.dp, vertical = 8.dp)
            .fillMaxWidth(),
        shape = MaterialTheme.shapes.extraLarge,
        color = MaterialTheme.colorScheme.surface,
        tonalElevation = 4.dp
    ) {
        Column(modifier = Modifier.padding(24.dp)) {
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically
            ) {
                LeagueBadge(name = match.league.name)
                if (match.status == MatchStatus.LIVE) {
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        LivePulse()
                        if (match.minute != null) {
                            Spacer(modifier = Modifier.width(8.dp))
                            Text(
                                text = "${match.minute}'",
                                style = MaterialTheme.typography.labelLarge.copy(fontWeight = FontWeight.Black),
                                color = MaterialTheme.colorScheme.primary
                            )
                        }
                    }
                } else {
                    Text(
                        text = com.pixelperfect.fotty.core.util.DateUtils.formatTime(match.timestamp),
                        style = MaterialTheme.typography.labelLarge.copy(fontWeight = FontWeight.Black),
                        color = MaterialTheme.colorScheme.onSurfaceVariant
                    )
                }
            }
            
            Spacer(modifier = Modifier.height(24.dp))
            
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically
            ) {
                // Home
                Column(
                    horizontalAlignment = Alignment.CenterHorizontally,
                    modifier = Modifier.weight(1f)
                ) {
                    TeamBadge(crestUrl = match.homeTeam.logoUrl, name = match.homeTeam.name, size = 56.dp)
                    Spacer(modifier = Modifier.height(12.dp))
                    Text(
                        text = match.homeTeam.name,
                        style = MaterialTheme.typography.titleSmall.copy(fontWeight = FontWeight.Bold),
                        textAlign = androidx.compose.ui.text.style.TextAlign.Center,
                        maxLines = 1
                    )
                }
                
                // Score
                Column(
                    horizontalAlignment = Alignment.CenterHorizontally,
                    modifier = Modifier.padding(horizontal = 24.dp)
                ) {
                    Text(
                        text = when {
                            match.status == MatchStatus.FINISHED -> {
                                if (match.category == "cricket") match.statusText ?: "FT"
                                else "${match.homeScore ?: 0} - ${match.awayScore ?: 0}"
                            }
                            match.status == MatchStatus.LIVE -> "LIVE"
                            else -> "VS"
                        },
                        style = if (match.category == "cricket") MaterialTheme.typography.titleLarge.copy(fontWeight = FontWeight.Black) 
                                else MaterialTheme.typography.displaySmall.copy(fontWeight = FontWeight.Black, letterSpacing = (-1).sp),
                        color = if (match.status == MatchStatus.LIVE) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.onSurface,
                        textAlign = androidx.compose.ui.text.style.TextAlign.Center
                    )
                }
                
                // Away
                Column(
                    horizontalAlignment = Alignment.CenterHorizontally,
                    modifier = Modifier.weight(1f)
                ) {
                    TeamBadge(crestUrl = match.awayTeam.logoUrl, name = match.awayTeam.name, size = 56.dp)
                    Spacer(modifier = Modifier.height(12.dp))
                    Text(
                        text = match.awayTeam.name,
                        style = MaterialTheme.typography.titleSmall.copy(fontWeight = FontWeight.Bold),
                        textAlign = androidx.compose.ui.text.style.TextAlign.Center,
                        maxLines = 1
                    )
                }
            }
        }
    }
}

@Composable
fun StadiumBackdrop(category: String, modifier: Modifier = Modifier) {
    val themeColor = when (category.lowercase()) {
        "football", "soccer" -> Color(0xFF1B5E20) // Deep Grass Green
        "basketball" -> Color(0xFFE65100) // Hardwood Orange
        "cricket" -> Color(0xFF2E7D32) // Pitch Green
        "tennis" -> Color(0xFF33691E) // Court Green
        "fight", "ufc", "boxing" -> Color(0xFF212121) // Octagon Gray
        else -> MaterialTheme.colorScheme.primaryContainer
    }

    Box(
        modifier = modifier
            .fillMaxSize()
            .background(
                Brush.verticalGradient(
                    colors = listOf(
                        themeColor.copy(alpha = 0.4f),
                        Color.Transparent,
                        MaterialTheme.colorScheme.surface
                    )
                )
            )
    )
}
