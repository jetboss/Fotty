package com.pixelperfect.fotty.core.ui.components

import androidx.compose.foundation.layout.*
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.ChatBubble
import androidx.compose.material3.*
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import com.pixelperfect.fotty.core.network.models.nexus.NexusAEvent
import com.pixelperfect.fotty.ui.components.*

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun MaterialLiveCard(
    event: NexusAEvent,
    isLive: Boolean = false,
    homeScore: Int? = null,
    awayScore: Int? = null,
    matchStatus: String? = null,
    onChatClick: () -> Unit = {},
    onClick: () -> Unit = {}
) {
    ElevatedCard(
        onClick = onClick,
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = 16.dp, vertical = 8.dp),
        shape = MaterialTheme.shapes.extraLarge,
        colors = CardDefaults.elevatedCardColors(
            containerColor = MaterialTheme.colorScheme.surface,
            contentColor = MaterialTheme.colorScheme.onSurface
        )
    ) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .padding(16.dp)
        ) {
            // Header Row
            Row(
                modifier = Modifier.fillMaxWidth(),
                verticalAlignment = Alignment.CenterVertically
            ) {
                LeagueBadge(name = event.category ?: "EVENT")
                
                if (isLive) {
                    Spacer(modifier = Modifier.width(8.dp))
                    LivePulse()
                }
                
                Spacer(modifier = Modifier.weight(1f))
                
                IconButton(onClick = onChatClick, modifier = Modifier.size(32.dp)) {
                    Icon(
                        imageVector = Icons.Default.ChatBubble,
                        contentDescription = "Arena",
                        tint = MaterialTheme.colorScheme.primary,
                        modifier = Modifier.size(18.dp)
                    )
                }
            }

            Spacer(modifier = Modifier.height(16.dp))

            // Teams & Scores
            Row(
                modifier = Modifier.fillMaxWidth(),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.SpaceBetween
            ) {
                // Home Team
                TeamSection(
                    name = event.teams?.home?.name ?: "Home",
                    badgeUrl = event.teams?.home?.badge,
                    modifier = Modifier.weight(1f),
                    alignment = Alignment.Start
                )

                // Score
                Column(
                    horizontalAlignment = Alignment.CenterHorizontally,
                    modifier = Modifier.padding(horizontal = 16.dp)
                ) {
                    if (homeScore != null && awayScore != null) {
                        Text(
                            text = "$homeScore - $awayScore",
                            style = MaterialTheme.typography.headlineMedium.copy(
                                fontWeight = FontWeight.ExtraBold,
                                color = MaterialTheme.colorScheme.primary
                            )
                        )
                    } else {
                        Text(
                            text = "VS",
                            style = MaterialTheme.typography.titleMedium.copy(
                                fontWeight = FontWeight.Bold,
                                color = MaterialTheme.colorScheme.outline
                            )
                        )
                    }
                    if (matchStatus != null) {
                        Text(
                            text = matchStatus,
                            style = MaterialTheme.typography.labelMedium,
                            color = MaterialTheme.colorScheme.secondary
                        )
                    }
                }

                // Away Team
                TeamSection(
                    name = event.teams?.away?.name ?: "Away",
                    badgeUrl = event.teams?.away?.badge,
                    modifier = Modifier.weight(1f),
                    alignment = Alignment.End
                )
            }
        }
    }
}

@Composable
private fun TeamSection(
    name: String,
    badgeUrl: String?,
    modifier: Modifier = Modifier,
    alignment: Alignment.Horizontal
) {
    Column(
        modifier = modifier,
        horizontalAlignment = alignment,
        verticalArrangement = Arrangement.spacedBy(8.dp)
    ) {
        TeamBadge(
            crestUrl = badgeUrl,
            name = name,
            size = 48.dp
        )
        Text(
            text = name,
            style = MaterialTheme.typography.bodyMedium.copy(fontWeight = FontWeight.Bold),
            maxLines = 1,
            overflow = TextOverflow.Ellipsis,
            textAlign = if (alignment == Alignment.Start) TextAlign.Start else TextAlign.End
        )
    }
}
