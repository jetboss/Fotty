package com.pixelperfect.fotty.core.network.api.football

import com.pixelperfect.fotty.core.network.models.football.FootballMatchesResponse
import retrofit2.http.GET
import retrofit2.http.Header
import retrofit2.http.Path
import retrofit2.http.Query

interface FootballInterface {
    @GET("competitions/{league}/matches")
    suspend fun getMatches(
        @Path("league") league: String,
        @Header("X-Auth-Token") apiKey: String,
        @Query("status") status: String? = null,
        @Query("limit") limit: Int? = null,
        @Query("dateFrom") dateFrom: String? = null,
        @Query("dateTo") dateTo: String? = null
    ): FootballMatchesResponse
}
