package com.pixelperfect.fotty.features.player.ui

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.dp
import androidx.lifecycle.viewmodel.compose.viewModel
import com.pixelperfect.fotty.features.player.viewmodel.PlaybackState
import com.pixelperfect.fotty.features.player.viewmodel.StreamPlayerViewModel

@Composable
fun Media3PlayerScreen(
    streamUrl: String = "https://test-streams.mux.dev/x36xhzz/x36xhzz.m3u8", // Big Buck Bunny HLS Mock
    onBack: () -> Unit
) {
    val viewModel: StreamPlayerViewModel = viewModel()
    val playbackState by viewModel.playbackState.collectAsState()
    val currentPosition by viewModel.currentPosition.collectAsState()
    val duration by viewModel.duration.collectAsState()
    
    var controlsVisible by remember { mutableStateOf(true) }

    LaunchedEffect(streamUrl) {
        viewModel.playStream(streamUrl)
    }

    Box(
        modifier = Modifier
            .fillMaxSize()
            .clickable { controlsVisible = !controlsVisible }
    ) {
        // Core Player
        Media3Player(player = viewModel.player)

        // Custom M3 Controls
        MediaControls(
            isVisible = controlsVisible,
            isPlaying = viewModel.player?.isPlaying ?: false,
            currentPosition = currentPosition,
            duration = duration,
            onPlayPauseToggle = { viewModel.togglePlayPause() },
            onSeek = { viewModel.seekTo(it) },
            onFullscreenToggle = { /* Handle fullscreen */ },
            onBack = onBack
        )

        // Buffering State
        if (playbackState is PlaybackState.Buffering) {
            CircularProgressIndicator(
                modifier = Modifier.align(Alignment.Center),
                color = MaterialTheme.colorScheme.primary
            )
        }

        // Error State
        if (playbackState is PlaybackState.Error) {
            Surface(
                modifier = Modifier.fillMaxSize(),
                color = Color.Black.copy(alpha = 0.8f)
            ) {
                Column(
                    modifier = Modifier.fillMaxSize(),
                    verticalArrangement = Arrangement.Center,
                    horizontalAlignment = Alignment.CenterHorizontally
                ) {
                    Text(
                        text = (playbackState as PlaybackState.Error).message,
                        color = MaterialTheme.colorScheme.error,
                        style = MaterialTheme.typography.bodyLarge,
                        modifier = Modifier.padding(16.dp)
                    )
                    Button(onClick = { viewModel.playStream(streamUrl) }) {
                        Text("Retry")
                    }
                }
            }
        }
    }
}
