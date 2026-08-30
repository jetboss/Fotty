package com.pixelperfect.fotty.core.network.models.streaming

import kotlinx.serialization.Serializable

@Serializable
data class SportEvent(
    val id: String,
    val title: String,
    val category: String,
    val participants: List<String>,
    val timestamp: Long
)

// Extension to map existing football Match to SportEvent if needed
// This will be used in the StreamRepository later.
