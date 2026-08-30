package com.pixelperfect.fotty.features.player.viewmodel

import android.content.Context
import android.util.Log
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.pixelperfect.fotty.core.extractors.LiveSportsExtractor
import com.pixelperfect.fotty.core.network.models.streaming.StreamSource
import com.pixelperfect.fotty.data.providers.P2PProvider
import com.pixelperfect.fotty.core.network.resolver.LocalStreamProxy
import com.pixelperfect.fotty.core.networking.StreamNetworkExtractor
import dagger.hilt.android.qualifiers.ApplicationContext
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.*
import java.text.Normalizer
import java.util.Locale
import javax.inject.Inject

@HiltViewModel
class PlayerViewModel @Inject constructor(
    @ApplicationContext private val appContext: Context,
    private val p2pProvider: com.pixelperfect.fotty.data.providers.P2PProvider,
    private val footballRepository: com.pixelperfect.fotty.core.network.repository.football.FootballRepository,
    private val localProxy: LocalStreamProxy,
    val securityManager: com.pixelperfect.fotty.core.util.AppSecurityManager
) : ViewModel() {

    var playerState by mutableStateOf<PlayerState>(PlayerState.Idle)
        private set

    var intelligenceState by mutableStateOf(IntelligenceState())
        private set

    var sources by mutableStateOf<List<StreamSource>>(emptyList())
        private set

    var selectedSourceIndex by mutableIntStateOf(0)
        private set

    var selectedSource by mutableStateOf<StreamSource?>(null)
        private set

    var globalP2PSources by mutableStateOf<List<StreamSource>>(emptyList())
        private set
    
    var isFetchingGlobalP2P by mutableStateOf(false)
        private set

    var diagnostics by mutableStateOf(DiagnosticInfo())
        private set

    private var preResolvedSource by mutableStateOf<StreamSource?>(null)

    private var lastSourceSwitchAtMillis: Long = 0L
    private val failedAutoFailoverUrls = linkedSetOf<String>()
    
    // Watchdog State
    private var watchdogJob: kotlinx.coroutines.Job? = null
    private var stallRefreshAttempts = mutableMapOf<String, Int>()

    init {
        localProxy.start()
        fetchGlobalP2PChannels()
    }

    fun fetchGlobalP2PChannels() {
        viewModelScope.launch {
            isFetchingGlobalP2P = true
            try {
                // Fetch ALL available P2P channels for manual browsing (Antenna mode)
                val channels = withContext(Dispatchers.IO) {
                    p2pProvider.findStreams(
                        com.pixelperfect.fotty.core.network.models.streaming.SportEvent(
                            id = "catalog",
                            title = "Global Catalog",
                            category = "football",
                            participants = emptyList(),
                            timestamp = 0L
                        )
                    )
                }
                globalP2PSources = channels
            } catch (e: Exception) {
                Log.e(TAG, "Failed to fetch global P2P channels: ${e.message}")
            } finally {
                isFetchingGlobalP2P = false
            }
        }
    }

    override fun onCleared() {
        super.onCleared()
        localProxy.stop()
        watchdogJob?.cancel()
    }

    fun resolveLiveStream(
        matchId: String,
        homeTeam: String = "",
        awayTeam: String = "",
        sourceHints: List<LiveSportsExtractor.StreamexSource> = emptyList()
    ) {
        viewModelScope.launch {
            Log.d(TAG, "Resolving live stream for matchId: $matchId | title: $homeTeam vs $awayTeam")
            playerState = PlayerState.Resolving
            intelligenceState = IntelligenceState()
            sources = emptyList()
            selectedSource = null
            selectedSourceIndex = 0
            failedAutoFailoverUrls.clear()
            stallRefreshAttempts.clear()

            // iOS PARITY: Fetch Match Events for Timeline
            launch {
                try {
                    val numericId = matchId.substringAfter("nexus-").substringAfter("fd-").toIntOrNull()
                    if (numericId != null) {
                        val events = footballRepository.getMatchEvents(numericId)
                        intelligenceState = intelligenceState.copy(events = events)
                    }
                } catch (e: Exception) {
                    Log.e(TAG, "Failed to fetch timeline events: ${e.message}")
                }
            }

            Log.d(TAG, "==== STREAM RESOLUTION START ====")
            
            try {
                if (securityManager.isSafeModeActive.value) {
                    playerState = PlayerState.Error("Broadcast intelligence nodes are currently undergoing maintenance in your region.")
                    return@launch
                }

                // Phase 1: Resolve from tapped hints + cached snapshot first.
                val cachedMatches = LiveSportsExtractor.snapshotCachedEvents()
                val cachedLookup = MatchMatcher.mapBestMatch(cachedMatches, matchId, homeTeam, awayTeam)
                val hintedMatch = MatchMatcher.buildHintedMatch(matchId, homeTeam, awayTeam, sourceHints, cachedLookup.match, true)
                
                var match = hintedMatch ?: cachedLookup.match
                var catalogBackfillDeferred: Deferred<FullCatalogBackfillResult?>? = null

                if (match == null || match.sources.isNullOrEmpty()) {
                    match = MatchMatcher.buildTeamFallbackMatch(matchId, homeTeam, awayTeam)
                    catalogBackfillDeferred = async {
                        val fetchedMatches = runCatching { LiveSportsExtractor.fetchLiveEvents() }.getOrDefault(emptyList())
                        val mergedPool = MatchMatcher.dedupeMatchesByStableId(fetchedMatches + cachedMatches)
                        val fetchedLookup = MatchMatcher.mapBestMatch(mergedPool, matchId, homeTeam, awayTeam)
                        FullCatalogBackfillResult(
                            match = MatchMatcher.buildHintedMatch(matchId, homeTeam, awayTeam, sourceHints, fetchedLookup.match, true) ?: fetchedLookup.match,
                            mappedByRequestedId = fetchedLookup.mappedByRequestedId
                        )
                    }
                }

                val resolvedMatch = requireNotNull(match)
                diagnostics = DiagnosticInfo(
                    matchId = matchId, 
                    stableId = resolvedMatch.stableId, 
                    rawSourceCount = resolvedMatch.sources?.size ?: 0,
                    matchStatus = "LIVE"
                )

                val aceSourcesDeferred = async {
                    runCatching {
                        val home = resolvedMatch.homeName.ifBlank { homeTeam }
                        val away = resolvedMatch.awayName.ifBlank { awayTeam }
                        val event = com.pixelperfect.fotty.core.network.models.streaming.SportEvent(
                            id = matchId,
                            title = "$home vs $away",
                            category = resolvedMatch.category ?: "football",
                            participants = listOf(home, away),
                            timestamp = resolvedMatch.date ?: 0L
                        )
                        p2pProvider.findStreams(event)
                    }.getOrDefault(emptyList())
                }

                val candidates = runCatching { 
                    LiveSportsExtractor.findStreams(resolvedMatch.copy(sources = resolvedMatch.sources?.filterNot { it.source.equals("acestream", true) })) 
                }.getOrDefault(emptyList())
                
                val aceSources = withTimeoutOrNull(10_000) { dedupeSourcesByUrl(aceSourcesDeferred.await()) } ?: emptyList()
                
                val (instant, background) = candidates.partition { it.url.contains("P2P", true) || isLikelyLiveDirect(it.url) }
                val webFallback = background.map { it.copy(provider = "${it.provider} (Web)") }

                val merged = dedupeSourcesByUrl(aceSources + instant + webFallback)
                val labeled = sanitizeSourcesForDisplay(merged)
                Log.d(TAG, "Final merged sources: ${labeled.size}")
                if (labeled.isNotEmpty()) {
                    sources = labeled
                    Log.d(TAG, "Applying preferred selection...")
                    applyPreferredSelection(labeled)
                }

                // Phase 2: Background Resolution
                launch {
                    val resolved = withTimeoutOrNull(25_000) { resolvePlayableSources(background) } ?: emptyList()
                    val combined = dedupeSourcesByUrl(instant + resolved + webFallback + aceSources)
                    val labeledFinal = sanitizeSourcesForDisplay(combined)
                    sources = labeledFinal
                    applyPreferredSelection(labeledFinal)
                }

                // Start Watchdog
                startPlaybackWatchdog()

            } catch (e: Exception) {
                playerState = PlayerState.Error(e.localizedMessage ?: "Failed to resolve stream.")
            }
        }
    }

    private fun startPlaybackWatchdog() {
        watchdogJob?.cancel()
        watchdogJob = viewModelScope.launch {
            while (isActive) {
                delay(2000)
                val current = playerState
                if (current is PlayerState.PlaybackStalled) {
                    val url = current.source.url
                    val attempts = stallRefreshAttempts.getOrDefault(url, 0)
                    
                    if (attempts < 10) {
                        Log.w(TAG, "WATCHDOG: Recoverable stall detected. Attempt ${attempts + 1}/10 for ${current.source.provider}")
                        stallRefreshAttempts[url] = attempts + 1
                        
                        // Force a reload by re-emitting the same state but with a refreshed proxied URL
                        val source = current.source
                        playerState = PlayerState.Playback(source.copy(url = localProxy.getProxiedUrl(source.url)))
                    } else {
                        Log.e(TAG, "WATCHDOG: Source exhausted after 10 attempts. Triggering failover.")
                        tryNextSource("Source persistent failure")
                    }
                }
            }
        }
    }

    fun selectSource(index: Int) {
        if (!sources.indices.contains(index)) return
        Log.d(TAG, "Selecting source at index $index: ${sources[index].provider}")
        selectedSourceIndex = index
        selectedSource = sources[index]
        
        val originalSource = sources[index]
        val proxiedSource = originalSource.copy(url = localProxy.getProxiedUrl(originalSource.url))
        
        playerState = PlayerState.Playback(proxiedSource)
        prepareNextSourceHandshake()
    }

    fun selectGlobalSource(source: StreamSource) {
        selectedSource = source
        selectedSourceIndex = -1 // Indicates manual/catalog selection
        
        val proxiedSource = source.copy(url = localProxy.getProxiedUrl(source.url))
        playerState = PlayerState.Playback(proxiedSource)
    }

    fun tryNextSource(reason: String): Boolean {
        Log.w(TAG, "Source failover triggered: $reason")
        if (sources.size <= 1) {
            playerState = PlayerState.Error(reason, selectedSource)
            return false
        }

        val now = System.currentTimeMillis()
        if (now - lastSourceSwitchAtMillis < SOURCE_SWITCH_THROTTLE_MS) return false

        val current = selectedSourceIndex
        selectedSource?.url?.let { failedAutoFailoverUrls.add(it) }
        
        val traversalOrder = ((current + 1)..sources.lastIndex) + (0 until current)
        val next = traversalOrder.firstOrNull { index ->
            val url = sources[index].url
            url.isNotBlank() && !failedAutoFailoverUrls.contains(url)
        } ?: run {
            playerState = PlayerState.Error(reason, selectedSource)
            return false
        }

        selectedSourceIndex = next
        selectedSource = sources[next]
        lastSourceSwitchAtMillis = now
        
        val originalSource = sources[next]
        val proxiedSource = originalSource.copy(url = localProxy.getProxiedUrl(originalSource.url))
        
        playerState = PlayerState.Playback(proxiedSource)
        prepareNextSourceHandshake()
        return true
    }

    private fun prepareNextSourceHandshake() {
        val current = selectedSourceIndex
        val nextIndex = sources.indices.firstOrNull { it != current && !failedAutoFailoverUrls.contains(sources[it].url) } ?: return
        val nextSource = sources[nextIndex]
        
        if (isLikelyLiveDirect(nextSource.url)) {
            preResolvedSource = nextSource
            return
        }

        viewModelScope.launch {
            val extractor = StreamNetworkExtractor(appContext)
            val extracted = runCatching { extractor.extractSources(nextSource.url, nextSource.url, nextSource.provider, 15) }.getOrDefault(emptyList())
            preResolvedSource = extracted.find { isLikelyLiveDirect(it.url) }
        }
    }

    fun onPlaybackStalled(source: StreamSource) {
        if (playerState is PlayerState.Playback) {
            playerState = PlayerState.PlaybackStalled(source)
        }
    }

    fun onPlaybackResumed() {
        val current = playerState
        if (current is PlayerState.PlaybackStalled) {
            playerState = PlayerState.Playback(current.source)
            stallRefreshAttempts.remove(current.source.url)
        }
    }

    private fun sanitizeSourcesForDisplay(input: List<StreamSource>): List<StreamSource> {
        return input.mapIndexed { index, source ->
            val sanitizedProvider = when {
                source.provider.contains("acestream", true) -> "P2P Network Node"
                source.provider.contains("StreameX", true) -> "Global Media Node"
                else -> "Network Link"
            }
            source.copy(provider = "$sanitizedProvider #${index + 1}")
        }
    }

    private suspend fun resolvePlayableSources(candidates: List<StreamSource>): List<StreamSource> = coroutineScope {
        val extractor = StreamNetworkExtractor(appContext)
        val playable = mutableListOf<StreamSource>()
        candidates.chunked(4).forEach { chunk ->
            val jobs = chunk.map { candidate ->
                async {
                    Log.d(TAG, "Resolving playable sources for candidate: ${candidate.provider} | URL: ${candidate.url}")
                    if (isLikelyLiveDirect(candidate.url)) return@async listOf(candidate)
                    val extracted = runCatching { extractor.extractSources(candidate.url, candidate.url, candidate.provider, 10) }.getOrDefault(emptyList())
                    Log.d(TAG, "Extracted ${extracted.size} sources from ${candidate.url}")
                    extracted.filter { isLikelyLiveDirect(it.url) } + candidate.copy(provider = "${candidate.provider} (Web)")
                }
            }
            jobs.forEach { playable += it.await() }
        }
        playable.distinctBy { it.url }.sortedByDescending { isLikelyLiveDirect(it.url) }
    }

    private fun isLikelyLiveDirect(url: String): Boolean {
        val lower = url.lowercase(Locale.US)
        return lower.contains(".m3u8") || lower.contains(".mpd") || lower.contains("/proxy/acestream") || lower.contains("/ace/getstream")
    }

    private fun dedupeSourcesByUrl(input: List<StreamSource>): List<StreamSource> = input.distinctBy { it.url.trim() }

    private fun applyPreferredSelection(updatedSources: List<StreamSource>) {
        if (updatedSources.isEmpty()) return
        val preferred = updatedSources.indexOfFirst { isLikelyLiveDirect(it.url) }.coerceAtLeast(0)
        selectedSourceIndex = preferred
        selectedSource = updatedSources[preferred]
        
        val originalSource = updatedSources[preferred]
        val proxiedSource = originalSource.copy(url = localProxy.getProxiedUrl(originalSource.url))
        playerState = PlayerState.Playback(proxiedSource)
    }

    fun toggleIntelligence() {
        intelligenceState = intelligenceState.copy(isVisible = !intelligenceState.isVisible)
    }

    fun reset() {
        sources = emptyList()
        selectedSource = null
        selectedSourceIndex = 0
        playerState = PlayerState.Idle
        intelligenceState = IntelligenceState()
        failedAutoFailoverUrls.clear()
        stallRefreshAttempts.clear()
    }

    companion object {
        private const val TAG = "PlayerViewModel"
        private const val SOURCE_SWITCH_THROTTLE_MS = 5000L
    }
}
