package com.pixelperfect.fotty.core.extractors

import android.util.Log
import com.pixelperfect.fotty.core.network.models.streaming.StreamSource
import com.pixelperfect.fotty.core.utils.SecurityUtils
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.async
import kotlinx.coroutines.awaitAll
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.decodeFromJsonElement
import kotlinx.serialization.json.booleanOrNull
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.intOrNull
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonPrimitive
import okhttp3.OkHttpClient
import okhttp3.Request
import java.text.Normalizer
import java.net.URI
import java.net.URLEncoder
import java.util.Locale
import java.util.concurrent.TimeUnit

object LiveSportsExtractor {
    private const val TAG = "LiveSportsExtractor"
    private const val EVENTS_CACHE_TTL_MS = 600_000L

    // Literal copy of iOS Safari User-Agent to bypass provider blocks
    private const val IOS_SAFARI_USER_AGENT = "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1"
    
    private const val MAX_STREAM_CANDIDATES = 12
    private val preferredSources = listOf("echo", "delta", "golf", "alpha", "admin")

    private val json = Json { ignoreUnknownKeys = true }
    private val streamClient = OkHttpClient.Builder()
        .connectTimeout(15, TimeUnit.SECONDS)
        .readTimeout(15, TimeUnit.SECONDS)
        .build()
    private val catalogClient = streamClient.newBuilder()
        .connectTimeout(4, TimeUnit.SECONDS)
        .readTimeout(6, TimeUnit.SECONDS)
        .callTimeout(8, TimeUnit.SECONDS)
        .build()
    @Volatile private var cachedEvents: List<StreamexMatch> = emptyList()
    @Volatile private var cachedEventsAtMillis: Long = 0L

    private data class LiveProvider(
        val label: String,
        val baseURL: String,
        val allMatchesPath: String = "/api/live/matches/all",
        val liveMatchesPath: String = "/api/live/matches/live",
        val upcomingMatchesPath: String = "/api/live/matches/upcoming",
        val streamPathPrefix: String = "/api/live/stream"
    )

    private val providers = listOf(
        LiveProvider(label = "StreameX", baseURL = SecurityUtils.decode("aHR0cHM6Ly93d3cuc3RyZWFtZXgubmV0")),
        LiveProvider(label = "StreameX Mirror", baseURL = SecurityUtils.decode("aHR0cHM6Ly9zdHJlYW1leC5zaA==")),
        LiveProvider(
            label = "Streamed Backup",
            baseURL = SecurityUtils.decode("aHR0cHM6Ly9zdHJlYW1lZC5waw=="),
            allMatchesPath = "/api/matches/all",
            liveMatchesPath = "/api/matches/live",
            upcomingMatchesPath = "/api/matches/upcoming",
            streamPathPrefix = "/api/stream"
        )
    )

