package com.pixelperfect.fotty.core.network.api.football

import com.pixelperfect.fotty.core.network.models.sportmonks.*
import retrofit2.http.GET
import retrofit2.http.Header
import retrofit2.http.Path
import retrofit2.http.Query

interface FootballProInterface {
    @GET("fixtures/date/{date}")
    suspend fun getFixturesByDate(
        @Header("X-RapidAPI-Key") apiKey: String,
        @Header("X-RapidAPI-Host") host: String = "football-pro.p.rapidapi.com",
        @Path("date") date: String,
        @Query("include") include: String = "participants,lineups,scores,events,league,statistics"
    ): SportmonksResponse

    @GET("teams/search/{name}")
    suspend fun searchParticipants(
        @Header("X-RapidAPI-Key") apiKey: String,
        @Header("X-RapidAPI-Host") host: String = "football-pro.p.rapidapi.com",
        @Path("name") name: String
    ): SportmonksParticipantResponse

    @GET("fixtures/between/{from}/{to}/{participantId}")
    suspend fun getFixturesByParticipant(
        @Header("X-RapidAPI-Key") apiKey: String,
        @Header("X-RapidAPI-Host") host: String = "football-pro.p.rapidapi.com",
        @Path("from") from: String,
        @Path("to") to: String,
        @Path("participantId") participantId: Int,
        @Query("include") include: String = "participants,lineups,scores,events,league,statistics"
    ): SportmonksResponse

    @GET("fixtures/{id}")
    suspend fun getFixtureById(
        @Header("X-RapidAPI-Key") apiKey: String,
        @Header("X-RapidAPI-Host") host: String = "football-pro.p.rapidapi.com",
        @Path("id") id: Int,
        @Query("include") include: String = "participants,lineups,scores,events,league,statistics"
    ): SportmonksSingleResponse
}
