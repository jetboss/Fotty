package com.pixelperfect.fotty.data.models

import kotlinx.serialization.Serializable

import com.pixelperfect.fotty.core.network.models.streaming.SportEvent

@Serializable
data class Match(
    val id: String,
    val homeTeam: Team,
    val awayTeam: Team,
    val homeScore: Int? = null,
    val awayScore: Int? = null,
    val status: MatchStatus,
    val timestamp: Long,
    val league: League,
    val minute: Int? = null,
    val hypeLevel: Float = 0f,
    val category: String = "football",
    val posterUrl: String? = null,
    val statusText: String? = null,
    val intelligence: MatchIntelligence? = null,
    val activePeers: Int = 0,
    val healthScore: Int = 100
) {
    /**
     * Maps this football-specific Match to a sport-agnostic SportEvent.
     */
    fun toSportEvent(): SportEvent = SportEvent(
        id = id,
        title = "${homeTeam.name} vs ${awayTeam.name}",
        category = category,
        participants = listOf(homeTeam.name, awayTeam.name),
        timestamp = timestamp
    )
}

@Serializable
data class Team(
    val id: String,
    val name: String,
    val logoUrl: String?,
    val shortName: String? = null
)

@Serializable
data class League(
    val id: String,
    val name: String,
    val logoUrl: String?
)

@Serializable
enum class MatchStatus {
    SCHEDULED, LIVE, FINISHED, POSTPONED
}

@Serializable
data class Highlight(
    val id: String,
    val title: String,
    val thumbnailUrl: String,
    val duration: String,
    val videoUrl: String
)

@Serializable
data class MatchIntelligence(
    val possessionHome: Int = 50,
    val possessionAway: Int = 50,
    val shotsOnGoalHome: Int = 0,
    val shotsOnGoalAway: Int = 0,
    val winProbabilityHome: Float = 0.33f,
    val winProbabilityAway: Float = 0.33f,
    val xGHome: Float = 0f,
    val xGAway: Float = 0f,
    val momentumGraph: List<Float> = emptyList()
)
