package com.pixelperfect.fotty.core.network.api.football

import com.pixelperfect.fotty.core.network.models.football.FootballMatchesResponse
import retrofit2.http.GET
import retrofit2.http.Query

/** Fotty Web football-data.org proxy — no client API key required. */
interface FottyFootballProxyInterface {
    @GET("api/football/matches/")
    suspend fun getMatches(
        @Query("competition") competition: String? = null,
        @Query("status") status: String? = null,
        @Query("limit") limit: Int? = null,
        @Query("dateFrom") dateFrom: String? = null,
        @Query("dateTo") dateTo: String? = null,
        @Query("season") season: String? = null,
    ): FootballMatchesResponse
}