    @Serializable
    data class StreamexMatch(
        val id: String? = null,
        val title: String? = null,
        val category: String? = null,
        val date: Long? = null,
        val poster: String? = null,
        val popular: Boolean? = null,
        val teams: StreamexTeams? = null,
        val sources: List<StreamexSource>? = null
    ) {
        val homeBadgeURL: String?
            get() = imageURL(teams?.home?.badge ?: splitTeams().first)

        val awayBadgeURL: String?
            get() = imageURL(teams?.away?.badge ?: splitTeams().second)

        private fun imageURL(raw: String?): String? {
            val badge = raw ?: return null
            if (badge.startsWith("/api/")) {
                return SecurityUtils.decode("aHR0cHM6Ly9zdHJlYW1lZC5waw==") + badge
            }
            return SecurityUtils.decode("aHR0cHM6Ly9zdHJlYW1lZC5waw==") + "/api/images/badge/$badge.webp"
        }

        val stableId: String
            get() {
                val explicit = id?.trim().orEmpty()
                if (explicit.isNotEmpty() && !explicit.startsWith("p2p-")) return explicit
                val baseTitle = title?.replace(" ", "-")?.lowercase() ?: "event"
                return "$baseTitle-${date ?: 0L}"
            }

        val normalizedCategory: String
            get() = normalizeCategory(category)

        val categoryDisplayName: String
            get() = categoryDisplayNameFor(normalizedCategory)

        val homeName: String
            get() = teams?.home?.name?.takeIf { it.isNotBlank() } ?: splitTeams().first

        val awayName: String
            get() = teams?.away?.name?.takeIf { it.isNotBlank() } ?: splitTeams().second

        val sourceCount: Int
            get() = sources?.size ?: 0

        val kickoffMillis: Long?
            get() {
                val value = date ?: return null
                if (value <= 0L) return null
                val normalized = if (value > 10_000_000_000L) value else value * 1_000L
                if (normalized < 946_684_800_000L) return null
                return normalized
            }

        private fun splitTeams(): Pair<String, String> {
            val cleanedTitle = title?.trim().orEmpty()
            if (cleanedTitle.isBlank()) return "Home" to "Away"
            val separators = listOf(" vs ", " v ", " @ ", " - ")
            for (separator in separators) {
                val parts = cleanedTitle.split(separator)
                if (parts.size == 2 && parts[0].isNotBlank() && parts[1].isNotBlank()) {
                    return parts[0].trim() to parts[1].trim()
                }
            }
            return cleanedTitle to "Away"
        }
    }

    @Serializable
    data class StreamexSource(val source: String, val id: String)

    @Serializable
    data class StreamexTeams(val home: StreamexTeam? = null, val away: StreamexTeam? = null)

    @Serializable
    data class StreamexTeam(val name: String? = null, val badge: String? = null)

    @Serializable
    private data class LiveStreamVariant(
        val streamNo: Int? = null,
        val language: String? = null,
        val hd: Boolean? = null,
        val embedUrl: String? = null,
        val source: String? = null,
        val heatTier: String? = null
    )

    private data class StreamCandidate(
        val sourceCode: String,
        val streamNo: Int,
        val language: String?,
        val isHD: Boolean,
        val heatTier: String?,
        val embedURL: String,
        val catalogProvider: String
    )

    /**
     * Exhaustive discovery that merges sources across multiple providers.
     */
    suspend fun fetchLiveEvents(): List<StreamexMatch> = coroutineScope {
        Log.d(TAG, "Fetching live events (Exhaustive Merger Mode)")
        val discoveryJobs = providers.map { provider ->
            async(Dispatchers.IO) { requestMatchesOnProvider(provider) }
        }
        
        val allMatches = discoveryJobs.awaitAll().flatten()
        
        // Final Union-based merge
        val deduped = mergeMatches(allMatches)
        val sorted = deduped.sortedWith(
            compareByDescending<StreamexMatch> { it.popular == true }
                .thenBy { it.kickoffMillis ?: Long.MAX_VALUE }
        )
        if (sorted.isNotEmpty()) {
            cacheEvents(sorted)
            return@coroutineScope sorted
        }

        val cached = readCachedEvents()
        if (cached.isNotEmpty()) {
            Log.w(TAG, "Using cached live events (${cached.size}) after empty upstream response.")
            return@coroutineScope cached
        }

        sorted
    }

    private fun mergeMatches(events: List<StreamexMatch>): List<StreamexMatch> {
        val deduped = LinkedHashMap<String, StreamexMatch>()
        for (event in events) {
            val key = event.stableId
            val existing = deduped[key]
            if (existing == null) {
                deduped[key] = event
            } else {
                // Combine sources from all providers
                val combined = (existing.sources.orEmpty() + event.sources.orEmpty()).distinctBy { "${it.source}|${it.id}" }
                deduped[key] = existing.copy(
                    sources = combined,
                    popular = existing.popular == true || event.popular == true,
                    // Keep the metadata (teams/badges) from whichever has it (prioritize StreameX)
                    teams = if (existing.teams != null) existing.teams else event.teams
                )
            }
        }
        return deduped.values.toList()
    }

