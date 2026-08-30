package com.pixelperfect.fotty.core.network.resolver

import android.util.Log
import com.pixelperfect.fotty.core.network.models.nexus.NexusAEvent
import com.pixelperfect.fotty.core.network.models.streaming.StreamSource
import com.pixelperfect.fotty.data.repositories.MatchRepository
import com.pixelperfect.fotty.data.repositories.StreamRepository
import kotlinx.coroutines.*
import javax.inject.Inject
import javax.inject.Singleton

@Singleton
class HybridStreamProvider @Inject constructor(
    private val matchRepository: MatchRepository,
    private val streamRepository: StreamRepository,
    private val diagnostics: StreamDiagnosticsEngine
) {
    private val webTimeout = 12_000L

    /**
     * Resolves the prioritized list of streams (Fast Web + P2P Backup Concurrently).
     * Mirrors iOS HybridStreamProvider.swift logic.
     */
    suspend fun resolvePrioritizedSources(event: NexusAEvent): List<StreamSource> = withContext(Dispatchers.IO) {
        val attemptId = java.util.UUID.randomUUID().toString()
        diagnostics.startNewAttempt(attemptId, event.title ?: "Unknown Event")
        
        Log.d("HybridPlayer", "Resolving prioritized sources for: ${event.title}")
        diagnostics.recordEvent("Resolution Started", "Beginning concurrent discovery")

        val webDeferred = async {
            try {
                diagnostics.recordEvent("Web Path Started", "Targeting high-quality feeds")
                withTimeout(webTimeout) {
                    attemptWebPriority(event)
                }
            } catch (e: Exception) {
                diagnostics.recordError("Web Path Failed", "Timeout or resolution error", e)
                emptyList<StreamSource>()
            }
        }

        val p2pDeferred = async {
            try {
                diagnostics.recordEvent("P2P Path Started", "Targeting AceStream swarm")
                attemptP2PPriority(event)
            } catch (e: Exception) {
                diagnostics.recordError("P2P Path Failed", "Handshake or peer discovery error", e)
                emptyList<StreamSource>()
            }
        }

        // Fetch both concurrently
        val webSources = try { webDeferred.await() } catch (e: Exception) { emptyList() }
        val p2pSources = try { p2pDeferred.await() } catch (e: Exception) { emptyList() }

        diagnostics.recordEvent("Discovery Results", "Web(${webSources.size}), P2P(${p2pSources.size})")

        // Interleave P2P and Web sources for maximum reliability
        val total = combineWebAndP2P(webSources, p2pSources)
        diagnostics.recordEvent("Resolution Complete", "Final list size: ${total.size}")
        return@withContext total
    }

    private fun combineWebAndP2P(web: List<StreamSource>, p2p: List<StreamSource>): List<StreamSource> {
        val w = deduplicated(web)
        val p = deduplicated(p2p)
        if (w.isEmpty() || p.isEmpty()) return deduplicated(w + p)
        
        return deduplicated(interleaveWebWithPairedP2P(w, p))
    }

    private fun interleaveWebWithPairedP2P(web: List<StreamSource>, p2p: List<StreamSource>): List<StreamSource> {
        val webOrdered = sortStreamexFirst(web)
        val p2pSorted = p2p.sortedByDescending { it.healthScore }
        
        val buckets = Array(webOrdered.size) { mutableListOf<StreamSource>() }
        
        for (source in p2pSorted) {
            val idx = bestWebAnchorIndex(source, webOrdered)
            buckets[idx].add(tagP2PWithWebAnchor(source, webOrdered[idx]))
        }
        
        val out = mutableListOf<StreamSource>()
        for (i in webOrdered.indices) {
            out.add(webOrdered[i])
            out.addAll(buckets[i])
        }
        return out
    }

    private fun sortStreamexFirst(web: List<StreamSource>): List<StreamSource> {
        return web.sortedWith(compareByDescending<StreamSource> { isLikelyStreamexFeed(it) }.thenBy { it.provider })
    }

    private fun isLikelyStreamexFeed(source: StreamSource): Boolean {
        val url = source.url.lowercase()
        if (url.contains("streamex")) return true
        val cat = source.headers["X-Fotty-Nexus-Catalog"]?.lowercase() ?: ""
        return cat.contains("streamex") || cat.contains("nexus alpha")
    }

    private fun bestWebAnchorIndex(p2p: StreamSource, web: List<StreamSource>): Int {
        val label = p2p.label
        val pr = bracketRegionTag(label)
        if (pr != null) {
            val idx = web.indexOfFirst { webRegionHint(it) == pr }
            if (idx != -1) return idx
        }
        
        val streamexIdx = web.indexOfFirst { isLikelyStreamexFeed(it) }
        return if (streamexIdx != -1) streamexIdx else 0
    }

    private fun bracketRegionTag(label: String): String? {
        val open = label.lastIndexOf("[")
        val close = label.lastIndexOf("]")
        if (open == -1 || close == -1 || open >= close) return null
        val inner = label.substring(open + 1, close).trim().uppercase()
        if (inner.length in 2..4 && inner.all { it.isLetter() }) return inner
        return null
    }

    private fun webRegionHint(source: StreamSource): String? {
        val t = source.label
        bracketRegionTag(t)?.let { return it }
        bracketRegionTag(source.provider)?.let { return it }
        
        val host = android.net.Uri.parse(source.url).host?.lowercase() ?: ""
        return when {
            host.endsWith(".co.uk") || host.contains(".uk.") -> "UK"
            host.endsWith(".com.au") -> "AU"
            host.endsWith(".ie") -> "IE"
            else -> null
        }
    }

    private fun tagP2PWithWebAnchor(p2p: StreamSource, anchor: StreamSource): StreamSource {
        val newHeaders = p2p.headers.toMutableMap().apply {
            put("X-Fotty-Paired-Web-Provider", anchor.provider)
            put("X-Fotty-Paired-Web-Host", android.net.Uri.parse(anchor.url).host ?: "")
        }
        return p2p.copy(headers = newHeaders)
    }

    private fun deduplicated(sources: List<StreamSource>): List<StreamSource> {
        val seenCanonicalURLs = mutableSetOf<String>()
        return sources.filter { source ->
            val canonical = if (source.isP2P) {
                source.url // Keep full URL string for P2P
            } else {
                // Strip query params for web sources to prevent token-based duplicates
                source.url.substringBefore("?")
            }
            seenCanonicalURLs.add(canonical)
        }
    }

    private suspend fun attemptWebPriority(event: NexusAEvent): List<StreamSource> {
        val directSources = matchRepository.getStreamsForEvent(event.id ?: "").filter { source -> !isP2PSource(source) }
        
        if (directSources.isNotEmpty()) {
            return directSources
        }

        // DEEP RESOLUTION: Parity with iOS logic
        val home = event.teams?.home?.name ?: ""
        val away = event.teams?.away?.name ?: ""
        
        val resolvedId = matchRepository.findNexusMatchIdByTeams(home, away)
        
        return if (resolvedId != null) {
            matchRepository.getStreamsForEvent(resolvedId).filter { !isP2PSource(it) }
        } else {
            emptyList()
        }
    }

    private suspend fun attemptP2PPriority(event: NexusAEvent): List<StreamSource> {
        return matchRepository.getP2PStreams(
            eventId = event.id ?: "",
            homeTeam = event.teams?.home?.name ?: "",
            awayTeam = event.teams?.away?.name ?: "",
            category = event.category ?: ""
        )
    }

    private fun isP2PSource(source: StreamSource): Boolean {
        val url = source.url.lowercase()
        return url.contains(":6878") || url.contains("/proxy/acestream/") || url.contains("acestream://")
    }

    /**
     * The 'Pre-Warm' Pattern: Silently monitor P2P health while Web is playing.
     */
    fun prewarmP2P(event: NexusAEvent, scope: CoroutineScope) {
        scope.launch(Dispatchers.IO) {
            try {
                attemptP2PPriority(event)
            } catch (_: Exception) {}
        }
    }
}
