package com.pixelperfect.fotty.features.player.ui

import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.Search
import androidx.compose.material3.*
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.pixelperfect.fotty.core.network.models.streaming.StreamSource
import com.pixelperfect.fotty.core.theme.Accent
import java.util.Locale
import androidx.compose.ui.graphics.Brush
import androidx.compose.runtime.remember
import kotlinx.coroutines.launch

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun SourceSelectorSheet(
    sources: List<StreamSource>,
    currentSourceIndex: Int,
    onSelectSource: (Int) -> Unit,
    onDismiss: () -> Unit,
    onBrowseCatalog: () -> Unit = {}
) {
    ModalBottomSheet(
        onDismissRequest = onDismiss,
        containerColor = Color.Transparent, // Enable Glassmorphism
        contentColor = Color.White,
        tonalElevation = 0.dp,
        shape = RoundedCornerShape(topStart = 32.dp, topEnd = 32.dp),
        dragHandle = {
            Column(modifier = Modifier.fillMaxWidth(), horizontalAlignment = Alignment.CenterHorizontally) {
                Box(
                    modifier = Modifier
                        .padding(vertical = 12.dp)
                        .size(width = 40.dp, height = 4.dp)
                        .background(Color.White.copy(alpha = 0.1f), CircleShape)
                )
            }
        }
    ) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .background(
                    Brush.verticalGradient(
                        listOf(Color(0xFF0B0E14).copy(alpha = 0.95f), Color(0xFF0B0E14))
                    )
                )
                .padding(horizontal = 24.dp)
                .padding(bottom = 32.dp)
        ) {
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically
            ) {
                Text(
                    text = "Live Now".uppercase(),
                    style = MaterialTheme.typography.labelLarge.copy(
                        fontWeight = FontWeight.Black,
                        letterSpacing = 1.sp
                    ),
                    color = Accent
                )
                Surface(
                    color = Accent.copy(alpha = 0.1f),
                    shape = CircleShape,
                    border = BorderStroke(1.dp, Accent.copy(alpha = 0.2f))
                ) {
                    Text(
                        text = "${sources.size} NODES ACTIVE",
                        modifier = Modifier.padding(horizontal = 12.dp, vertical = 4.dp),
                        style = MaterialTheme.typography.labelSmall.copy(fontWeight = FontWeight.Bold),
                        color = Accent
                    )
                }
            }
            
            Spacer(modifier = Modifier.height(20.dp))

            // Browse Catalog Entry (Moved to top for constant visibility)
            Surface(
                onClick = onBrowseCatalog,
                color = Accent.copy(alpha = 0.05f),
                shape = RoundedCornerShape(16.dp),
                border = BorderStroke(1.dp, Accent.copy(alpha = 0.3f)),
                modifier = Modifier.fillMaxWidth()
            ) {
                Row(
                    modifier = Modifier.padding(16.dp),
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.Center
                ) {
                    Icon(Icons.Default.Search, contentDescription = null, tint = Accent, modifier = Modifier.size(18.dp))
                    Spacer(modifier = Modifier.width(12.dp))
                    Text(
                        text = "BROWSE CHANNEL CATALOG",
                        style = MaterialTheme.typography.labelLarge.copy(
                            fontWeight = FontWeight.Black,
                            letterSpacing = 1.sp
                        ),
                        color = Accent
                    )
                }
            }

            Spacer(modifier = Modifier.height(16.dp))
            
            androidx.compose.foundation.lazy.LazyColumn(
                modifier = Modifier.fillMaxWidth(),
                verticalArrangement = Arrangement.spacedBy(8.dp)
            ) {
                items(sources.size) { index ->
                    val source = sources[index]
                    val isSelected = index == currentSourceIndex
                    
                    // PRO HAPTIC: Vibrate on selection
                    val context = androidx.compose.ui.platform.LocalContext.current
                    val scope = androidx.compose.runtime.rememberCoroutineScope()
                    val hapticManager = remember {
                        dagger.hilt.android.EntryPointAccessors.fromApplication(
                            context.applicationContext,
                            com.pixelperfect.fotty.core.di.HapticEntryPoint::class.java
                        ).hapticManager()
                    }

                    Surface(
                        onClick = { 
                            scope.launch { hapticManager.vibrateLight() }
                            onSelectSource(index) 
                        },
                        color = if (isSelected) Accent.copy(alpha = 0.15f) else Color(0xFF1E2128),
                        shape = RoundedCornerShape(16.dp),
                        border = BorderStroke(
                            width = 1.dp,
                            color = if (isSelected) Accent else Color.White.copy(alpha = 0.05f)
                        ),
                        modifier = Modifier.fillMaxWidth()
                    ) {
                        Row(
                            modifier = Modifier.padding(16.dp),
                            verticalAlignment = Alignment.CenterVertically
                        ) {
                            // Health Dot
                            val healthColor = when {
                                source.healthScore >= 80 -> Color(0xFF4CAF50)
                                source.healthScore >= 50 -> Color(0xFFFFC107)
                                else -> Color(0xFFF44336)
                            }
                            Box(modifier = Modifier.size(8.dp).background(healthColor, CircleShape))
                            
                            Spacer(modifier = Modifier.width(16.dp))
                            
                            Column(modifier = Modifier.weight(1f)) {
                                Text(
                                    text = source.label.uppercase(),
                                    style = MaterialTheme.typography.bodyLarge.copy(
                                        fontWeight = FontWeight.Black,
                                        letterSpacing = 0.5.sp
                                    ),
                                    color = Color.White
                                )
                                Row(verticalAlignment = Alignment.CenterVertically) {
                                    Text(
                                        text = (source.provider ?: "GLOBAL NODE").uppercase(),
                                        style = MaterialTheme.typography.labelSmall.copy(fontWeight = FontWeight.Bold),
                                        color = if (isSelected) Accent else Color.Gray
                                    )
                                    if (source.activePeers > 0) {
                                        Spacer(modifier = Modifier.width(8.dp))
                                        Text(
                                            text = "• ${source.activePeers} PEERS",
                                            style = MaterialTheme.typography.labelSmall.copy(fontWeight = FontWeight.Bold),
                                            color = Color(0xFF4CAF50)
                                        )
                                    }
                                }
                            }
                            
                            if (isSelected) {
                                Icon(
                                    Icons.Default.Check,
                                    contentDescription = null,
                                    tint = Accent,
                                    modifier = Modifier.size(20.dp)
                                )
                            } else {
                                Surface(
                                    color = Color.White.copy(alpha = 0.05f),
                                    shape = RoundedCornerShape(4.dp)
                                ) {
                                    Text(
                                        text = source.qualityLabel.uppercase(),
                                        modifier = Modifier.padding(horizontal = 6.dp, vertical = 2.dp),
                                        style = MaterialTheme.typography.labelSmall.copy(fontWeight = FontWeight.Bold),
                                        color = Color.Gray
                                    )
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun SyncSettingsBottomSheet(
    exoPlayer: androidx.media3.exoplayer.ExoPlayer?,
    onDismiss: () -> Unit
) {
    var offset by androidx.compose.runtime.remember { androidx.compose.runtime.mutableStateOf(0f) }
    var speed by androidx.compose.runtime.remember { androidx.compose.runtime.mutableStateOf(exoPlayer?.playbackParameters?.speed ?: 1.0f) }

    ModalBottomSheet(
        onDismissRequest = onDismiss,
        containerColor = Color.Black,
        contentColor = Color.White,
        shape = RoundedCornerShape(0.dp),
        dragHandle = null
    ) {
        Column(modifier = Modifier.padding(24.dp).padding(bottom = 32.dp)) {
            Text(
                androidx.compose.ui.res.stringResource(com.pixelperfect.fotty.R.string.player_data_sync_title).uppercase(),
                style = MaterialTheme.typography.titleLarge,
                color = com.pixelperfect.fotty.core.theme.SolarOrange,
                fontWeight = FontWeight.Black,
                fontFamily = androidx.compose.ui.text.font.FontFamily.Monospace,
                modifier = Modifier.padding(bottom = 8.dp)
            )
            Text(
                androidx.compose.ui.res.stringResource(com.pixelperfect.fotty.R.string.player_data_sync_description).uppercase(),
                fontSize = 9.sp,
                color = Color.Gray,
                fontFamily = androidx.compose.ui.text.font.FontFamily.Monospace,
                modifier = Modifier.padding(bottom = 24.dp)
            )

            // Offset Slider
            Text("LAG OFFSET: ${offset.toInt()}S", color = Color.White, fontSize = 12.sp, fontWeight = FontWeight.Black, fontFamily = androidx.compose.ui.text.font.FontFamily.Monospace)
            Slider(
                value = offset,
                onValueChange = { offset = it },
                valueRange = 0f..30f,
                steps = 30,
                colors = SliderDefaults.colors(thumbColor = com.pixelperfect.fotty.core.theme.SolarOrange, activeTrackColor = com.pixelperfect.fotty.core.theme.SolarOrange)
            )
            Surface(
                onClick = { 
                    exoPlayer?.let {
                        val current = it.currentPosition
                        it.seekTo((current - (offset * 1000).toLong()).coerceAtLeast(0))
                    }
                },
                modifier = Modifier.fillMaxWidth().height(44.dp),
                color = Color.White.copy(alpha = 0.05f),
                shape = RoundedCornerShape(0.dp),
                border = BorderStroke(1.dp, Color.White.copy(alpha = 0.1f))
            ) {
                Box(contentAlignment = Alignment.Center) {
                    Text(
                        androidx.compose.ui.res.stringResource(com.pixelperfect.fotty.R.string.player_apply_sync).uppercase(), 
                        fontSize = 10.sp, 
                        fontWeight = FontWeight.Black,
                        fontFamily = androidx.compose.ui.text.font.FontFamily.Monospace,
                        color = Color.White
                    )
                }
            }

            Spacer(modifier = Modifier.height(32.dp))

            // Playback Speed
            Text("CATCH-UP SPEED: ${"%.2f".format(speed)}X", color = Color.White, fontSize = 12.sp, fontWeight = FontWeight.Black, fontFamily = androidx.compose.ui.text.font.FontFamily.Monospace)
            Slider(
                value = speed,
                onValueChange = { 
                    speed = it
                    exoPlayer?.setPlaybackSpeed(it)
                },
                valueRange = 1.0f..2.0f,
                steps = 10,
                colors = SliderDefaults.colors(thumbColor = com.pixelperfect.fotty.core.theme.SolarOrange, activeTrackColor = com.pixelperfect.fotty.core.theme.SolarOrange)
            )
        }
    }
}

@Composable
fun DiagRow(label: String, value: String, color: Color = Color.White) {
    Row(
        modifier = Modifier.fillMaxWidth().padding(vertical = 1.dp),
        horizontalArrangement = Arrangement.SpaceBetween
    ) {
        Text(label, color = Color.Gray, fontSize = 8.sp, fontWeight = FontWeight.Bold)
        Text(value, color = color, fontSize = 8.sp, fontFamily = androidx.compose.ui.text.font.FontFamily.Monospace, maxLines = 1, overflow = androidx.compose.ui.text.style.TextOverflow.Ellipsis)
    }
}

fun isDirectMediaUrl(url: String): Boolean {
    val lower = url.lowercase(Locale.US)
    return isLikelyLiveStreamUrl(url)
        || lower.contains(".mp4")
        || lower.contains("/proxy/acestream")
        || lower.contains("/ace/getstream")
}

fun isP2PStreamUrl(url: String): Boolean {
    val lower = url.lowercase(Locale.US)
    return lower.contains("p2p.pixel-invoice.com")
        || lower.contains("/proxy/acestream")
        || lower.contains("/ace/getstream")
}

fun classifyFailureClass(reason: String): String {
    val lower = reason.lowercase(Locale.US)
    return when {
        "524" in lower -> "524"
        "timeout" in lower || "timed out" in lower -> "timeout"
        "segment" in lower && "500" in lower -> "segment 500"
        "manifest" in lower && "500" in lower -> "manifest 500"
        "500" in lower -> "500"
        "proxy" in lower -> "proxy"
        else -> "unknown"
    }
}

fun isLikelyLiveStreamUrl(url: String): Boolean {
    val lower = url.lowercase(Locale.US)
    return lower.contains(".m3u8")
        || lower.contains(".m3u")
        || lower.contains(".mpd")
        || lower.contains(".m4s")
        || lower.contains(".ts?")
        || lower.contains(".ts&")
        || lower.endsWith(".ts")
        || lower.contains("chunklist")
        || lower.contains("master.m3u8")
        || lower.contains("playlist.m3u8")
        || lower.contains("index.m3u8")
}