    private suspend fun requestMatchesOnProvider(provider: LiveProvider): List<StreamexMatch> = coroutineScope {
        val startedAt = System.currentTimeMillis()
        val primary = requestMatches(provider, provider.allMatchesPath)
        if (primary.isNotEmpty()) {
            Log.d(
                TAG,
                "provider=${provider.label} path=${provider.allMatchesPath} matches=${primary.size} in ${System.currentTimeMillis() - startedAt}ms"
            )
            return@coroutineScope primary
        }

        // Match iOS fallback behavior: merge live + upcoming feeds when /all is empty.
        val liveDeferred = async(Dispatchers.IO) {
            requestMatches(provider, provider.liveMatchesPath)
        }
        val upcomingDeferred = async(Dispatchers.IO) {
            requestMatches(provider, provider.upcomingMatchesPath)
        }
        val merged = (liveDeferred.await() + upcomingDeferred.await())
            .distinctBy { it.stableId }
        Log.d(
            TAG,
            "provider=${provider.label} fallback matches=${merged.size} in ${System.currentTimeMillis() - startedAt}ms"
        )
        return@coroutineScope merged
    }

    private fun requestMatches(provider: LiveProvider, path: String): List<StreamexMatch> {
        val request = Request.Builder()
            .url("${provider.baseURL}$path")
            .header("User-Agent", IOS_SAFARI_USER_AGENT)
            .header("Referer", provider.baseURL)
            .header("Accept", "application/json")
            .build()

        return try {
            catalogClient.newCall(request).execute().use { response ->
                if (!response.isSuccessful) {
                    Log.e(TAG, "requestMatches failed provider=${provider.label} code=${response.code} url=${provider.baseURL}$path")
                    return@use emptyList()
                }
                val body = response.body?.string().orEmpty()
                if (body.isBlank()) {
                    Log.w(TAG, "requestMatches empty body from provider=${provider.label}")
                    return@use emptyList()
                }
                decodeMatches(body)
            }
        } catch (e: Exception) {
            Log.e(TAG, "requestMatches exception provider=${provider.label} error=${e.message}")
            emptyList()
        }
    }

    private fun decodeMatches(body: String): List<StreamexMatch> {
        runCatching {
            val decoded = json.decodeFromString<List<StreamexMatch>>(body)
            Log.d(TAG, "decodeMatches (Direct List) success: ${decoded.size} items")
            return decoded
        }
        return runCatching {
            val element = json.parseToJsonElement(body)
            if (element is JsonObject) {
                element["matches"]?.let { 
                    val decoded = json.decodeFromJsonElement<List<StreamexMatch>>(it)
                    Log.d(TAG, "decodeMatches (Object wrapping 'matches') success: ${decoded.size} items")
                    decoded
                }
            } else {
                Log.w(TAG, "decodeMatches: Response is neither list nor object wrapping 'matches'. Body starts with: ${body.take(100)}")
                null
            }
        }.getOrNull() ?: emptyList<StreamexMatch>().also { 
            Log.e(TAG, "decodeMatches: All decoding attempts failed. Body: ${body.take(200)}")
        }
    }

    private fun cacheEvents(events: List<StreamexMatch>) {
        cachedEvents = events
        cachedEventsAtMillis = System.currentTimeMillis()
    }

    private fun readCachedEvents(): List<StreamexMatch> {
        if (cachedEvents.isEmpty()) return emptyList()
        val ageMs = System.currentTimeMillis() - cachedEventsAtMillis
        if (ageMs > EVENTS_CACHE_TTL_MS) return emptyList()
        return cachedEvents
    }

    fun snapshotCachedEvents(): List<StreamexMatch> = readCachedEvents()

