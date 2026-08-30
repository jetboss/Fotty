package com.pixelperfect.fotty.core.network.models.streaming

import kotlinx.serialization.Serializable

@Serializable
data class StreamSource(
    val id: String,
    val eventId: String,
    val url: String, // The actual playback URL or P2P identifier
    val provider: String, // The name of the source provider (e.g. "Nexus Alpha", "P2P")
    val type: StreamType,
    val label: String,
    val qualityLabel: String,
    val language: String = "en",
    val isPreferred: Boolean = false,
    val healthStatus: HealthStatus = HealthStatus.UNKNOWN,
    val activePeers: Int = 0,
    val healthScore: Int = 0, // 0-100 scale for precise parity
    val lastCheckedAt: Long = System.currentTimeMillis(),
    val headers: Map<String, String> = emptyMap(),
    val mimeType: String? = null,
    val fallbackUrls: List<String> = emptyList()
) {
    val isP2P: Boolean get() = type == StreamType.P2P
}

@Serializable
enum class StreamType {
    P2P, DIRECT, HLS, FALLBACK
}

@Serializable
enum class HealthStatus {
    EXCELLENT, GOOD, FAIR, POOR, DEAD, UNKNOWN
}

@Serializable
data class ResolvedStream(
    val sourceId: String,
    val playbackUrl: String,
    val headers: Map<String, String> = emptyMap(),
    val mimeType: String? = null,
    val streamType: StreamType,
    val expiresAt: Long? = null,
    val requiresRefresh: Boolean = false,
    val fallbackSources: List<String> = emptyList()
)

sealed class StreamState {
    object Idle : StreamState()
    object Resolving : StreamState()
    object Connecting : StreamState()
    object Buffering : StreamState()
    data class Playing(val stream: ResolvedStream) : StreamState()
    object Reconnecting : StreamState()
    data class Failed(val error: StreamError) : StreamState()
    object Ended : StreamState()
}

sealed class StreamError {
    object NoSourceFound : StreamError()
    object EngineUnavailable : StreamError()
    object ResolveFailed : StreamError()
    object Timeout : StreamError()
    object UnsupportedFormat : StreamError()
    object PlaybackFailed : StreamError()
    object NetworkError : StreamError()
    object ProviderBlocked : StreamError()
    data class Unknown(val message: String?) : StreamError()
}
