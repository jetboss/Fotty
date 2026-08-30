package com.pixelperfect.fotty.features.player.viewmodel

import com.pixelperfect.fotty.core.network.models.streaming.StreamSource
import com.pixelperfect.fotty.data.models.MatchIntelligence

sealed class PlayerState {
    object Idle : PlayerState()
    object Resolving : PlayerState()
    object Handshake : PlayerState()
    data class Playback(val source: StreamSource) : PlayerState()
    data class PlaybackStalled(val source: StreamSource) : PlayerState()
    data class Error(val message: String, val lastSource: StreamSource? = null) : PlayerState()
}

data class IntelligenceState(
    val intelligence: MatchIntelligence? = null,
    val events: List<com.pixelperfect.fotty.core.network.models.football.APIFootballEvent> = emptyList(),
    val isVisible: Boolean = false
)

data class DiagnosticInfo(
    val matchId: String = "",
    val stableId: String = "",
    val rawSourceCount: Int = 0,
    val mappedSourceCount: Int = 0,
    val rejectedSourceCount: Int = 0,
    val playableSourceCount: Int = 0,
    val backfillCount: Int = 0,
    val lastHttpStatus: Int = 0,
    val lastError: String? = null,
    val matchStatus: String? = null,
    val matchTime: String? = null
)

data class FullCatalogBackfillResult(
    val match: com.pixelperfect.fotty.core.extractors.LiveSportsExtractor.StreamexMatch?,
    val mappedByRequestedId: Boolean
)