    suspend fun findStreams(match: StreamexMatch): List<StreamSource> = coroutineScope {
        val candidates = mutableListOf<StreamCandidate>()
        val jobs = match.sources.orEmpty().map { source ->
            async { 
                fetchCandidatesAcrossProviders(source.source.lowercase(Locale.US).trim(), source.id.trim())
            }
        }
        candidates.addAll(jobs.flatMap { it.await() })
        deduplicateCandidates(candidates)
            .sortedWith(::compareCandidates)
            .take(MAX_STREAM_CANDIDATES)
            .map { candidate ->
                StreamSource(
                    id = java.util.UUID.randomUUID().toString(),
                    eventId = match.stableId,
                    url = candidate.embedURL,
                    provider = "Server • ${candidate.sourceCode.uppercase(Locale.US)}",
                    type = com.pixelperfect.fotty.core.network.models.streaming.StreamType.DIRECT,
                    label = "Server • ${candidate.sourceCode.uppercase(Locale.US)}",
                    qualityLabel = if (candidate.isHD) "Direct HD" else "Standard",
                    headers = mapOf(
                        "Referer" to candidate.embedURL,
                        "User-Agent" to IOS_SAFARI_USER_AGENT
                    )
                )
            }
    }

    private suspend fun fetchCandidatesAcrossProviders(sourceCode: String, sourceId: String): List<StreamCandidate> = coroutineScope {
        val resolved = mutableListOf<StreamCandidate>()
        val providerJobs = providers.map { provider ->
            async(Dispatchers.IO) {
                val variants = requestStreamVariants(provider, sourceCode, sourceId)
                variants.mapNotNull { variant ->
                    variant.embedUrl?.let { url ->
                        StreamCandidate(
                            sourceCode = variant.source ?: sourceCode,
                            streamNo = variant.streamNo ?: 1,
                            language = variant.language,
                            isHD = variant.hd ?: false,
                            heatTier = variant.heatTier,
                            embedURL = url,
                            catalogProvider = provider.label
                        )
                    }
                }
            }
        }
        resolved.addAll(providerJobs.flatMap { it.await() })
        
        if (resolved.isEmpty()) {
            Log.w(TAG, "Stream catalog empty for source=$sourceCode id=$sourceId, using legacy multi-stream fallback.")
            resolved.addAll(
                listOf(1, 2, 3).map { streamNo ->
                    StreamCandidate(
                        sourceCode = sourceCode,
                        streamNo = streamNo,
                        language = null,
                        isHD = streamNo <= 2,
                        heatTier = if (streamNo == 1) "high" else "legacy",
                        embedURL = SecurityUtils.decode("aHR0cHM6Ly9lbWJlZHNwb3J0cy50b3Av") + "embed/$sourceCode/$sourceId/$streamNo",
                        catalogProvider = "Legacy"
                    )
                }
            )
        }
        resolved
    }

