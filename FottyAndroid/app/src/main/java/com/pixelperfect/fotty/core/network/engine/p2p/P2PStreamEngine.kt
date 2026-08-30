package com.pixelperfect.fotty.core.network.engine.p2p

import com.pixelperfect.fotty.core.network.models.streaming.ResolvedStream
import com.pixelperfect.fotty.core.network.models.streaming.SportEvent
import com.pixelperfect.fotty.core.network.models.streaming.StreamSource
import kotlinx.coroutines.flow.Flow

interface P2PStreamEngine {
    /**
     * Checks if the P2P engine is healthy and ready to resolve streams.
     */
    suspend fun isHealthy(): Boolean

    /**
     * Starts the P2P engine if it's not already running.
     */
    suspend fun ensureStarted()

    /**
     * Resolves a generic [SportEvent] and [StreamSource] into a [ResolvedStream].
     * This handles the core P2P negotiation and returns a playable URL (local or remote).
     */
    suspend fun resolveStream(event: SportEvent, source: StreamSource): ResolvedStream

    /**
     * Returns a Flow of engine status (e.g., number of peers, buffer percentage).
     */
    fun getEngineStatus(): Flow<EngineStatus>

    /**
     * Stops any active stream resolution and releases engine resources if appropriate.
     */
    suspend fun stop()
}

data class EngineStatus(
    val isRunning: Boolean,
    val activePeers: Int,
    val downloadSpeed: Long,
    val bufferPercentage: Float,
    val message: String? = null
)
