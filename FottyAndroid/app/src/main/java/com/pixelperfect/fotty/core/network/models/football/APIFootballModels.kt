package com.pixelperfect.fotty.core.network.models.football

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.JsonElement

@Serializable
data class APIFootballResponse(
    @SerialName("response") val response: List<APIFootballFixture>? = null,
    @SerialName("errors") val errors: JsonElement? = null
)

@Serializable
data class APIFootballFixture(
    @SerialName("fixture") val fixture: APIFootballFixtureInfo,
    @SerialName("league") val league: APIFootballLeague,
    @SerialName("teams") val teams: APIFootballTeams,
    @SerialName("goals") val goals: APIFootballGoals,
    @SerialName("score") val score: APIFootballScore
)

@Serializable
data class APIFootballFixtureInfo(
    @SerialName("id") val id: Int,
    @SerialName("date") val date: String? = null,
    @SerialName("status") val status: APIFootballStatus
)

@Serializable
data class APIFootballStatus(
    @SerialName("long") val long: String,
    @SerialName("short") val short: String,
    @SerialName("elapsed") val elapsed: Int? = null
)

@Serializable
data class APIFootballLeague(
    @SerialName("id") val id: Int,
    @SerialName("name") val name: String,
    @SerialName("logo") val logo: String? = null
)

@Serializable
data class APIFootballTeams(
    @SerialName("home") val home: APIFootballTeam,
    @SerialName("away") val away: APIFootballTeam
)

@Serializable
data class APIFootballTeam(
    @SerialName("id") val id: Int,
    @SerialName("name") val name: String,
    @SerialName("logo") val logo: String? = null
)

@Serializable
data class APIFootballGoals(
    @SerialName("home") val home: Int? = null,
    @SerialName("away") val away: Int? = null
)

@Serializable
data class APIFootballScore(
    @SerialName("halftime") val halftime: APIFootballGoals,
    @SerialName("fulltime") val fulltime: APIFootballGoals
)

// ── New Analytics Models ─────────────────────────────────────────────────────

@Serializable
data class APIFootballStatsResponse(
    @SerialName("response") val response: List<APIFootballTeamStats>
)

@Serializable
data class APIFootballTeamStats(
    @SerialName("team") val team: APIFootballTeam,
    @SerialName("statistics") val statistics: List<APIFootballStatistic>
)

@Serializable
data class APIFootballLineupResponse(
    @SerialName("response") val response: List<APIFootballLineup>
)

@Serializable
data class APIFootballLineup(
    @SerialName("team") val team: APIFootballTeam,
    @SerialName("formation") val formation: String? = null,
    @SerialName("startXI") val startXI: List<APIFootballPlayerEntry>,
    @SerialName("substitutes") val substitutes: List<APIFootballPlayerEntry>,
    @SerialName("coach") val coach: APIFootballCoach
)

@Serializable
data class APIFootballPlayerEntry(
    @SerialName("player") val player: APIFootballPlayerInfo
)

@Serializable
data class APIFootballPlayerInfo(
    @SerialName("id") val id: Int,
    @SerialName("name") val name: String,
    @SerialName("number") val number: Int? = null,
    @SerialName("pos") val pos: String? = null,
    @SerialName("grid") val grid: String? = null,
    @SerialName("xg") val xg: Float? = null,
    @SerialName("xa") val xa: Float? = null
)

@Serializable
data class APIFootballCoach(
    @SerialName("id") val id: Int? = null,
    @SerialName("name") val name: String? = null,
    @SerialName("photo") val photo: String? = null
)

@Serializable
data class APIFootballEventsResponse(
    @SerialName("response") val response: List<APIFootballEvent>
)

@Serializable
data class APIFootballEvent(
    @SerialName("time") val time: APIFootballEventTime,
    @SerialName("team") val team: APIFootballTeam,
    @SerialName("player") val player: APIFootballPlayerInfo,
    @SerialName("assist") val assist: APIFootballPlayerInfo? = null,
    @SerialName("type") val type: String, // Goal, Card, subst, Var
    @SerialName("detail") val detail: String, // Normal Goal, Yellow Card, etc
    @SerialName("comments") val comments: String? = null
)

@Serializable
data class APIFootballEventTime(
    @SerialName("elapsed") val elapsed: Int,
    @SerialName("extra") val extra: Int? = null
)

@Serializable
data class APIFootballStatistic(
    @SerialName("type") val type: String,
    @SerialName("value") val value: JsonElement? = null
)

@Serializable
data class APIFootballLeaguesResponse(
    @SerialName("response") val response: List<APIFootballLeagueEntry>
)

@Serializable
data class APIFootballLeagueEntry(
    @SerialName("league") val league: APIFootballLeague,
    @SerialName("country") val country: APIFootballCountry
)

@Serializable
data class APIFootballCountry(
    @SerialName("name") val name: String,
    @SerialName("code") val code: String? = null,
    @SerialName("flag") val flag: String? = null
)

@Serializable
data class APIFootballTeamsResponse(
    @SerialName("response") val response: List<APIFootballTeamEntry>
)

@Serializable
data class APIFootballTeamEntry(
    @SerialName("team") val team: APIFootballTeam,
    @SerialName("venue") val venue: APIFootballVenue? = null
)

@Serializable
data class APIFootballVenue(
    @SerialName("id") val id: Int? = null,
    @SerialName("name") val name: String? = null,
    @SerialName("city") val city: String? = null
)
