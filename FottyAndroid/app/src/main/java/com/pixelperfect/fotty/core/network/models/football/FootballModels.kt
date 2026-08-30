package com.pixelperfect.fotty.core.network.models.football

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable

@Serializable
data class FootballMatchesResponse(
    val matches: List<FootballMatch>,
    val resultSet: FootballResultSet? = null
)

@Serializable
data class FootballResultSet(
    val count: Int? = null,
    val competitions: String? = null,
    val first: String? = null,
    val last: String? = null,
    val played: Int? = null
)

@Serializable
data class FootballMatch(
    val id: Int,
    val utcDate: String,
    val status: String,
    val matchday: Int? = null,
    val stage: String? = null,
    val group: String? = null,
    val homeTeam: FootballTeam,
    val awayTeam: FootballTeam,
    val score: MatchScore,
    val competition: MatchCompetition,
    val referees: List<MatchReferee>? = null
)

@Serializable
data class FootballTeam(
    val id: Int? = null,
    val name: String? = null,
    val shortName: String? = null,
    val tla: String? = null,
    val crest: String? = null
)

@Serializable
data class MatchScore(
    val winner: String? = null,
    val duration: String? = null,
    val fullTime: ScoreDetail? = null,
    val halfTime: ScoreDetail? = null
)

@Serializable
data class ScoreDetail(
    val home: Int? = null,
    val away: Int? = null
)

@Serializable
data class MatchCompetition(
    val id: Int? = null,
    val name: String? = null,
    val code: String? = null,
    val emblem: String? = null
)

@Serializable
data class MatchReferee(
    val id: Int? = null,
    val name: String? = null,
    val nationality: String? = null
)

enum class MatchStatus(val value: String) {
    SCHEDULED("SCHEDULED"),
    TIMED("TIMED"),
    IN_PLAY("IN_PLAY"),
    PAUSED("PAUSED"),
    FINISHED("FINISHED"),
    SUSPENDED("SUSPENDED"),
    POSTPONED("POSTPONED"),
    CANCELLED("CANCELLED"),
    AWARDED("AWARDED")
}

enum class League(val code: String, val displayName: String) {
    PREMIER_LEAGUE("PL", "Premier League"),
    CHAMPIONS_LEAGUE("CL", "Champions League"),
    LA_LIGA("PD", "La Liga"),
    SERIE_A("SA", "Serie A"),
    BUNDESLIGA("BL1", "Bundesliga"),
    LIGUE_1("FL1", "Ligue 1")
}
