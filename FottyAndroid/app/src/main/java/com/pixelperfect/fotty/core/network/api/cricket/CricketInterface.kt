package com.pixelperfect.fotty.core.network.api.cricket

import kotlinx.serialization.Serializable
import retrofit2.http.GET
import retrofit2.http.Query

interface CricketInterface {
    @GET(".") // The base URL ends in /cricket/, so we use . for the current path
    suspend fun getMatches(
        @Query("APIkey") apiKey: String,
        @Query("method") method: String = "get_events",
        @Query("date_start") dateStart: String,
        @Query("date_stop") dateStop: String
    ): CricketResponse

    @GET(".")
    suspend fun getLiveScores(
        @Query("APIkey") apiKey: String,
        @Query("method") method: String = "get_livescore"
    ): CricketResponse
}

@Serializable
data class CricketResponse(
    val success: Int? = null,
    val result: List<CricketMatch>? = null
)

@Serializable
data class CricketMatch(
    val event_key: String? = null,
    val event_date: String? = null,
    val event_status: String? = null,
    val event_home_team: String? = null,
    val event_away_team: String? = null,
    val event_home_final_score: String? = null,
    val event_away_final_score: String? = null,
    val score: String? = null // Often contains the runs/wickets
)
