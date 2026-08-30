package com.pixelperfect.fotty.data.models

data class NewsItem(
    val id: String,
    val title: String,
    val summary: String,
    val imageUrl: String?,
    val sourceName: String,
    val publishTime: Long,
    val category: String, // "Tactical", "Transfer", "Match Update"
    val relatedTeamId: String? = null,
    val relatedLeagueId: String? = null,
    val url: String? = null
)
