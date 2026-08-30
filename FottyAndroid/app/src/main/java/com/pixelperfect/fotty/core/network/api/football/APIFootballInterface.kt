package com.pixelperfect.fotty.core.network.api.football

import com.pixelperfect.fotty.core.network.models.football.APIFootballResponse
import retrofit2.http.GET
import retrofit2.http.Header
import retrofit2.http.Query

interface APIFootballInterface {
    @GET("fixtures")
    suspend fun getLiveFixtures(
        @Header("x-apisports-key") apiKey: String,
        @Query("live") live: String = "all"
    ): APIFootballResponse

    @GET("fixtures")
    suspend fun getFixtureById(
        @Header("x-apisports-key") apiKey: String,
        @Query("id") fixtureId: Int
    ): APIFootballResponse

    @GET("fixtures")
    suspend fun getFixturesByDate(
        @Header("x-apisports-key") apiKey: String,
        @Query("date") date: String,
        @Query("league") league: Int? = null,
        @Query("season") season: Int? = null
    ): APIFootballResponse

    @GET("fixtures/statistics")
    suspend fun getFixtureStatistics(
        @Header("x-apisports-key") apiKey: String,
        @Query("fixture") fixtureId: Int
    ): com.pixelperfect.fotty.core.network.models.football.APIFootballStatsResponse

    @GET("fixtures/lineups")
    suspend fun getFixtureLineups(
        @Header("x-apisports-key") apiKey: String,
        @Query("fixture") fixtureId: Int
    ): com.pixelperfect.fotty.core.network.models.football.APIFootballLineupResponse

    @GET("fixtures/events")
    suspend fun getFixtureEvents(
        @Header("x-apisports-key") apiKey: String,
        @Query("fixture") fixtureId: Int
    ): com.pixelperfect.fotty.core.network.models.football.APIFootballEventsResponse

    @GET("leagues")
    suspend fun getLeagues(
        @Header("x-apisports-key") apiKey: String
    ): com.pixelperfect.fotty.core.network.models.football.APIFootballLeaguesResponse

    @GET("teams")
    suspend fun getTeams(
        @Header("x-apisports-key") apiKey: String,
        @Query("league") leagueId: Int,
        @Query("season") season: Int
    ): com.pixelperfect.fotty.core.network.models.football.APIFootballTeamsResponse
}
