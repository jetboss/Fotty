package com.pixelperfect.fotty.core.network.resolver

import android.util.Log
import com.pixelperfect.fotty.core.Config
import com.pixelperfect.fotty.core.network.models.streaming.StreamSource
import com.pixelperfect.fotty.core.network.models.streaming.StreamType
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.async
import kotlinx.coroutines.awaitAll
import kotlinx.coroutines.withContext
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json
import okhttp3.OkHttpClient
import okhttp3.Request
import javax.inject.Inject
import javax.inject.Singleton

@Serializable
data class ScrapedAceMatch(
    val cid: String,
    val title: String,
    val availability: Double? = null,
    val bitrate: Int? = null,
    val category: String? = null
)

@Singleton
class P2PDataService @Inject constructor(
    private val httpClient: OkHttpClient,
    private val json: Json
) {
    private val SCRAPER_URL = "https://scraper.pixel-invoice.com"
    private val SERVER_URL = "https://p2p.pixel-invoice.com"
    private val API_PASSWORD = Config.p2pApiPassword

    suspend fun findStreams(eventId: String, homeTeam: String, awayTeam: String, matchCategory: String?): List<StreamSource> = withContext(Dispatchers.IO) {
        val queries = listOf(
            "$homeTeam $awayTeam",
            homeTeam,
            awayTeam
        )

        val deferreds = queries.map { query ->
            async {
                fetchMatchesFromScraper("/search/${java.net.URLEncoder.encode(query, "UTF-8")}")
            }
        }
        
        val catalogDeferred = async { fetchMatchesFromScraper("/matches") }

        val allResults = deferreds.awaitAll()
        val catalogResults = catalogDeferred.await()
        
        val allMatches = (allResults.flatten() + catalogResults).distinctBy { it.cid }
        
        // Filter by sport parity and relevance
        val targetSport = inferSport(homeTeam, awayTeam, matchCategory)
        
        val filtered = allMatches.filter { match ->
            val matchSport = inferSport(match.title, "", match.category)
            
            // Strict sport parity: don't show basketball in football matches
            if (targetSport != "general" && matchSport != "general" && targetSport != matchSport) {
                return@filter false
            }

            val score = calculateMatchScore(match.title, homeTeam, awayTeam)
            score > 0
        }

        buildSources(eventId, filtered, homeTeam, awayTeam)
            .sortedByDescending { it.headers["X-Fotty-P2P-Match-Score"]?.toIntOrNull() ?: 0 }
    }

    private fun inferSport(title: String, secondTitle: String = "", category: String? = null): String {
        val text = "$title $secondTitle ${category ?: ""}".lowercase()
        return when {
            text.contains("football") || text.contains("soccer") || text.contains("premier league") || text.contains("champions league") -> "football"
            text.contains("basketball") || text.contains("nba") -> "basketball"
            text.contains("hockey") || text.contains("nhl") -> "hockey"
            text.contains("baseball") || text.contains("mlb") -> "baseball"
            text.contains("tennis") || text.contains("atp") || text.contains("wta") -> "tennis"
            text.contains("fight") || text.contains("ufc") || text.contains("boxing") || text.contains("mma") -> "fight"
            else -> "general"
        }
    }

    private fun calculateMatchScore(matchTitle: String, home: String, away: String): Int {
        val title = matchTitle.lowercase()
        val h = home.lowercase()
        val a = away.lowercase()
        
        var score = 0
        
        fun scoreForTeam(team: String): Int {
            if (team.isEmpty()) return 0
            if (title.contains(team)) return 100
            
            val keywords = team.split(" ").filter { it.length > 3 }
            return if (keywords.any { title.contains(it) }) 50 else 0
        }
        
        score += scoreForTeam(h)
        score += scoreForTeam(a)
        
        return score
    }

    private suspend fun fetchMatchesFromScraper(path: String): List<ScrapedAceMatch> {
        return try {
            val request = Request.Builder()
                .url("$SCRAPER_URL$path")
                .header("Authorization", "Bearer $API_PASSWORD")
                .header("Accept", "application/json")
                .build()

            httpClient.newCall(request).execute().use { response ->
                if (response.isSuccessful) {
                    val body = response.body?.string() ?: ""
                    json.decodeFromString<List<ScrapedAceMatch>>(body)
                } else {
                    Log.e("P2PDataService", "Scraper error: ${response.code}")
                    emptyList()
                }
            }
        } catch (e: Exception) {
            Log.e("P2PDataService", "Fetch failed: ${e.message}")
            emptyList()
        }
    }

    private fun buildSources(eventId: String, matches: List<ScrapedAceMatch>, home: String, away: String): List<StreamSource> {
        return matches.map { match ->
            val availability = (match.availability ?: 0.5)
            val availabilityLabel = " (${(availability * 100).toInt()}%)"
            val score = calculateMatchScore(match.title, home, away)
            
            StreamSource(
                id = match.cid,
                eventId = eventId,
                url = "$SERVER_URL/proxy/acestream/manifest.m3u8?infohash=${match.cid}&api_password=$API_PASSWORD",
                provider = "P2P NETWORK - ${match.title}",
                label = "AceStream HD$availabilityLabel",
                qualityLabel = "${match.bitrate ?: 1080}p P2P",
                type = StreamType.P2P,
                headers = mapOf(
                    "User-Agent" to "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15",
                    "Referer" to "$SERVER_URL/",
                    "X-Fotty-P2P-Match-Score" to score.toString(),
                    "X-Fotty-P2P-Availability" to availability.toString(),
                    "X-Fotty-P2P-Bitrate" to (match.bitrate ?: 0).toString(),
                    "X-Fotty-P2P-Probe-Class" to if (score >= 100) "strong" else "medium"
                ),
                mimeType = "application/x-mpegURL"
            )
        }
    }
}
