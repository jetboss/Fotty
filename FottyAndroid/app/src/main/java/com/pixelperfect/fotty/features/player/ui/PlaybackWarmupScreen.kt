package com.pixelperfect.fotty.features.player.ui

import androidx.compose.animation.core.*
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.blur
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import coil.compose.AsyncImage
import com.pixelperfect.fotty.core.theme.Accent

@Composable
fun PlaybackWarmupScreen(
    homeTeam: String,
    awayTeam: String,
    statusHint: String,
    modifier: Modifier = Modifier
) {
    Box(modifier = modifier.fillMaxSize().background(Color.Black)) {
        // Blurred Backdrop (iOS Parity)
        AsyncImage(
            model = "https://images.unsplash.com/photo-1508098682722-e99c43a406b2?q=80&w=1000", // Default stadium
            contentDescription = null,
            modifier = Modifier.fillMaxSize().blur(20.dp).alpha(0.3f),
            contentScale = ContentScale.Crop
        )

        Box(
            modifier = Modifier
                .fillMaxSize()
                .background(
                    Brush.verticalGradient(
                        listOf(Color.Transparent, Color.Black.copy(alpha = 0.8f))
                    )
                )
        )

        Column(
            modifier = Modifier
                .align(Alignment.Center)
                .padding(32.dp),
            horizontalAlignment = Alignment.CenterHorizontally
        ) {
            // Animated Pulse Ring
            val infiniteTransition = rememberInfiniteTransition()
            val pulseScale by infiniteTransition.animateFloat(
                initialValue = 1f,
                targetValue = 1.2f,
                animationSpec = infiniteRepeatable(
                    animation = tween(1000, easing = FastOutSlowInEasing),
                    repeatMode = RepeatMode.Reverse
                )
            )

            Box(contentAlignment = Alignment.Center) {
                Surface(
                    modifier = Modifier.size(80.dp * pulseScale),
                    shape = CircleShape,
                    color = Accent.copy(alpha = 0.1f),
                    border = androidx.compose.foundation.BorderStroke(1.dp, Accent.copy(alpha = 0.3f))
                ) {}
                CircularProgressIndicator(
                    modifier = Modifier.size(48.dp),
                    color = Accent,
                    strokeWidth = 2.dp
                )
            }

            Spacer(modifier = Modifier.height(48.dp))

            Text(
                text = "$homeTeam vs $awayTeam".uppercase(),
                style = MaterialTheme.typography.headlineSmall,
                color = Color.White,
                fontWeight = FontWeight.Black,
                letterSpacing = 1.sp
            )

            Spacer(modifier = Modifier.height(8.dp))

            Text(
                text = statusHint.uppercase(),
                style = MaterialTheme.typography.labelSmall,
                color = Color.White.copy(alpha = 0.6f),
                fontWeight = FontWeight.Bold,
                letterSpacing = 2.sp
            )
        }

        // Bottom Brand
        Text(
            text = "POWERED BY ARES PLAYBACK ENGINE",
            modifier = Modifier
                .align(Alignment.BottomCenter)
                .padding(bottom = 48.dp),
            style = MaterialTheme.typography.labelSmall,
            color = Color.White.copy(alpha = 0.2f),
            fontWeight = FontWeight.Black,
            letterSpacing = 2.sp
        )
    }
}