    private fun requestStreamVariants(provider: LiveProvider, code: String, id: String): List<LiveStreamVariant> {
        val codePart = URLEncoder.encode(code, "UTF-8").replace("+", "%20")
        val idPart = URLEncoder.encode(id, "UTF-8").replace("+", "%20")
        val request = Request.Builder()
            .url("${provider.baseURL}${provider.streamPathPrefix}/$codePart/$idPart")
            .header("User-Agent", IOS_SAFARI_USER_AGENT)
            .header("Referer", provider.baseURL)
            .header("Accept", "application/json")
            .build()
        return try {
            streamClient.newCall(request).execute().use { response ->
                if (!response.isSuccessful) {
                    Log.w(TAG, "requestStreamVariants non-200 provider=${provider.label} code=${response.code} source=$code id=$id")
                    return@use emptyList()
                }
                val body = response.body?.string().orEmpty()
                val decoded = decodeStreamVariants(body)
                if (decoded.isEmpty()) {
                    Log.w(
                        TAG,
                        "requestStreamVariants empty decode provider=${provider.label} source=$code id=$id bodyPrefix=${
                            body.take(120).replace("\n", " ")
                        }"
                    )
                } else {
                    Log.d(TAG, "requestStreamVariants provider=${provider.label} source=$code id=$id variants=${decoded.size}")
                }
                decoded
            }
        } catch (e: Exception) {
            Log.w(TAG, "requestStreamVariants failed provider=${provider.label} source=$code id=$id", e)
            emptyList()
        }
    }

    private fun decodeStreamVariants(body: String): List<LiveStreamVariant> {
        runCatching {
            return json.decodeFromString<List<LiveStreamVariant>>(body)
        }

        val element = runCatching { json.parseToJsonElement(body) }.getOrNull() ?: return emptyList()

        val arrayElement = when (element) {
            is JsonObject -> {
                element["streams"]
                    ?: element["variants"]
                    ?: element["data"]
                    ?: element["result"]
            }
            else -> null
        }

        if (arrayElement != null) {
            runCatching {
                return json.decodeFromJsonElement<List<LiveStreamVariant>>(arrayElement)
            }
        }

        if (arrayElement == null) return emptyList()
        return runCatching {
            arrayElement.jsonArray.mapNotNull { item ->
                val obj = item as? JsonObject ?: return@mapNotNull null
                val embedUrl = obj["embedUrl"]?.jsonPrimitive?.contentOrNull
                    ?: obj["embed_url"]?.jsonPrimitive?.contentOrNull
                    ?: obj["url"]?.jsonPrimitive?.contentOrNull
                if (embedUrl.isNullOrBlank()) return@mapNotNull null
                LiveStreamVariant(
                    streamNo = obj["streamNo"]?.jsonPrimitive?.intOrNull
                        ?: obj["stream_no"]?.jsonPrimitive?.intOrNull,
                    language = obj["language"]?.jsonPrimitive?.contentOrNull
                        ?: obj["lang"]?.jsonPrimitive?.contentOrNull,
                    hd = obj["hd"]?.jsonPrimitive?.booleanOrNull
                        ?: obj["isHD"]?.jsonPrimitive?.booleanOrNull,
                    embedUrl = embedUrl,
                    source = obj["source"]?.jsonPrimitive?.contentOrNull,
                    heatTier = obj["heatTier"]?.jsonPrimitive?.contentOrNull
                        ?: obj["heat_tier"]?.jsonPrimitive?.contentOrNull
                )
            }
        }.getOrDefault(emptyList())
    }

    private fun compareCandidates(lhs: StreamCandidate, rhs: StreamCandidate): Int {
        val lhsRank = preferredSources.indexOf(lhs.sourceCode).takeIf { it >= 0 } ?: 999
        val rhsRank = preferredSources.indexOf(rhs.sourceCode).takeIf { it >= 0 } ?: 999
        if (lhsRank != rhsRank) return lhsRank - rhsRank
        val lhsHeat = heatTierRank(lhs.heatTier)
        val rhsHeat = heatTierRank(rhs.heatTier)
        if (lhsHeat != rhsHeat) return lhsHeat - rhsHeat
        if (lhs.isHD != rhs.isHD) return rhs.isHD.compareTo(lhs.isHD)
        return lhs.streamNo - rhs.streamNo
    }

    private fun heatTierRank(heatTier: String?): Int = when (heatTier?.lowercase(Locale.US)) {
        "veryhigh" -> 0
        "high" -> 1
        "medium" -> 2
        "low" -> 3
        else -> 4
    }

    private fun deduplicateCandidates(candidates: List<StreamCandidate>): List<StreamCandidate> {
        return candidates.distinctBy { it.embedURL.lowercase(Locale.US) }
    }

    private fun findMatchingFixture(fixtures: List<StreamexMatch>, p2pTitle: String): StreamexMatch? {
        val lowerTitle = p2pTitle.lowercase(Locale.US)
        for (fixture in fixtures) {
            val homeTokens = normalizeTeamForMatching(fixture.homeName)
            val awayTokens = normalizeTeamForMatching(fixture.awayName)
            var score = 0
            for (token in homeTokens) { if (lowerTitle.contains(token)) score++ }
            for (token in awayTokens) { if (lowerTitle.contains(token)) score++ }
            if (score >= 2) return fixture
        }
        return null
    }

    private fun normalizeTeamForMatching(name: String): Set<String> {
        return name.lowercase(Locale.US).replace("fc", "").replace("utd", "united")
            .split(" ").filter { it.length > 2 }.toSet()
    }

    fun findBestTeamMatch(
        matches: List<StreamexMatch>,
        homeTeam: String,
        awayTeam: String,
        minScore: Int = MIN_TEAM_MATCH_SCORE
    ): StreamexMatch? {
        if (matches.isEmpty()) return null
        val homeTokens = teamTokens(homeTeam)
        val awayTokens = teamTokens(awayTeam)
        if (homeTokens.isEmpty() && awayTokens.isEmpty()) return null

        val ranked = matches.map { match ->
            val titleTokens = teamTokens(match.title.orEmpty())
            val matchHomeTokens = teamTokens(match.homeName)
            val matchAwayTokens = teamTokens(match.awayName)

            val directHome = maxOf(
                overlapCount(homeTokens, matchHomeTokens),
                overlapCount(homeTokens, titleTokens)
            )
            val directAway = maxOf(
                overlapCount(awayTokens, matchAwayTokens),
                overlapCount(awayTokens, titleTokens)
            )
            val directScore = (directHome * 3) + (directAway * 3) + if (directHome > 0 && directAway > 0) 4 else 0

            val swappedHome = maxOf(
                overlapCount(homeTokens, matchAwayTokens),
                overlapCount(homeTokens, titleTokens)
            )
            val swappedAway = maxOf(
                overlapCount(awayTokens, matchHomeTokens),
                overlapCount(awayTokens, titleTokens)
            )
            val swappedScore = (swappedHome * 3) + (swappedAway * 3) + if (swappedHome > 0 && swappedAway > 0) 3 else 0

            val sourceBonus = if (!match.sources.isNullOrEmpty()) 2 else 0
            val score = maxOf(directScore, swappedScore) + sourceBonus
            match to score
        }

        val best = ranked.maxByOrNull { it.second } ?: return null
        return if (best.second >= minScore) best.first else null
    }

    private fun normalizeCategory(raw: String?): String {
        val v = raw?.lowercase(Locale.US).orEmpty()
        return if (v.contains("soc") || v.contains("foot")) "football" else "other"
    }

    private fun teamTokens(value: String): Set<String> {
        if (value.isBlank()) return emptySet()

        val folded = Normalizer.normalize(value, Normalizer.Form.NFD)
            .replace("\\p{M}+".toRegex(), "")
            .lowercase(Locale.US)
            .replace("&", " and ")
            .replace("[^a-z0-9 ]".toRegex(), " ")
            .replace("\\s+".toRegex(), " ")
            .trim()

        if (folded.isBlank()) return emptySet()

        val base = folded
            .split(" ")
            .filter { token -> token.length >= 2 && token !in COMMON_TEAM_TOKENS && token !in TEAM_NOISE_TOKENS }
            .toMutableSet()

        if (base.isEmpty()) return emptySet()

        val expanded = base.toMutableSet()
        for (token in base) {
            TEAM_SYNONYMS[token]?.let { expanded.addAll(it) }
        }

        return expanded
    }

    private fun overlapCount(lhs: Set<String>, rhs: Set<String>): Int {
        if (lhs.isEmpty() || rhs.isEmpty()) return 0
        return lhs.count { rhs.contains(it) }
    }

    fun categoryDisplayNameFor(key: String): String = if (key == "football") "Football" else "Other"

    private val COMMON_TEAM_TOKENS = setOf("fc", "cf", "sc", "afc", "club", "the", "united", "utd")
    private val TEAM_NOISE_TOKENS = setOf("de", "da", "do", "la", "las", "los", "and")
    private val TEAM_SYNONYMS = mapOf(
        "utd" to setOf("united"),
        "united" to setOf("utd"),
        "atl" to setOf("atletico"),
        "atletico" to setOf("atl"),
        "mg" to setOf("mineiro")
    )
    private const val MIN_TEAM_MATCH_SCORE = 6
}
