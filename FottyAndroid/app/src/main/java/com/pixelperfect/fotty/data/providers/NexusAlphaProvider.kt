package com.pixelperfect.fotty.data.providers

import android.util.Log
import com.pixelperfect.fotty.core.network.api.nexus.NexusAlphaInterface
import com.pixelperfect.fotty.core.network.models.nexus.NexusAEvent
import com.pixelperfect.fotty.data.models.League
import com.pixelperfect.fotty.data.models.Match
import com.pixelperfect.fotty.data.models.MatchStatus
import com.pixelperfect.fotty.core.network.models.streaming.StreamSource
import com.pixelperfect.fotty.data.models.Team
import java.util.UUID
import javax.inject.Inject
import javax.inject.Singleton

@Singleton
class NexusAlphaProvider @Inject constructor(
    private val api: NexusAlphaInterface
) {
    private val mirrors = listOf(
        "https://streamex.sh",
        "https://streamed.pk",
        "https://streamex.net",
        "https://nexus.top"
    )

    private val paths = listOf(
        "/api/live/matches/all",
        "/api/matches/all",
        "/api/live/matches/live"
    )

    // Cache of raw Nexus events to resolve streams later
    private val eventCache = mutableMapOf<String, NexusAEvent>()
    private var lastSuccessfulMirror: String = mirrors.first()

    suspend fun getLiveEvents(): List<Match> {
        Log.d("NexusAlphaProvider", "getLiveEvents called")
        for (mirror in mirrors) {
            for (path in paths) {
                try {
                    val url = "$mirror$path"
                    Log.d("NexusAlphaProvider", "Fetching from $url")
                    
                    // The Nexus API can return a list or a wrapped object.
                    // We'll try fetching as a list first.
                    try {
                        val rawJson = api.getLiveResponseRaw(url, referer = mirror).string()
                        Log.d("NexusAlphaProvider", "RAW_NEXUS_JSON: ${rawJson.take(1000)}...")
                    } catch (e: Exception) {
                        Log.e("NexusAlphaProvider", "RAW_NEXUS_JSON FAILED: ${e.message}")
                    }
                    
                    val events = try {
                        api.getLiveEvents(url, referer = mirror)
                    } catch (e: Exception) {
                        api.getLiveResponse(url, referer = mirror).matches ?: emptyList()
                    }

                    if (events.isNotEmpty()) {
                        Log.d("NexusAlphaProvider", "Successfully loaded ${events.size} events from $mirror")
                        events.forEach { Log.d("NexusAlphaProvider", "EVENT_TITLE: ${it.title}") }
                        lastSuccessfulMirror = mirror
                        return events.map { event ->
                            val match = event.toDomain()
                            eventCache[match.id] = event
                            match
                        }
                    }
                } catch (e: Exception) {
                    Log.e("NexusAlphaProvider", "Failed to fetch from mirror $mirror$path: ${e.message}")
                }
            }
        }
        return emptyList()
    }

    suspend fun getStreamsForCachedEvent(matchId: String): List<com.pixelperfect.fotty.core.network.models.streaming.StreamSource> {
        val event = eventCache[matchId] ?: return emptyList()
        val sources = event.sources ?: return emptyList()
        return getStreamSources(matchId, sources)
    }

    fun findMatchIdByTeams(home: String, away: String): String? {
        val h = home.lowercase().trim()
        val a = away.lowercase().trim()
        
        // Try exact match first
        val exact = eventCache.values.find { event ->
            val eh = event.teams?.home?.name?.lowercase() ?: ""
            val ea = event.teams?.away?.name?.lowercase() ?: ""
            (eh.contains(h) && ea.contains(a)) || (eh.contains(a) && ea.contains(h))
        }
        if (exact != null) return exact.id
        
        // Try title match
        return eventCache.values.find { event ->
            val title = event.title?.lowercase() ?: ""
            title.contains(h) && title.contains(a)
        }?.id
    }

    fun findMatchIdByNormalizedTeams(home: String, away: String): String? {
        // home and away are already normalized by MatchRepository
        return eventCache.values.find { event ->
            val eh = event.teams?.home?.name?.lowercase() ?: ""
            val ea = event.teams?.away?.name?.lowercase() ?: ""
            
            // Normalize the Nexus team names too for comparison
            val neh = normalizeForSearch(eh)
            val nea = normalizeForSearch(ea)
            
            (neh.contains(home) || home.contains(neh)) && (nea.contains(away) || away.contains(nea))
        }?.id ?: findMatchIdByTeams(home, away)
    }

    private fun normalizeForSearch(name: String): String {
        val s = name.lowercase()
            .replace("real ", "")
            .replace("fc ", "")
            .replace(" cf", "")
            .replace(" afc", "")
            .replace(" sc", "")
            .replace(" united", "")
            .replace(" r.", "")
            .replace(".", "")
            .replace("-", " ")
            .trim()
            
        return when {
            s.contains("atletico") || s.contains("atleti") -> "atletico madrid"
            s.contains("athletic") -> "athletic club"
            s.contains("man utd") || s.contains("manchester utd") -> "manchester united"
            s.contains("psg") || s.contains("paris") -> "paris saint germain"
            s.contains("bayern") -> "bayern munich"
            else -> s
        }
    }

    suspend fun getStreamSources(
        matchId: String, 
        sources: List<com.pixelperfect.fotty.core.network.models.nexus.NexusASource>
    ): List<com.pixelperfect.fotty.core.network.models.streaming.StreamSource> {
        val allVariants = mutableListOf<com.pixelperfect.fotty.core.network.models.streaming.StreamSource>()
        val mirror = lastSuccessfulMirror
        
        for (source in sources) {
            try {
                // Ensure correct path based on mirror (some use /api/live/stream, others /api/stream)
                val streamPath = if (mirror.contains("nx.net")) "/api/stream" else "/api/live/stream"
                val url = "$mirror$streamPath/${source.source}/${source.id}"
                
                val variants = api.getStreamVariants(url, referer = mirror)
                
                allVariants.addAll(variants.map { variant ->
                    com.pixelperfect.fotty.core.network.models.streaming.StreamSource(
                        id = UUID.randomUUID().toString(),
                        eventId = matchId,
                        url = variant.embedUrl ?: "",
                        provider = "Nexus ${variant.source?.uppercase() ?: "ALPHA"}",
                        type = if (variant.embedUrl?.contains(".m3u8") == true) 
                                com.pixelperfect.fotty.core.network.models.streaming.StreamType.HLS 
                               else com.pixelperfect.fotty.core.network.models.streaming.StreamType.FALLBACK,
                        label = variant.source?.uppercase() ?: "SERVER ${variant.streamNo}",
                        qualityLabel = if (variant.hd == true) "1080p HD" else "720p",
                        isPreferred = variant.hd == true,
                        headers = mapOf("Referer" to mirror)
                    )
                })
            } catch (e: Exception) {
                Log.e("NexusAlphaProvider", "Failed to fetch variants for $matchId: ${e.message}")
            }
        }
        return allVariants
    }

    private fun NexusAEvent.toDomain(): Match {
        val dateMillis = date?.let { 
            if (it > 10_000_000_000L) it else it * 1000L
        } ?: System.currentTimeMillis()

        val homeName = teams?.home?.name ?: splitTitle().first
        val awayName = teams?.away?.name ?: splitTitle().second
        
        val categoryRaw = category?.lowercase() ?: "other"
        val normalizedCategory = when (categoryRaw) {
            "soccer" -> "football"
            "mma", "boxing", "ufc" -> "fight"
            "nba", "basketball" -> "basketball"
            "mlb", "baseball" -> "baseball"
            "nhl", "hockey" -> "hockey"
            else -> categoryRaw
        }

        val now = System.currentTimeMillis()
        val fifteenMinutesMillis = 15 * 60 * 1000L
        val twoHoursMillis = 130 * 60 * 1000L

        val calculatedStatus: MatchStatus
        val calculatedStatusText: String?

        if (dateMillis > now + fifteenMinutesMillis) {
            calculatedStatus = MatchStatus.SCHEDULED
            // Mirror iOS RelativeDateTimeFormatter (short style)
            val diff = dateMillis - now
            val hours = diff / (3600 * 1000)
            val minutes = (diff % (3600 * 1000)) / (60 * 1000)
            
            calculatedStatusText = when {
                hours > 24 -> "${hours / 24}d"
                hours > 0 -> "in ${hours} hr."
                else -> "in ${minutes} min."
            }
        } else if (now > dateMillis + twoHoursMillis) {
            calculatedStatus = MatchStatus.FINISHED
            calculatedStatusText = "FT"
        } else {
            calculatedStatus = MatchStatus.LIVE
            val extractedScore = tryExtractScore(title ?: "")
            if (extractedScore != null) {
                android.util.Log.d("NexusAlphaProvider", "SCORE_DEBUG: Extracted '$extractedScore' from title '$title'")
            }
            calculatedStatusText = extractedScore ?: if (categoryRaw == "football") "LIVE" else normalizedCategory.uppercase()
        }

        return Match(
            id = id ?: "nexus-${title.hashCode()}-$dateMillis",
            homeTeam = Team(
                id = "t-${homeName.hashCode()}",
                name = homeName,
                logoUrl = teams?.home?.badge?.let { buildBadgeUrl(it) }
            ),
            awayTeam = Team(
                id = "t-${awayName.hashCode()}",
                name = awayName,
                logoUrl = teams?.away?.badge?.let { buildBadgeUrl(it) }
            ),
            status = calculatedStatus,
            timestamp = dateMillis,
            league = League(
                id = "l-${normalizedCategory.hashCode()}",
                name = com.pixelperfect.fotty.core.util.LeagueResolver.infer(title ?: "", homeName, awayName),
                logoUrl = poster?.let { buildBadgeUrl(it) }
            ),
            category = normalizedCategory,
            statusText = calculatedStatusText
        )
    }

    private fun tryExtractScore(title: String): String? {
        // Regex to find patterns like "1-2", "1 - 2", "145/4", or "(145/4)"
        val patterns = listOf(
            Regex("(\\d+)\\s*-\\s*(\\d+)"), // Football style 1-2
            Regex("\\(?(\\d+/\\d+)\\s*(\\(\\d+\\.\\d+ ov\\))?\\)?"), // Cricket style
            Regex("\\(?(\\d+-\\d+)\\s*(\\(\\d+\\.\\d+ ov\\))?\\)?")
        )
        
        for (pattern in patterns) {
            val match = pattern.find(title)
            if (match != null) {
                // For football, ensure it's not a date or something else
                if (pattern.pattern.contains("-")) {
                    val groups = match.groupValues
                    if (groups.size >= 3) {
                        return "${groups[1]}-${groups[2]}"
                    }
                }
                return match.value.trim('(', ')')
            }
        }
        return null
    }

    private fun buildBadgeUrl(raw: String): String? {
        if (raw.isBlank() || raw == "null") return null
        if (raw.startsWith("http")) return raw
        
        val base = com.pixelperfect.fotty.core.utils.SecurityUtils.decode("aHR0cHM6Ly9zdHJlYW1lZC5waw==")
        
        return when {
            raw.startsWith("/api/") -> base + raw
            else -> {
                val clean = raw.substringBeforeLast(".")
                "$base/api/images/badge/$clean.webp"
            }
        }
    }

    private fun NexusAEvent.splitTitle(): Pair<String, String> {
        val t = title ?: return "Home" to "Away"
        val separators = listOf(" vs ", " v ", " @ ", " - ")
        for (sep in separators) {
            val parts = t.split(sep)
            if (parts.size == 2) {
                return parts[0].trim() to parts[1].trim()
            }
        }
        return t to "Away"
    }

}
