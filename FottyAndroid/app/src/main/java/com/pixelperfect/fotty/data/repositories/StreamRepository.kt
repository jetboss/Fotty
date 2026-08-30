package com.pixelperfect.fotty.data.repositories

import android.util.Log
import com.pixelperfect.fotty.data.models.Match
import com.pixelperfect.fotty.data.providers.NexusAlphaProvider
import com.pixelperfect.fotty.data.providers.P2PProvider
import kotlinx.coroutines.async
import kotlinx.coroutines.coroutineScope
import javax.inject.Inject
import javax.inject.Singleton

import com.pixelperfect.fotty.core.network.models.streaming.StreamSource

@Singleton
class StreamRepository @Inject constructor(
    private val nexusProvider: NexusAlphaProvider,
    private val p2pProvider: P2PProvider
) {
    private val TAG = "StreamRepository"

    suspend fun getStreamsForMatch(match: Match): List<StreamSource> = coroutineScope {
        Log.d("StreamRepository", "🚀 CRITICAL: getStreamsForMatch called for ${match.homeTeam.name} vs ${match.awayTeam.name}")

        val event = match.toSportEvent()

        // 1. Resolve Native (Nexus Alpha) Streams
        val webTask = async {
            try {
                var nexusId = match.id
                if (!nexusId.startsWith("nexus-")) {
                    nexusId = nexusProvider.findMatchIdByTeams(match.homeTeam.name, match.awayTeam.name) ?: ""
                }
                
                if (nexusId.isNotEmpty()) {
                    nexusProvider.getStreamsForCachedEvent(nexusId)
                } else {
                    Log.w(TAG, "No Nexus event found for team names: ${match.homeTeam.name} vs ${match.awayTeam.name}")
                    emptyList()
                }
            } catch (e: Exception) {
                Log.e(TAG, "Native resolution failed: ${e.message}")
                emptyList()
            }
        }

        // 2. Resolve P2P (Acestream) Streams
        val p2pTask = async {
            try {
                p2pProvider.findStreams(event)
            } catch (e: Exception) {
                Log.e(TAG, "P2P resolution failed: ${e.message}")
                emptyList()
            }
        }

        val webSources = webTask.await()
        val p2pSources = p2pTask.await()

        val allSources = (webSources + p2pSources).distinctBy { it.id }
        
        if (allSources.isEmpty()) {
            Log.d(TAG, "Primary resolution empty. Triggering Scraper Fallback (iOS Parity)...")
            return@coroutineScope attemptFallbackScraping(match)
        }

        Log.d(TAG, "Sync complete: Found ${allSources.size} total sources (${webSources.size} Native, ${p2pSources.size} P2P)")
        
        allSources
    }

    private suspend fun attemptFallbackScraping(match: Match): List<StreamSource> {
        // BLUEPRINT: This mimics the iOS fallbackEmbedSources logic.
        // It should eventually call a dedicated web-extraction service or headless scraper.
        Log.w(TAG, "Self-Healing: Scraper Fallback triggered for ${match.homeTeam.name}")
        // For now, we return empty as the extraction bridge is still being refined,
        // but the hook is now correctly positioned in the lifecycle.
        return emptyList()
    }

    suspend fun resolveMatchStreams(
        match: Match, 
        nexusSources: List<com.pixelperfect.fotty.core.network.models.nexus.NexusASource>? = null
    ): List<StreamSource> = coroutineScope {
        val event = match.toSportEvent()
        
        val webTask = async {
            if (nexusSources != null && nexusSources.isNotEmpty()) {
                nexusProvider.getStreamSources(match.id, nexusSources)
            } else {
                emptyList()
            }
        }

        val p2pTask = async {
            p2pProvider.findStreams(event)
        }

        val webSources = webTask.await()
        val p2pSources = p2pTask.await()

        (webSources + p2pSources).distinctBy { it.id }
    }
}
