package com.pixelperfect.fotty.core.network.models.p2p

import kotlinx.serialization.Serializable

@Serializable
data class ScrapedAceMatch(
    val cid: String,
    val title: String,
    val availability: Float? = null,
    val language: String? = null,
    val quality: String? = null,
    val active_peers: Int? = null
)

@Serializable
data class ProxyFailureEnvelope(
    val code: String? = null,
    val detail: String? = null,
    val active_peers: Int? = null
)

data class P2PCandidate(
    val cid: String,
    val title: String,
    val availability: Float,
    val streamUrl: String
)

data class HealthyP2PSource(
    val cid: String,
    val title: String,
    val availability: Float,
    val streamUrl: String,
    val manifestTTFBMs: Int,
    val segmentStatusCode: Int,
    val segmentBytes: Int,
    val probeScore: Int,
    val failureClass: String,
    val activePeers: Int?
)
