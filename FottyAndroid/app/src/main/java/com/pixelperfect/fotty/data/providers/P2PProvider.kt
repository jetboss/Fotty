package com.pixelperfect.fotty.data.providers

import android.util.Log
import com.pixelperfect.fotty.core.network.api.p2p.P2PInterface
import com.pixelperfect.fotty.core.network.engine.p2p.EngineStatus
import com.pixelperfect.fotty.core.network.engine.p2p.P2PStreamEngine
import com.pixelperfect.fotty.core.network.models.p2p.*
import com.pixelperfect.fotty.core.network.models.streaming.*
import kotlinx.coroutines.*
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow
import okhttp3.OkHttpClient
import okhttp3.Request
import java.util.*
import javax.inject.Inject
import javax.inject.Singleton

@Singleton
class P2PProvider @Inject constructor(
    private val api: P2PInterface,
    private val okHttpClient: OkHttpClient
) : P2PStreamEngine, StreamingProvider {
    override val name: String = "P2P (AceStream)"
    override val priority: Int = 20

    private val TAG = "P2PProvider"
    private val SERVER_URL = "https://p2p.pixel-invoice.com"
    private val SCRAPER_URL = "https://scraper.pixel-invoice.com"
    private val API_PASSWORD = com.pixelperfect.fotty.core.Config.p2pApiPassword
    private val USER_AGENT = "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15"
    private val REFERER = "https://p2p.pixel-invoice.com/"

    private val maxReturnedSources = 20
    private val maxProbeAttempts = maxReturnedSources * 2
    private val minimumSegmentBytes = 512
    private val preflightReadLimitBytes = 4096

    private val _engineStatus = MutableStateFlow(EngineStatus(false, 0, 0, 0f))

    override suspend fun isHealthy(): Boolean {
        val request = Request.Builder()
            .url("$SERVER_URL/proxy/acestream/status?api_password=$API_PASSWORD")
            .header("Accept", "application/json")
            .build()
        return try {
            okHttpClient.newCall(request).execute().use { it.isSuccessful }
        } catch (e: Exception) {
            false
        }
    }

    override suspend fun ensureStarted() {
        _engineStatus.value = _engineStatus.value.copy(isRunning = true)
    }

    override suspend fun resolveStream(event: SportEvent, source: StreamSource): ResolvedStream {
        // Validation/Negotiation logic
        delay(500)
        return ResolvedStream(
            sourceId = source.id,
            playbackUrl = source.url,
            headers = mapOf(
                "User-Agent" to USER_AGENT,
                "Referer" to REFERER,
                "Authorization" to "Bearer $API_PASSWORD"
            ),
            streamType = StreamType.P2P
        )
    }

    override fun getEngineStatus(): Flow<EngineStatus> = _engineStatus.asStateFlow()

    override suspend fun stop() {
        _engineStatus.value = _engineStatus.value.copy(isRunning = false)
    }

    override suspend fun findStreams(event: SportEvent): List<StreamSource> {
        Log.d(TAG, "findStreams called for ${event.title}")
        return withContext(Dispatchers.IO) {
            try {
                val queries = mutableListOf<String>()
                queries.add("${event.title} ${event.category}")
                event.participants.forEach { queries.add("$it ${event.category}") }
                
                // Add first significant token for each participant as fallback
                event.participants.forEach { participant ->
                    val tokens = significantTokens(participant)
                    if (tokens.isNotEmpty()) {
                        queries.add("${tokens.first()} ${event.category}")
                    }
                }
                
                val candidates = coroutineScope {
                    val deferreds = mutableListOf<Deferred<List<ScrapedAceMatch>>>()
                    Log.d(TAG, "Fetching global matches from scraper...")
                    deferreds.add(async {
                        try { 
                            val res = api.getMatches("Bearer $API_PASSWORD")
                            Log.d(TAG, "getMatches returned ${res.size} items")
                            res
                        } catch (e: Exception) { 
                            Log.e(TAG, "getMatches failed: ${e.message}")
                            emptyList() 
                        }
                    })
                    for (query in queries) {
                        Log.d(TAG, "Searching scraper for: $query")
                        deferreds.add(async {
                            try { 
                                val res = api.searchMatches(query, "Bearer $API_PASSWORD")
                                Log.d(TAG, "searchMatches('$query') returned ${res.size} items")
                                res
                            } catch (e: Exception) { 
                                Log.e(TAG, "searchMatches('$query') failed: ${e.message}")
                                emptyList() 
                            }
                        })
                    }
                    val all = mutableListOf<ScrapedAceMatch>()
                    val seen = mutableSetOf<String>()
                    deferreds.awaitAll().flatten().forEach { match ->
                        if (seen.add(match.cid)) {
                            all.add(match)
                        }
                    }
                    Log.d(TAG, "Total unique P2P candidates: ${all.size}")
                    all
                }

                val matchingCandidates = candidates.filter { matchesContext(it, event) }
                Log.d(TAG, "Discovery found ${candidates.size} total candidates, ${matchingCandidates.size} matching context")
                
                if (candidates.isNotEmpty()) {
                    Log.d(TAG, "CANDIDATE SAMPLE (First 20):")
                    candidates.take(20).forEach { Log.d(TAG, "  - ${it.title} (cid: ${it.cid.take(8)}...)") }
                }

                if (matchingCandidates.isNotEmpty()) {
                    Log.d(TAG, "✅ Found ${matchingCandidates.size} P2P matches! Probing...")
                    return@withContext preflightAndBuildSources(matchingCandidates, event.id, SourceScope.EXACT_MATCH)
                }
                Log.w(TAG, "No P2P candidates matched event: ${event.title}")
                emptyList()
            } catch (e: Exception) {
                Log.e(TAG, "P2P discovery failed: ${e.message}")
                emptyList()
            }
        }
    }

    private suspend fun preflightAndBuildSources(
        matches: List<ScrapedAceMatch>, 
        eventId: String,
        scope: SourceScope
    ): List<StreamSource> {
        val sorted = matches.sortedByDescending { it.availability ?: 0f }
        val healthy = mutableListOf<HealthyP2PSource>()
        
        for (match in sorted.take(maxProbeAttempts)) {
            val candidate = makeCandidate(match) ?: continue
            val outcome = preflight(candidate)
            if (outcome is ProbeOutcome.Success) {
                healthy.add(outcome.value)
                if (healthy.size >= scope.maxHealthySources) break
            }
        }

        healthy.sortByDescending { it.probeScore }
        return healthy.map { buildStreamSource(it, eventId, scope) }
    }

    private fun makeCandidate(match: ScrapedAceMatch): P2PCandidate? {
        val url = "$SERVER_URL/proxy/acestream/manifest.m3u8?infohash=${match.cid}&api_password=$API_PASSWORD"
        return P2PCandidate(
            cid = match.cid,
            title = match.title,
            availability = match.availability ?: 0f,
            streamUrl = url
        )
    }

    private suspend fun preflight(candidate: P2PCandidate): ProbeOutcome {
        return try {
            val start = System.currentTimeMillis()
            val request = Request.Builder()
                .url(candidate.streamUrl)
                .header("User-Agent", USER_AGENT)
                .header("Referer", REFERER)
                .header("Range", "bytes=0-${preflightReadLimitBytes - 1}")
                .build()

            okHttpClient.newCall(request).execute().use { response ->
                val ttfb = (System.currentTimeMillis() - start).toInt()
                if (!response.isSuccessful) return ProbeOutcome.Failure("HTTP ${response.code}")

                val stream = response.body?.byteStream()
                val probeBuffer = ByteArray(preflightReadLimitBytes)
                val bytesRead = stream?.read(probeBuffer)?.coerceAtLeast(0) ?: 0
                
                if (bytesRead < minimumSegmentBytes) return ProbeOutcome.Failure("Empty stream")

                ProbeOutcome.Success(
                    HealthyP2PSource(
                        cid = candidate.cid,
                        title = candidate.title,
                        availability = candidate.availability,
                        streamUrl = candidate.streamUrl,
                        manifestTTFBMs = ttfb,
                        segmentStatusCode = 200,
                        segmentBytes = bytesRead,
                        probeScore = (10000 - ttfb).coerceAtLeast(0),
                        failureClass = "ok",
                        activePeers = null
                    )
                )
            }
        } catch (e: Exception) {
            ProbeOutcome.Failure(e.message ?: "Unknown")
        }
    }

    private fun buildStreamSource(healthy: HealthyP2PSource, eventId: String, scope: SourceScope): StreamSource {
        return StreamSource(
            id = healthy.cid,
            eventId = eventId,
            url = healthy.streamUrl,
            provider = name,
            type = StreamType.P2P,
            label = healthy.title,
            qualityLabel = scope.qualityLabel,
            healthStatus = when {
                healthy.probeScore > 8000 -> HealthStatus.EXCELLENT
                healthy.probeScore > 6000 -> HealthStatus.GOOD
                healthy.probeScore > 4000 -> HealthStatus.FAIR
                else -> HealthStatus.POOR
            },
            headers = mapOf(
                "User-Agent" to USER_AGENT,
                "Referer" to REFERER,
                "Authorization" to "Bearer $API_PASSWORD"
            ),
            mimeType = "application/x-mpegURL"
        )
    }

    private fun matchesContext(match: ScrapedAceMatch, event: SportEvent): Boolean {
        val title = match.title.lowercase()
        val eventTokens = significantTokens(event.title)
        val participantTokens = event.participants.flatMap { significantTokens(it) }
        val allSearchTokens = (eventTokens + participantTokens).filter { it.length >= 3 }
        
        // Looser matching: if any significant token is found in the title
        val matches = allSearchTokens.any { title.contains(it) }
        
        if (matches) {
            Log.d(TAG, "✅ Match: '$title' matches tokens $allSearchTokens")
        }
        return matches
    }

    private fun significantTokens(name: String): Set<String> {
        val weakTokens = setOf(
            "the", "and", "club", "team", "fc", "cf", "sc", "ac", "afc", "bc", "u19", "u20",
            "u21", "women", "woman", "men", "united", "state", "new", "real", "sporting",
            "athletic", "athletico", "college", "university"
        )
        return name.lowercase()
            .split(Regex("[^a-zA-Z0-9]+"))
            .filter { it.length >= 3 && !weakTokens.contains(it) }
            .toSet()
    }

    private enum class SourceScope(val qualityLabel: String, val headerValue: String, val maxHealthySources: Int) {
        EXACT_MATCH("P2P HD", "exact-match", 8),
        SPORT_CHANNEL("P2P Channel HD", "sport-channel", 3),
        CATALOG("P2P HD", "catalog", 20)
    }

    private sealed interface ProbeOutcome {
        data class Success(val value: HealthyP2PSource) : ProbeOutcome
        data class Failure(val reason: String) : ProbeOutcome
    }
}
