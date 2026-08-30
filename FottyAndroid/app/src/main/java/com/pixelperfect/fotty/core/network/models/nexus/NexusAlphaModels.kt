package com.pixelperfect.fotty.core.network.models.nexus

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable

@Serializable
data class NexusALiveResponse(
    val matches: List<NexusAEvent>? = null
)

@Serializable
data class NexusAEvent(
    val id: String? = null,
    val title: String? = null,
    val category: String? = null,
    val date: Long? = null,
    val poster: String? = null,
    val popular: Boolean? = null,
    val teams: NexusATeams? = null,
    val sources: List<NexusASource>? = null
)

@Serializable
data class NexusATeams(
    val home: NexusATeam? = null,
    val away: NexusATeam? = null
)

@Serializable
data class NexusATeam(
    val name: String? = null,
    val badge: String? = null
)

@Serializable
data class NexusASource(
    val id: String,
    val source: String
)

@Serializable
data class NexusAVariant(
    @SerialName("streamNo") val streamNo: Int? = null,
    val language: String? = null,
    val hd: Boolean? = null,
    val embedUrl: String? = null,
    val source: String? = null,
    @SerialName("heatTier") val heatTier: String? = null
)
