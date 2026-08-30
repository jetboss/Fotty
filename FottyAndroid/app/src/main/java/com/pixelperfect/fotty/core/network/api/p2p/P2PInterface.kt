package com.pixelperfect.fotty.core.network.api.p2p

import com.pixelperfect.fotty.core.network.models.p2p.ScrapedAceMatch
import retrofit2.http.GET
import retrofit2.http.Header
import retrofit2.http.Path

interface P2PInterface {

    @GET("matches")
    suspend fun getMatches(
        @Header("Authorization") auth: String
    ): List<ScrapedAceMatch>

    @GET("search/{query}")
    suspend fun searchMatches(
        @Path("query") query: String,
        @Header("Authorization") auth: String
    ): List<ScrapedAceMatch>
}
