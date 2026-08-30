package com.pixelperfect.fotty.features.player.ui

import androidx.compose.animation.*
import androidx.compose.foundation.background
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.gestures.detectVerticalDragGestures
import kotlinx.coroutines.launch
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.pixelperfect.fotty.core.network.models.streaming.StreamSource
import com.pixelperfect.fotty.core.theme.Accent
import kotlinx.coroutines.delay
import kotlin.math.roundToInt

@Composable
fun AresPlayerControls(
    isVisible: Boolean,
    isPlaying: Boolean,
    isPipMode: Boolean,
    title: String,
    subtitle: String,
    currentPosition: Long,
    duration: Long,
    bufferedPosition: Long,
    onPlayPause: () -> Unit,
    onSeek: (Long) -> Unit,
    onToggleFullscreen: () -> Unit,
    onSettingsClick: () -> Unit,
    onInsightsClick: () -> Unit,
    onBack: () -> Unit,
    statusLabel: String? = null,
    modifier: Modifier = Modifier
) {
    if (isPipMode) return // No controls in PiP mode

    AnimatedVisibility(
        visible = isVisible,
        enter = fadeIn() + slideInVertically { it / 4 },
        exit = fadeOut() + slideOutVertically { it / 4 },
        modifier = modifier.fillMaxSize()
    ) {
        Box(
            modifier = Modifier
                .fillMaxSize()
                .background(
                    Brush.verticalGradient(
                        colors = listOf(
                            Color.Black.copy(alpha = 0.6f),
                            Color.Transparent,
                            Color.Black.copy(alpha = 0.6f)
                        )
                    )
                )
        ) {
            // Top Bar
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .statusBarsPadding()
                    .padding(16.dp),
                verticalAlignment = Alignment.CenterVertically
            ) {
                IconButton(onClick = onBack) {
                    Icon(Icons.Default.ArrowBack, contentDescription = "Back", tint = Color.White)
                }
                Column(modifier = Modifier.weight(1f).padding(horizontal = 8.dp)) {
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Text(
                            text = title,
                            style = MaterialTheme.typography.titleMedium.copy(fontWeight = FontWeight.Bold),
                            color = Color.White,
                            maxLines = 1,
                            modifier = Modifier.weight(1f, fill = false)
                        )
                        if (!statusLabel.isNullOrBlank()) {
                            Spacer(modifier = Modifier.width(8.dp))
                            Surface(
                                color = Color(0xFFF44336), // Broadcast Red
                                shape = RoundedCornerShape(4.dp)
                            ) {
                                Text(
                                    text = statusLabel.uppercase(),
                                    modifier = Modifier.padding(horizontal = 6.dp, vertical = 2.dp),
                                    style = MaterialTheme.typography.labelSmall.copy(
                                        fontWeight = FontWeight.Black,
                                        fontSize = 8.sp,
                                        letterSpacing = 1.sp
                                    ),
                                    color = Color.White
                                )
                            }
                        }
                    }
                    Text(
                        text = subtitle,
                        style = MaterialTheme.typography.bodySmall,
                        color = Color.White.copy(alpha = 0.7f),
                        maxLines = 1
                    )
                }
                IconButton(onClick = onInsightsClick) {
                    Icon(Icons.Default.AutoGraph, contentDescription = "Insights", tint = Color.White)
                }
                IconButton(onClick = onSettingsClick) {
                    Icon(Icons.Default.Settings, contentDescription = "Settings", tint = Color.White)
                }
            }

            // Center Play/Pause
            IconButton(
                onClick = onPlayPause,
                modifier = Modifier
                    .align(Alignment.Center)
                    .size(84.dp)
                    .clip(CircleShape)
                    .background(Color.White.copy(alpha = 0.1f))
            ) {
                Icon(
                    imageVector = if (isPlaying) Icons.Default.Pause else Icons.Default.PlayArrow,
                    contentDescription = "Play/Pause",
                    modifier = Modifier.size(48.dp),
                    tint = Color.White
                )
            }

            // Bottom Controls
            Column(
                modifier = Modifier
                    .align(Alignment.BottomCenter)
                    .navigationBarsPadding()
                    .padding(horizontal = 16.dp, vertical = 8.dp)
            ) {
                // Seek Bar
                Box(modifier = Modifier.fillMaxWidth().height(48.dp), contentAlignment = Alignment.Center) {
                    // Buffered Progress (Behind)
                    if (duration > 0) {
                        LinearProgressIndicator(
                            progress = { bufferedPosition.toFloat() / duration.toFloat() },
                            modifier = Modifier.fillMaxWidth().height(2.dp),
                            color = Color.White.copy(alpha = 0.2f),
                            trackColor = Color.Transparent,
                        )
                    }
                    
                    Slider(
                        value = if (duration > 0) currentPosition.toFloat() else 0f,
                        onValueChange = { onSeek(it.toLong()) },
                        valueRange = 0f..(if (duration > 0) duration.toFloat() else 1f),
                        modifier = Modifier.fillMaxWidth(),
                        colors = SliderDefaults.colors(
                            thumbColor = Color.White,
                            activeTrackColor = Color.White,
                            inactiveTrackColor = Color.White.copy(alpha = 0.3f)
                        )
                    )
                }

                Row(
                    modifier = Modifier.fillMaxWidth().padding(bottom = 8.dp),
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.SpaceBetween
                ) {
                    Text(
                        text = formatDuration(currentPosition),
                        style = MaterialTheme.typography.labelSmall,
                        color = Color.White
                    )
                    
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        IconButton(onClick = onToggleFullscreen) {
                            Icon(Icons.Default.Fullscreen, contentDescription = "Fullscreen", tint = Color.White)
                        }
                    }
                }
            }
        }
    }
}

