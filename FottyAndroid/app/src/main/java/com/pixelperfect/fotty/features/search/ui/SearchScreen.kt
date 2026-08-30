package com.pixelperfect.fotty.features.search.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Search
import androidx.compose.material3.*
import androidx.compose.runtime.Composable
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import coil.compose.AsyncImage
import com.pixelperfect.fotty.core.Config
import com.pixelperfect.fotty.core.network.models.sportmonks.SportmonksParticipant
import com.pixelperfect.fotty.features.search.viewmodel.SearchViewModel
import com.pixelperfect.fotty.core.theme.*
import com.pixelperfect.fotty.ui.components.*

@Composable
fun SearchScreen(
    viewModel: SearchViewModel,
    onParticipantClick: (Int) -> Unit
) {
    Box(
        modifier = Modifier
            .fillMaxSize()
            .background(Background)
            .grainyBackground()
    ) {
        Column(modifier = Modifier.fillMaxSize()) {
            // 1. MACHINED SEARCH INPUT
            Box(
                modifier = Modifier
                    .fillMaxWidth()
                    .statusBarsPadding()
                    .moldedSurface(cornerRadius = 0.dp)
                    .padding(horizontal = 24.dp, vertical = 20.dp)
            ) {
                KineticSearchField(
                    query = viewModel.query,
                    onQueryChange = viewModel::onQueryChange,
                    onClear = viewModel::clearSearch
                )
            }

            if (viewModel.isSearching) {
                Box(modifier = Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                    CircularProgressIndicator(color = Accent)
                }
            } else if (viewModel.results.isEmpty()) {
                Box(modifier = Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                    Text(
                        text = if (viewModel.hasSearched) "NO RESULTS FOUND" else "SEARCH TEAMS & PLAYERS",
                        style = Typography.labelSmall.copy(color = TextTertiary, letterSpacing = 2.sp)
                    )
                }
            } else {
                LazyColumn(
                    modifier = Modifier.fillMaxSize(),
                    contentPadding = PaddingValues(24.dp),
                    verticalArrangement = Arrangement.spacedBy(20.dp)
                ) {
                    items(viewModel.results) { item ->
                        KineticSearchResult(
                            item = item,
                            onClick = { onParticipantClick(item.id) }
                        )
                    }
                }
            }
        }
    }
}

@Composable
fun KineticSearchField(
    query: String,
    onQueryChange: (String) -> Unit,
    onClear: () -> Unit
) {
    Box(
        modifier = Modifier
            .fillMaxWidth()
            .rimLight(cornerRadius = 12.dp)
            .padding(horizontal = 16.dp, vertical = 12.dp)
    ) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            BasicTextField(
                value = query,
                onValueChange = onQueryChange,
                modifier = Modifier.weight(1f),
                textStyle = Typography.bodyMedium.copy(color = TextPrimary),
                cursorBrush = androidx.compose.ui.graphics.SolidColor(Accent),
                decorationBox = { innerTextField ->
                    if (query.isEmpty()) {
                        Text("Search sports database...", style = Typography.bodyMedium.copy(color = TextTertiary))
                    }
                    innerTextField()
                }
            )
            if (query.isNotEmpty()) {
                Text(
                    text = "CLEAR",
                    style = Typography.labelSmall.copy(fontSize = 10.sp),
                    color = Accent,
                    modifier = Modifier.clickable { onClear() }
                )
            }
        }
    }
}

@Composable
fun KineticSearchResult(
    item: SportmonksParticipant,
    onClick: () -> Unit
) {
    Box(
        modifier = Modifier
            .fillMaxWidth()
            .moldedSurface(cornerRadius = 16.dp)
            .clickable { onClick() }
            .padding(12.dp)
    ) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            AsyncImage(
                model = item.image_path,
                contentDescription = null,
                contentScale = ContentScale.Crop,
                modifier = Modifier
                    .size(60.dp)
                    .clip(CircleShape)
            )

            Spacer(modifier = Modifier.width(16.dp))

            Column(modifier = Modifier.weight(1f)) {
                Text(
                    text = item.name.uppercase(),
                    style = Typography.bodyMedium.copy(fontWeight = FontWeight.Black, letterSpacing = 0.5.sp),
                    color = TextPrimary,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis
                )
                Text(
                    text = "FOOTBALL PARTICIPANT",
                    style = Typography.labelSmall.copy(fontSize = 10.sp, color = TextSecondary),
                    modifier = Modifier.padding(top = 4.dp)
                )
            }
        }
    }
}
