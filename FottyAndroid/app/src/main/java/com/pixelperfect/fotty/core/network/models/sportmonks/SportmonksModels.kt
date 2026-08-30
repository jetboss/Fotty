package com.pixelperfect.fotty.core.network.models.sportmonks

import kotlinx.serialization.Serializable

@Serializable
data class SportmonksParticipantResponse(
    val data: List<SportmonksParticipant>
)

@Serializable
data class SportmonksSingleResponse(
    val data: SportmonksFixture
)

@Serializable
data class SportmonksResponse(
    val data: List<SportmonksFixture>
)

@Serializable
data class SportmonksFixture(
    val id: Int,
    val name: String,
    val starting_at: String,
    val lineups: List<SportmonksLineup>? = null,
    val participants: List<SportmonksParticipant>? = null,
    val scores: List<SportmonksScore>? = null,
    val events: List<SportmonksEvent>? = null,
    val league: SportmonksLeague? = null,
    val statistics: List<SportmonksStatistic>? = null
)

@Serializable
data class SportmonksLineup(
    val id: Long? = null,
    val team_id: Int,
    val player_id: Int,
    val type_id: Int, // 11=Starter, 12=Sub
    val player_name: String,
    val jersey_number: Int? = null,
    val formation_position: Int? = null,
    val formation_field: String? = null, // V3 uses formation_field for coordinates
    val is_starter: Int? = null,
    val statistics: List<SportmonksStatistic>? = null
)

@Serializable
data class SportmonksParticipant(
    val id: Int,
    val name: String,
    val image_path: String? = null,
    val meta: SportmonksMeta? = null
)

@Serializable
data class SportmonksMeta(
    val location: String? = null // "home" or "away"
)

@Serializable
data class SportmonksScore(
    val participant_id: Int,
    val score: SportmonksScoreValue? = null
)

@Serializable
data class SportmonksScoreValue(
    val goals: Int? = null,
    val participant: String? = null
)

@Serializable
data class SportmonksEvent(
    val minute: Int,
    val type_id: Int,
    val player_name: String? = null,
    val related_player_name: String? = null,
    val team_id: Int? = null
)

@Serializable
data class SportmonksLeague(
    val id: Int,
    val name: String,
    val image_path: String? = null
)

@Serializable
data class SportmonksStatistic(
    val type_id: Int,
    val participant_id: Int? = null,
    val data: SportmonksStatisticValue? = null
)

@Serializable
data class SportmonksStatisticValue(
    val value: Float? = null,
    val count: Int? = null,
    val total: Int? = null,
    val percentage: Float? = null
)