@Composable
fun AresGestureLayer(
    onVolumeChange: (Float) -> Unit,
    onBrightnessChange: (Float) -> Unit,
    onDoubleTapSeek: (Long) -> Unit,
    modifier: Modifier = Modifier,
    content: @Composable () -> Unit
) {
    var showHud by remember { mutableStateOf(false) }
    var hudType by remember { mutableStateOf("volume") }
    var hudValue by remember { mutableStateOf(0f) }
    
    val scope = rememberCoroutineScope()

    Box(
        modifier = modifier
            .fillMaxSize()
            .pointerInput(Unit) {
                detectTapGestures(
                    onDoubleTap = { offset ->
                        val isRightSide = offset.x > size.width / 2
                        onDoubleTapSeek(if (isRightSide) 10000L else -10000L)
                    }
                )
            }
            .pointerInput(Unit) {
                val width = size.width
                detectVerticalDragGestures(
                    onVerticalDrag = { change, dragAmount ->
                        change.consume()
                        showHud = true
                        val sensitivity = 0.002f
                        if (change.position.x < width / 2) {
                            hudType = "brightness"
                            onBrightnessChange(-dragAmount * sensitivity)
                        } else {
                            hudType = "volume"
                            onVolumeChange(-dragAmount * sensitivity)
                        }
                    },
                    onDragEnd = {
                        scope.launch {
                            delay(1500)
                            showHud = false
                        }
                    }
                )
            }
    ) {
        content()
        
        // Ares HUD (Material 3 Feedback)
        AnimatedVisibility(
            visible = showHud,
            enter = fadeIn() + scaleIn(),
            exit = fadeOut() + scaleOut(),
            modifier = Modifier.align(Alignment.Center)
        ) {
            Surface(
                color = Color.Black.copy(alpha = 0.8f),
                shape = RoundedCornerShape(24.dp),
                modifier = Modifier.size(120.dp),
                tonalElevation = 8.dp
            ) {
                Column(
                    modifier = Modifier.fillMaxSize(),
                    horizontalAlignment = Alignment.CenterHorizontally,
                    verticalArrangement = Arrangement.Center
                ) {
                    Icon(
                        imageVector = if (hudType == "volume") Icons.Default.VolumeUp else Icons.Default.BrightnessMedium,
                        contentDescription = null,
                        tint = Color.White,
                        modifier = Modifier.size(48.dp)
                    )
                    Spacer(modifier = Modifier.height(8.dp))
                    Text(
                        text = "${(hudValue * 100).roundToInt()}%",
                        color = Color.White,
                        fontWeight = FontWeight.Bold
                    )
                }
            }
        }
    }
}

private fun formatDuration(millis: Long): String {
    val totalSeconds = millis / 1000
    val minutes = totalSeconds / 60
    val seconds = totalSeconds % 60
    return "%02d:%02d".format(minutes, seconds)
}
