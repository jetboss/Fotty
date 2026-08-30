package com.pixelperfect.fotty.core.theme

import androidx.compose.animation.core.*
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.interaction.collectIsPressedAsState
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ripple
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.composed
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.*
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.foundation.gestures.*
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.layout.onGloballyPositioned
import androidx.compose.ui.graphics.graphicsLayer

/**
 * FOTTY MASTER: Monochromatic Depth
 */
@Composable
fun Modifier.moldedSurface(
    cornerRadius: Dp = 16.dp,
    elevation: Dp = 2.dp,
    isPressed: Boolean = false
) = this.then(
    Modifier
        .shadow(
            elevation = if (isPressed) 1.dp else elevation, 
            shape = RoundedCornerShape(cornerRadius),
            ambientColor = Color.Black.copy(alpha = 0.3f),
            spotColor = Color.Black.copy(alpha = 0.3f)
        )
        .background(MaterialTheme.colorScheme.surface, RoundedCornerShape(cornerRadius))
        .border(1.dp, MaterialTheme.colorScheme.outlineVariant.copy(alpha = 0.1f), RoundedCornerShape(cornerRadius))
)

/**
 * TACTICAL MONOLITH: Precision Edge Surface
 * Zero radius, matte black, high-intensity border.
 */
@Composable
fun Modifier.monolithSurface(
    borderColor: Color = MaterialTheme.colorScheme.primary.copy(alpha = 0.5f),
    borderWidth: Dp = 1.dp,
    backgroundColor: Color = MaterialTheme.colorScheme.surface
) = this.then(
    Modifier
        .background(backgroundColor)
        .border(borderWidth, borderColor)
)

/**
 * FOTTY MASTER: Rim Light
 * Highly subtle white/gray border to define edges in monochromatic UI.
 */
fun Modifier.rimLight(
    cornerRadius: Dp = 16.dp,
    pulseColor: Color = Color.Transparent
) = this.then(
    Modifier.border(
        width = 1.dp, 
        color = if (pulseColor != Color.Transparent) pulseColor else Color.White.copy(alpha = 0.08f), 
        shape = RoundedCornerShape(cornerRadius)
    )
)

/**
 * FOTTY MASTER: Adaptive Pulse
 */
fun Modifier.adaptivePulse(
    enabled: Boolean = false,
    color: Color = Accent
) = composed {
    if (!enabled) return@composed Modifier
    
    val infiniteTransition = rememberInfiniteTransition(label = "pulse")
    val alpha by infiniteTransition.animateFloat(
        initialValue = 0.05f,
        targetValue = 0.4f,
        animationSpec = infiniteRepeatable(
            animation = tween(1200, easing = FastOutSlowInEasing),
            repeatMode = RepeatMode.Reverse
        ),
        label = "alpha"
    )
    
    this.rimLight(pulseColor = color.copy(alpha = alpha))
}

/**
 * TACTICAL MONOLITH: High-Intensity Tactical Pulse
 */
fun Modifier.tacticalPulse() = composed {
    val primaryColor = MaterialTheme.colorScheme.primary
    val infiniteTransition = rememberInfiniteTransition(label = "tactical_pulse")
    val alpha by infiniteTransition.animateFloat(
        initialValue = 0.2f,
        targetValue = 0.8f,
        animationSpec = infiniteRepeatable(
            animation = tween(800, easing = LinearEasing),
            repeatMode = RepeatMode.Reverse
        ),
        label = "alpha"
    )
    
    this.border(1.dp, primaryColor.copy(alpha = alpha))
}

/**
 * FOTTY MASTER: Tactile Press
 */
fun Modifier.tactilePress(
    onClick: () -> Unit = {}
) = composed {
    val interactionSource = remember { MutableInteractionSource() }
    val isPressed by interactionSource.collectIsPressedAsState()
    
    this.moldedSurface(isPressed = isPressed)
        .clickable(
            interactionSource = interactionSource,
            indication = null, 
            onClick = onClick
        )
}

/**
 * Standard Card Style for Kinetic Minimalism.
 */
@Composable
fun Modifier.cardStyle(
    cornerRadius: Dp = 16.dp
) = this.moldedSurface(cornerRadius).rimLight(cornerRadius)

/**
 * FOTTY MASTER: Flick to Dismiss
 */
fun Modifier.flickToDismiss(
    onDismiss: () -> Unit
) = this.pointerInput(Unit) {
    detectDragGestures { change, dragAmount ->
        change.consume()
        if (dragAmount.y < -50) { 
            onDismiss()
        }
    }
}

/**
 * FOTTY M3: Shimmer Effect for high-fidelity loading states.
 */
fun Modifier.shimmerEffect(): Modifier = composed {
    var size by remember { mutableStateOf(androidx.compose.ui.geometry.Size.Zero) }
    val transition = rememberInfiniteTransition(label = "shimmer")
    val startOffsetX by transition.animateFloat(
        initialValue = -2 * size.width,
        targetValue = 2 * size.width,
        animationSpec = infiniteRepeatable(
            animation = tween(1000)
        ),
        label = "shimmer_offset"
    )

    background(
        brush = Brush.linearGradient(
            colors = listOf(
                Color.White.copy(alpha = 0.05f),
                Color.White.copy(alpha = 0.15f),
                Color.White.copy(alpha = 0.05f),
            ),
            start = Offset(startOffsetX, 0f),
            end = Offset(startOffsetX + size.width, size.height)
        )
    ).onGloballyPositioned {
        size = androidx.compose.ui.geometry.Size(it.size.width.toFloat(), it.size.height.toFloat())
    }
}

/**
 * FOTTY M3: Subtle Tactile Scale for high-fidelity interactions.
 */
fun Modifier.m3TactileScale(
    onClick: () -> Unit = {}
) = composed {
    val interactionSource = remember { MutableInteractionSource() }
    val isPressed by interactionSource.collectIsPressedAsState()
    val scale by animateFloatAsState(
        targetValue = if (isPressed) 0.98f else 1f,
        label = "scale"
    )

    this.graphicsLayer(scaleX = scale, scaleY = scale)
        .clickable(
            interactionSource = interactionSource,
            indication = ripple(),
            onClick = onClick
        )
}

/**
 * FOTTY MASTER: Grainy Texture (M3 Polished)
 */
fun Modifier.grainyBackground(
    alpha: Float = 0.03f 
) = this.drawBehind {
    drawRect(
        color = Color.White.copy(alpha = alpha),
        size = size
    )
}
