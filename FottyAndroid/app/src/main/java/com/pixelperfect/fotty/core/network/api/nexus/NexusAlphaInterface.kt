package com.pixelperfect.fotty.core.network.api.nexus

import com.pixelperfect.fotty.core.network.models.nexus.NexusALiveResponse
import com.pixelperfect.fotty.core.network.models.nexus.NexusAEvent
import com.pixelperfect.fotty.core.network.models.nexus.NexusAVariant
import retrofit2.http.GET
import retrofit2.http.Header
import retrofit2.http.Path
import retrofit2.http.Url

interface NexusAlphaInterface {

    @GET
    suspend fun getLiveEvents(
        @Url url: String,
        @Header("User-Agent") userAgent: String = "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X)",
        @Header("Referer") referer: String? = null
    ): List<NexusAEvent>

    @GET
    suspend fun getLiveResponse(
        @Url url: String,
        @Header("User-Agent") userAgent: String = "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X)",
        @Header("Referer") referer: String? = null
    ): NexusALiveResponse

    @GET
    suspend fun getStreamVariants(
        @Url url: String,
        @Header("User-Agent") userAgent: String = "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X)",
        @Header("Referer") referer: String? = null
    ): List<NexusAVariant>

    @GET
    suspend fun getLiveResponseRaw(
        @Url url: String,
        @Header("User-Agent") userAgent: String = "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X)",
        @Header("Referer") referer: String? = null
    ): okhttp3.ResponseBody
}
