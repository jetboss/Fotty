package com.pixelperfect.fotty.core.storage

import android.content.Context
import android.content.SharedPreferences
import com.pixelperfect.fotty.core.utils.SecurityUtils
import dagger.hilt.android.qualifiers.ApplicationContext
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlinx.serialization.Serializable
import kotlinx.serialization.decodeFromString
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json
import okhttp3.OkHttpClient
import okhttp3.Request
import java.net.URLEncoder
import java.util.Locale
import javax.inject.Inject
import javax.inject.Singleton

@Serializable
data class SportsDBResponse(val teams: List<SportsDBTeam>? = null)

@Serializable
data class SportsDBTeam(
    val strTeam: String? = null,
    val strTeamShort: String? = null,
    val strTeamAlternate: String? = null,
    val strBadge: String? = null
)

@Singleton
class TeamBrandService @Inject constructor(
    @ApplicationContext context: Context,
    private val okHttpClient: OkHttpClient,
    private val json: Json
) {
    private val prefs: SharedPreferences = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
    private val cache: MutableMap<String, String> = mutableMapOf()

    init {
        loadCache()
    }

    private fun normalizedKey(name: String): String {
        return name.lowercase(Locale.US).trim().replace("\\s+".toRegex(), " ")
    }

    fun getCachedBadge(name: String): String? {
        val key = normalizedKey(name)
        return cache[key]
    }

    suspend fun resolveBadge(name: String): String? = withContext(Dispatchers.IO) {
        val key = normalizedKey(name)
        getCachedBadge(name)?.let { return@withContext it }

        val genericNames = listOf("home", "away", "tba", "tbd", "unknown", "team", "to be announced")
        if (key in genericNames) return@withContext null

        val encodedName = URLEncoder.encode(name, "UTF-8")
        val url = "https://www.thesportsdb.com/api/v1/json/3/searchteams.php?t=$encodedName"
        
        val request = Request.Builder()
            .url(url)
            .build()

        try {
            okHttpClient.newCall(request).execute().use { response ->
                if (!response.isSuccessful) return@withContext null
                val body = response.body?.string() ?: return@withContext null
                val data = json.decodeFromString<SportsDBResponse>(body)
                val team = data.teams?.firstOrNull() ?: return@withContext null
                
                // VALIDATION: Ensure the returned team name is actually similar to what we searched for
                val foundName = team.strTeam?.lowercase() ?: ""
                val searchName = name.lowercase()
                
                if (!foundName.contains(searchName) && !searchName.contains(foundName)) {
                    // Try alternate names
                    val alt = team.strTeamAlternate?.lowercase() ?: ""
                    val short = team.strTeamShort?.lowercase() ?: ""
                    if (!alt.contains(searchName) && !short.contains(searchName)) {
                        android.util.Log.w("TeamBrandService", "Discarding mismatching result: $foundName for search: $searchName")
                        return@withContext null
                    }
                }

                val badgeUrl = team.strBadge ?: return@withContext null
                
                // Save to cache
                synchronized(cache) {
                    cache[key] = badgeUrl
                    // Also cache synonyms
                    team.strTeam?.let { cache[normalizedKey(it)] = badgeUrl }
                    team.strTeamShort?.let { cache[normalizedKey(it)] = badgeUrl }
                }
                saveCache()
                return@withContext badgeUrl
            }
        } catch (e: Exception) {
            null
        }
    }

    private fun loadCache() {
        val raw = prefs.getString(KEY_CACHE, null) ?: return
        try {
            val decoded = json.decodeFromString<Map<String, String>>(raw)
            cache.putAll(decoded)
        } catch (_: Exception) {}
    }

    private fun saveCache() {
        val raw = json.encodeToString(cache.toMap())
        prefs.edit().putString(KEY_CACHE, raw).apply()
    }

    companion object {
        private const val PREFS_NAME = "fotty_team_brand_cache_v2"
        private const val KEY_CACHE = "badge_cache"
    }
}
