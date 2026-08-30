package com.pixelperfect.fotty.core.network.resolver

import com.pixelperfect.fotty.core.network.models.streaming.HealthStatus
import com.pixelperfect.fotty.core.network.models.streaming.StreamSource
import com.pixelperfect.fotty.core.network.models.streaming.StreamType
import javax.inject.Inject
import javax.inject.Singleton

@Singleton
class StreamResolver @Inject constructor() {

    /**
     * Ranks and selects the best available stream source.
     */
    fun resolvePreferredSource(sources: List<StreamSource>): StreamSource? {
        if (sources.isEmpty()) return null

        return sources.sortedWith(compareByDescending<StreamSource> { 
            // 1. Health first
            when (it.healthStatus) {
                HealthStatus.EXCELLENT -> 50
                HealthStatus.GOOD -> 40
                HealthStatus.FAIR -> 30
                HealthStatus.POOR -> 10
                HealthStatus.UNKNOWN -> 20
                HealthStatus.DEAD -> 0
            }
        }.thenByDescending { 
            // 2. Preferred flag
            if (it.isPreferred) 1 else 0
        }.thenByDescending { 
            // 3. P2P is generally higher quality if healthy
            if (it.type == StreamType.P2P) 1 else 0
        }).firstOrNull()
    }

    /**
     * Returns alternate sources if the primary one fails.
     */
    fun getFallbackSources(primary: StreamSource, all: List<StreamSource>): List<StreamSource> {
        return all.filter { it.id != primary.id }
            .sortedByDescending { 
                if (it.type != primary.type) 1 else 0 // Prefer different types for fallbacks
            }
    }
}
