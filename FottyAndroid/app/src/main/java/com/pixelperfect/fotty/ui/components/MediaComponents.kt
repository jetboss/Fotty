package com.pixelperfect.fotty.ui.components

import androidx.compose.animation.core.*
import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Hub
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.runtime.getValue
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import coil.compose.SubcomposeAsyncImage
import com.pixelperfect.fotty.core.storage.TeamBrandService
import com.pixelperfect.fotty.core.theme.*

@Composable
fun TeamBadge(
    crestUrl: String?,
    name: String,
    teamId: String? = null,
    size: Dp = 48.dp,
    modifier: Modifier = Modifier
) {
    val context = androidx.compose.ui.platform.LocalContext.current
    val brandService = remember {
        dagger.hilt.android.EntryPointAccessors.fromApplication(
            context.applicationContext,
            TeamBrandEntryPoint::class.java
        ).brandService()
    }

    var resolvedUrl by remember(crestUrl) { mutableStateOf(crestUrl) }
    var isResolvingFallback by remember { mutableStateOf(false) }
    
    // Deterministic Premium Gradient based on Name (matching iOS logic)
    val colors = remember(name) {
        val hash = name.hashCode()
        val hue1 = (hash % 360).coerceAtLeast(0).toFloat()
        val hue2 = ((hash + 60) % 360).coerceAtLeast(0).toFloat()
        listOf(
            Color.hsl(hue1, 0.6f, 0.4f),
            Color.hsl(hue2, 0.7f, 0.3f)
        )
    }

    suspend fun tryResolveBrand() {
        if (isResolvingFallback) return
        isResolvingFallback = true
        android.util.Log.d("TeamBadge", "Resolving dedicated brand for: $name")
        val dbBadge = brandService.resolveBadge(name)
        if (dbBadge != null) {
            android.util.Log.d("TeamBadge", "Resolved brand for $name -> $dbBadge")
            resolvedUrl = dbBadge
        }
        isResolvingFallback = false
    }

    LaunchedEffect(name, crestUrl) {
        if (resolvedUrl.isNullOrBlank()) {
            tryResolveBrand()
        }
    }

    Box(
        modifier = modifier
            .size(size)
            .clip(CircleShape),
        contentAlignment = Alignment.Center
    ) {
        if (!resolvedUrl.isNullOrBlank()) {
            SubcomposeAsyncImage(
                model = resolvedUrl,
                contentDescription = name,
                modifier = Modifier.fillMaxSize(),
                contentScale = ContentScale.Fit,
                loading = {
                    Box(modifier = Modifier.fillMaxSize().shimmerEffect())
                },
                error = {
                    val scope = rememberCoroutineScope()
                    LaunchedEffect(Unit) {
                        android.util.Log.w("TeamBadge", "Primary load failed for $name ($resolvedUrl), attempting brand resolution...")
                        tryResolveBrand()
                    }
                    
                    InitialsFallback(name = name, colors = colors, size = size)
                }
            )
        } else {
            InitialsFallback(name = name, colors = colors, size = size)
        }
    }
}

@dagger.hilt.EntryPoint
@dagger.hilt.InstallIn(dagger.hilt.components.SingletonComponent::class)
interface TeamBrandEntryPoint {
    fun brandService(): TeamBrandService
}

@Composable
private fun InitialsFallback(name: String, colors: List<Color>, size: Dp) {
    Box(
        modifier = Modifier
            .fillMaxSize()
            .background(Brush.linearGradient(colors)),
        contentAlignment = Alignment.Center
    ) {
        Text(
            text = getInitials(name),
            style = MaterialTheme.typography.titleMedium.copy(
                fontWeight = FontWeight.Black,
                fontSize = (size.value * 0.35).sp,
                color = Color.White
            )
        )
    }
}

private fun getInitials(name: String): String {
    val words = name.split(" ")
    return if (words.size >= 2) {
        (words[0].take(1) + words[1].take(1)).uppercase()
    } else {
        name.take(2).uppercase()
    }
}

