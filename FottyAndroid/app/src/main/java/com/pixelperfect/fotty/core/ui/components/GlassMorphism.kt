package com.pixelperfect.fotty.core.ui.components

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.blur
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import com.pixelperfect.fotty.core.theme.Border
import com.pixelperfect.fotty.core.theme.Glass

/**
 * Premium Glassmorphism Modifier for Jetpack Compose.
 * Replicates the iOS .glassBackground() effect with blur, tint, and rim light.
 */
fun Modifier.glassBackground(
    cornerRadius: Dp = 12.dp,
    blurRadius: Dp = 16.dp,
    tint: Color = Glass,
    borderColor: Color = Border
): Modifier = this
    .clip(RoundedCornerShape(cornerRadius))
    .blur(blurRadius)
    .background(tint)
    .border(
        width = 0.5.dp,
        brush = Brush.linearGradient(
            colors = listOf(
                Color.White.copy(alpha = 0.15f),
                Color.White.copy(alpha = 0.02f),
                Color.White.copy(alpha = 0.05f)
            ),
            start = Offset(0f, 0f),
            end = Offset.Infinite
        ),
        shape = RoundedCornerShape(cornerRadius)
    )

/**
 * Alternative implementation using drawBehind for performance-sensitive layouts.
 */
fun Modifier.glassCard(
    cornerRadius: Dp = 12.dp,
    tint: Color = Glass
): Modifier = this
    .background(
        color = tint,
        shape = RoundedCornerShape(cornerRadius)
    )
    .border(
        width = 0.5.dp,
        color = Border,
        shape = RoundedCornerShape(cornerRadius)
    )
