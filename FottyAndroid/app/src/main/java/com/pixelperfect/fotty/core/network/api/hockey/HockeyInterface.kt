package com.pixelperfect.fotty.core.network.api.hockey

import com.pixelperfect.fotty.core.network.models.football.APIFootballResponse
import retrofit2.http.GET
import retrofit2.http.Header
import retrofit2.http.Query

interface HockeyInterface {
    @GET("games")
    suspend fun getGames(
        @Header("x-rapidapi-key") apiKey: String,
        @Query("date") date: String
    ): HockeyResponse
}

@kotlinx.serialization.Serializable
data class HockeyResponse(
    val get: String? = null,
    val parameters: kotlinx.serialization.json.JsonElement? = null,
    val errors: kotlinx.serialization.json.JsonElement? = null,
    val results: Int? = null,
    val response: List<HockeyGame>? = null
)

@kotlinx.serialization.Serializable
data class HockeyGame(
    val id: Int,
    val date: String? = null,
    val timestamp: Long? = null,
    val status: HockeyStatus? = null,
    val teams: HockeyTeams? = null,
    val scores: HockeyScores? = null,
    val league: HockeyLeague? = null
)

@kotlinx.serialization.Serializable
data class HockeyStatus(
    val long: String? = null,
    val short: String? = null
)

@kotlinx.serialization.Serializable
data class HockeyTeams(
    val home: HockeyTeam? = null,
    val away: HockeyTeam? = null
)

@kotlinx.serialization.Serializable
data class HockeyTeam(
    val id: Int? = null,
    val name: String? = null,
    val logo: String? = null
)

@kotlinx.serialization.Serializable
data class HockeyScores(
    val home: Int? = null,
    val away: Int? = null
)

@kotlinx.serialization.Serializable
data class HockeyLeague(
    val id: Int? = null,
    val name: String? = null,
    val logo: String? = null
)