@Composable
fun P2PBadge(modifier: Modifier = Modifier) {
    Surface(
        modifier = modifier,
        shape = MaterialTheme.shapes.extraSmall,
        color = MaterialTheme.colorScheme.tertiaryContainer,
        contentColor = MaterialTheme.colorScheme.onTertiaryContainer
    ) {
        Row(
            verticalAlignment = Alignment.CenterVertically,
            modifier = Modifier.padding(horizontal = 6.dp, vertical = 2.dp)
        ) {
            Icon(
                imageVector = Icons.Default.Hub,
                contentDescription = null,
                modifier = Modifier.size(10.dp)
            )
            Spacer(modifier = Modifier.width(4.dp))
            Text(
                text = "P2P NETWORK",
                style = MaterialTheme.typography.labelSmall.copy(
                    fontSize = 8.sp,
                    fontWeight = FontWeight.Black,
                    letterSpacing = 0.5.sp
                )
            )
        }
    }
}

@Composable
fun LivePulse(modifier: Modifier = Modifier) {
    val infiniteTransition = rememberInfiniteTransition(label = "live_pulse")
    
    val scale by infiniteTransition.animateFloat(
        initialValue = 1f,
        targetValue = 1.4f,
        animationSpec = infiniteRepeatable(
            animation = tween(1000, easing = FastOutSlowInEasing),
            repeatMode = RepeatMode.Reverse
        ),
        label = "scale"
    )
    
    val alpha by infiniteTransition.animateFloat(
        initialValue = 1f,
        targetValue = 0.6f,
        animationSpec = infiniteRepeatable(
            animation = tween(1000, easing = FastOutSlowInEasing),
            repeatMode = RepeatMode.Reverse
        ),
        label = "alpha"
    )

    Surface(
        modifier = modifier,
        shape = androidx.compose.foundation.shape.CircleShape,
        color = MaterialTheme.colorScheme.error.copy(alpha = 0.12f),
        border = BorderStroke(0.5.dp, MaterialTheme.colorScheme.error.copy(alpha = 0.3f))
    ) {
        Row(
            verticalAlignment = Alignment.CenterVertically,
            modifier = Modifier.padding(horizontal = 10.dp, vertical = 5.dp)
        ) {
            Box(
                modifier = Modifier
                    .size(6.dp)
                    .graphicsLayer(
                        scaleX = scale,
                        scaleY = scale,
                        alpha = alpha
                    )
                    .background(MaterialTheme.colorScheme.error, androidx.compose.foundation.shape.CircleShape)
            )
            Spacer(modifier = Modifier.width(6.dp))
            Text(
                text = "LIVE",
                style = MaterialTheme.typography.labelSmall.copy(
                    fontSize = 10.sp,
                    fontWeight = FontWeight.Black,
                    letterSpacing = 0.5.sp
                ),
                color = MaterialTheme.colorScheme.error
            )
        }
    }
}

@Composable
fun LeagueBadge(
    name: String,
    logoUrl: String? = null,
    modifier: Modifier = Modifier
) {
    Surface(
        modifier = modifier,
        shape = MaterialTheme.shapes.small,
        color = MaterialTheme.colorScheme.secondaryContainer.copy(alpha = 0.7f),
        contentColor = MaterialTheme.colorScheme.onSecondaryContainer
    ) {
        Row(
            verticalAlignment = Alignment.CenterVertically,
            modifier = Modifier.padding(horizontal = 8.dp, vertical = 4.dp)
        ) {
            if (logoUrl != null) {
                SubcomposeAsyncImage(
                    model = logoUrl,
                    contentDescription = null,
                    modifier = Modifier.size(14.dp),
                    contentScale = ContentScale.Fit
                )
                Spacer(modifier = Modifier.width(6.dp))
            }
            Text(
                text = name.uppercase(),
                style = MaterialTheme.typography.labelSmall.copy(
                    fontSize = 9.sp,
                    fontWeight = FontWeight.Bold
                )
            )
        }
    }
}

@Composable
fun SectionHeader(
    title: String,
    modifier: Modifier = Modifier
) {
    Text(
        text = title,
        style = MaterialTheme.typography.titleSmall.copy(
            fontWeight = FontWeight.ExtraBold,
            letterSpacing = 2.sp,
            color = MaterialTheme.colorScheme.primary
        ),
        modifier = modifier.padding(vertical = 8.dp)
    )
}
