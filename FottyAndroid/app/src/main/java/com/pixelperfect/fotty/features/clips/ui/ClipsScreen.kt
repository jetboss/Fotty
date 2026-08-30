package com.pixelperfect.fotty.features.clips.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.PlayArrow
import androidx.compose.material3.*
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import coil.compose.AsyncImage
import com.pixelperfect.fotty.core.theme.*
import com.pixelperfect.fotty.ui.components.*

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ClipsScreen() {
    val clips = listOf(
        ClipItem("1", "CHAMPIONS LEAGUE: TOP 10 GOALS", "3:42", "UEFA", null),
        ClipItem("2", "TACTICAL BREAKDOWN: LIVERPOOL VS REAL MADRID", "12:15", "SKY SPORTS", null),
        ClipItem("3", "EVERY ANGLE: HAALAND'S RECORD BREAKER", "5:20", "PREMIER LEAGUE", null),
        ClipItem("4", "ALL ACCESS: THE ROAD TO ISTANBUL", "45:00", "FOTTY ORIGINALS", null)
    )

    Scaffold(
        containerColor = MaterialTheme.colorScheme.background,
        topBar = {
            LargeTopAppBar(
                title = { 
                    Column {
                        Text(
                            "CLIPS", 
                            style = MaterialTheme.typography.displaySmall.copy(
                                fontWeight = FontWeight.Black,
                                letterSpacing = 2.sp,
                                color = MaterialTheme.colorScheme.primary
                            )
                        )
                        Text(
                            "PREMIUM MATCH HIGHLIGHTS",
                            style = MaterialTheme.typography.labelSmall.copy(
                                color = MaterialTheme.colorScheme.onSurfaceVariant,
                                letterSpacing = 1.sp
                            )
                        )
                    }
                },
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
            item {
                SectionHeader(
                    title = "FEATURED ORIGINALS", 
                    modifier = Modifier.padding(horizontal = 24.dp, vertical = 16.dp)
                )
            }
            
            items(clips) { clip ->
                ClipCard(clip = clip)
            }
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun ClipCard(clip: ClipItem) {
    Surface(
        onClick = { /* Play video */ },
        modifier = Modifier
            .padding(horizontal = 16.dp, vertical = 12.dp)
            .fillMaxWidth()
            .height(240.dp),
        shape = MaterialTheme.shapes.extraLarge,
        color = MaterialTheme.colorScheme.surface,
        tonalElevation = 4.dp
    ) {
        Box(modifier = Modifier.fillMaxSize()) {
            // Thumbnail Placeholder with Gradient
            Box(
                modifier = Modifier
                    .fillMaxSize()
                    .background(
                        Brush.verticalGradient(
                            colors = listOf(
                                Color.Transparent,
                                Color.Black.copy(alpha = 0.8f)
                            )
                        )
                    )
            )
            
            // Play Icon
            Surface(
                modifier = Modifier.align(Alignment.Center),
                shape = androidx.compose.foundation.shape.CircleShape,
                color = MaterialTheme.colorScheme.primary,
                tonalElevation = 8.dp
            ) {
                Icon(
                    Icons.Default.PlayArrow,
                    contentDescription = "Play",
                    modifier = Modifier.padding(16.dp).size(32.dp),
                    tint = Color.Black
                )
            }
            
            // Info Overlay
            Column(
                modifier = Modifier
                    .align(Alignment.BottomStart)
                    .padding(24.dp)
            ) {
                Surface(
                    color = MaterialTheme.colorScheme.primary,
                    shape = MaterialTheme.shapes.extraSmall
                ) {
                    Text(
                        text = clip.duration,
                        modifier = Modifier.padding(horizontal = 6.dp, vertical = 2.dp),
                        style = MaterialTheme.typography.labelSmall.copy(fontWeight = FontWeight.Black, color = Color.Black)
                    )
                }
                Spacer(modifier = Modifier.height(8.dp))
                Text(
                    text = clip.title,
                    style = MaterialTheme.typography.titleLarge.copy(fontWeight = FontWeight.Black, color = Color.White),
                    maxLines = 2
                )
                Text(
                    text = clip.provider.uppercase(),
                    style = MaterialTheme.typography.labelSmall.copy(color = MaterialTheme.colorScheme.primary, letterSpacing = 1.sp)
                )
            }
        }
    }
}

data class ClipItem(
    val id: String,
    val title: String,
    val duration: String,
    val provider: String,
    val thumbnailUrl: String?
)
