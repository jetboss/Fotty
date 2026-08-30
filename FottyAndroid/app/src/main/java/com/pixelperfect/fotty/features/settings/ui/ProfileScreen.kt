package com.pixelperfect.fotty.features.settings.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.foundation.lazy.grid.items
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.pixelperfect.fotty.features.settings.viewmodel.ProfileViewModel
import com.pixelperfect.fotty.core.theme.*
import com.pixelperfect.fotty.ui.components.*

@Composable
fun ProfileScreen(
    viewModel: ProfileViewModel,
    onBack: () -> Unit
) {
    val profile = viewModel.profile
    var displayName by remember(profile) { mutableStateOf(profile?.displayName ?: "") }
    var selectedSymbol by remember(profile) { mutableStateOf(profile?.avatarSymbol ?: "⚽") }

    val symbols = listOf("⚽", "🏟️", "🏆", "🏃", "🧤", "📣", "🔥", "💎", "🦁", "🦅", "🐺", "🔴", "🔵", "⚪", "⚫", "🟡")

    Box(
        modifier = Modifier
            .fillMaxSize()
            .background(Background)
            .grainyBackground()
            .flickToDismiss(onDismiss = onBack)
    ) {
        Column(modifier = Modifier.fillMaxSize()) {
            // 1. MACHINED IDENTITY HEADER
            Box(
                modifier = Modifier
                    .fillMaxWidth()
                    .statusBarsPadding()
                    .moldedSurface(cornerRadius = 0.dp)
                    .padding(horizontal = 24.dp, vertical = 20.dp)
            ) {
                Column {
                    Text(
                        text = "IDENTITY CONFIG",
                        style = Typography.titleLarge.copy(fontSize = 20.sp, fontWeight = FontWeight.Black),
                        color = TextPrimary
                    )
                    Text(
                        text = "SOCIAL SIGNATURE ENCRYPTION",
                        style = Typography.labelSmall.copy(color = Accent, letterSpacing = 1.5.sp)
                    )
                }
            }

            Column(
                modifier = Modifier
                    .fillMaxSize()
                    .padding(24.dp),
                horizontalAlignment = Alignment.CenterHorizontally
            ) {
                // PRECISION BADGE PREVIEW
                Box(
                    modifier = Modifier
                        .size(120.dp)
                        .moldedSurface(cornerRadius = 60.dp),
                    contentAlignment = Alignment.Center
                ) {
                    Text(text = selectedSymbol, fontSize = 60.sp)
                }

                Spacer(modifier = Modifier.height(40.dp))

                // MACHINED INPUT
                Text(
                    text = "DISPLAY SIGNATURE",
                    style = Typography.labelSmall.copy(color = TextSecondary, letterSpacing = 2.sp),
                    modifier = Modifier.align(Alignment.Start).padding(bottom = 8.dp)
                )
                Box(
                    modifier = Modifier
                        .fillMaxWidth()
                        .rimLight(cornerRadius = 12.dp)
                        .padding(16.dp)
                ) {
                    BasicTextField(
                        value = displayName,
                        onValueChange = { displayName = it },
                        textStyle = Typography.bodyMedium.copy(color = TextPrimary, fontWeight = FontWeight.Bold),
                        cursorBrush = androidx.compose.ui.graphics.SolidColor(Accent)
                    )
                }

                Spacer(modifier = Modifier.height(32.dp))

                Text(
                    text = "FAN BADGE ALLOCATION",
                    style = Typography.labelSmall.copy(color = TextSecondary, letterSpacing = 2.sp),
                    modifier = Modifier.align(Alignment.Start).padding(bottom = 12.dp)
                )

                LazyVerticalGrid(
                    columns = GridCells.Fixed(4),
                    horizontalArrangement = Arrangement.spacedBy(16.dp),
                    verticalArrangement = Arrangement.spacedBy(16.dp),
                    modifier = Modifier.weight(1f)
                ) {
                    items(symbols) { symbol ->
                        val isSelected = selectedSymbol == symbol
                        Box(
                            modifier = Modifier
                                .aspectRatio(1f)
                                .moldedSurface(cornerRadius = 12.dp)
                                .clickable { selectedSymbol = symbol }
                                .padding(4.dp),
                            contentAlignment = Alignment.Center
                        ) {
                            if (isSelected) {
                                Box(modifier = Modifier.fillMaxSize().rimLight(cornerRadius = 12.dp, pulseColor = Accent))
                            }
                            Text(text = symbol, fontSize = 28.sp)
                        }
                    }
                }

                // MACHINED SAVE ACTION
                Box(
                    modifier = Modifier
                        .fillMaxWidth()
                        .height(56.dp)
                        .rimLight(cornerRadius = 28.dp, pulseColor = if (displayName.isNotBlank()) Accent else Color.Transparent)
                        .clickable(enabled = displayName.isNotBlank() && !viewModel.isSaving) {
                            viewModel.updateProfile(displayName, selectedSymbol, onBack)
                        },
                    contentAlignment = Alignment.Center
                ) {
                    if (viewModel.isSaving) {
                        CircularProgressIndicator(color = Accent, modifier = Modifier.size(24.dp))
                    } else {
                        Text(
                            text = "COMMIT CHANGES",
                            style = Typography.labelSmall.copy(fontWeight = FontWeight.Black, color = if (displayName.isNotBlank()) TextPrimary else TextTertiary)
                        )
                    }
                }
            }
        }
    }
}
