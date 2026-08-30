package com.pixelperfect.fotty.data.repositories

import android.util.Log
import com.pixelperfect.fotty.data.mappers.toMatch
import com.pixelperfect.fotty.data.models.Match
import com.pixelperfect.fotty.data.providers.IFootballProvider
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import java.text.SimpleDateFormat
import java.util.*
import javax.inject.Inject
import javax.inject.Singleton

@Singleton
class MatchRepository @Inject constructor(
    private val provider: IFootballProvider,
    private val footballDataApi: com.pixelperfect.fotty.core.network.api.football.FootballInterface,
    private val fottyFootballProxy: com.pixelperfect.fotty.core.network.api.football.FottyFootballProxyInterface,
    private val nexusProvider: com.pixelperfect.fotty.data.providers.NexusAlphaProvider,
    private val p2pService: com.pixelperfect.fotty.core.network.resolver.P2PDataService,
    private val hockeyApi: com.pixelperfect.fotty.core.network.api.hockey.HockeyInterface,
    private val cricketApi: com.pixelperfect.fotty.core.network.api.cricket.CricketInterface
) {
    private val TAG = "MatchRepository"
    private val hockeyApiKey = com.pixelperfect.fotty.core.Config.apiFootballKey

    private suspend fun footballDataMatches(
        competition: String,
        status: String? = null,
        dateFrom: String? = null,
        dateTo: String? = null,
    ): com.pixelperfect.fotty.core.network.models.football.FootballMatchesResponse {
        if (com.pixelperfect.fotty.core.Config.prefersFootballDataProxy) {
            try {
                return fottyFootballProxy.getMatches(
                    competition = competition,
                    status = status,
                    dateFrom = dateFrom,
                    dateTo = dateTo,
                )
            } catch (e: Exception) {
                Log.w(TAG, "Fotty football proxy failed; falling back to direct API", e)
            }
        }
        return footballDataApi.getMatches(
            league = competition,
            apiKey = com.pixelperfect.fotty.core.Config.footballAPIKey,
            status = status,
            dateFrom = dateFrom,
            dateTo = dateTo,
        )
    }
    
    // In-memory cache with TTL
    private var dailyFixturesCache: List<Match>? = null
    private var lastDailyFetch: Long = 0
    private val DAILY_TTL = 5 * 60 * 1000 // 5 minutes

    private var liveFixturesCache: List<Match>? = null
    private var lastLiveFetch: Long = 0
    private val LIVE_TTL = 20 * 1000 // 20 seconds

    private val _liveMatches = MutableStateFlow<List<Match>>(emptyList())
    val liveMatches: StateFlow<List<Match>> = _liveMatches

    private fun normalizeTeamName(name: String): String {
        val lowered = name.lowercase().replace("[^a-z0-9 ]".toRegex(), " ")
        
        var alias = lowered
            .replace(" fc ", " ")
            .replace(" cf ", " ")
            .replace(" afc ", " ")
            .replace(" football club ", " ")
            .replace(" wanderers ", " ")
            .replace(" united ", " united ")
            .trim()
        
        alias = alias.split(" ")
            .filter { it.isNotEmpty() }
            .joinToString(" ")
        
        return when {
            alias.contains("man utd") || alias.contains("manchester utd") -> "manchester united"
            alias.contains("man city") || alias.contains("manchester city") -> "manchester city"
            alias.contains("atletico") || alias.contains("atleti") -> "atletico madrid"
            alias.contains("athletic") -> "athletic club"
            alias.contains("spurs") || alias.contains("tottenham") -> "tottenham"
            alias.contains("wolves") -> "wolverhampton"
            alias.contains("psg") -> "paris saint germain"
            alias.contains("bayern") -> "bayern munich"
            alias.contains("leverkusen") -> "bayer leverkusen"
            else -> alias
        }
    }

    private fun getMatchKey(match: Match): String {
        val h = normalizeTeamName(match.homeTeam.name)
        val a = normalizeTeamName(match.awayTeam.name)
        return "${h}_${a}"
    }

    suspend fun getDailyFixtures(
        date: String = SimpleDateFormat("yyyy-MM-dd", Locale.getDefault()).format(Date()),
        forceRefresh: Boolean = false
    ): List<Match> {
        val now = System.currentTimeMillis()
        if (!forceRefresh && dailyFixturesCache != null && (now - lastDailyFetch) < DAILY_TTL) {
            return dailyFixturesCache!!
        }

        Log.d(TAG, "[MatchRepo] REQ: getDailyFixtures | Date: $date")
        
        // Fetch from both providers
        val apiSportsMatches = try {
            val raw = provider.getFixturesByDate(date)
            Log.d(TAG, "[MatchRepo] Daily API-Sports items: ${raw.size} for $date")
            val mapped = raw.map { it.toMatch() }
            
            // Overlay live scores for real-time accuracy (iOS Parity)
            try {
                val now = System.currentTimeMillis()
                val liveMatchesMapped = if (now - lastLiveFetch < LIVE_TTL && liveFixturesCache != null) {
                    Log.d(TAG, "[MatchRepo] Using cached Live Pulse scores (${liveFixturesCache?.size ?: 0})")
                    liveFixturesCache!!
                } else {
                    val liveRaw = provider.getLiveFixtures()
                    Log.d(TAG, "[MatchRepo] Fetched ${liveRaw.size} Live Pulse scores...")
                    val mappedLive = liveRaw.map { it.toMatch() }
                    liveFixturesCache = mappedLive
                    lastLiveFetch = now
                    mappedLive
                }

                mapped.map { match ->
                    val mKey = getMatchKey(match)
                    

                    val liveOverlay = liveMatchesMapped.find { getMatchKey(it) == mKey }
                    if (liveOverlay != null) {
                        match.copy(
                            status = liveOverlay.status,
                            statusText = liveOverlay.statusText,
                            homeScore = liveOverlay.homeScore,
                            awayScore = liveOverlay.awayScore,
                            minute = liveOverlay.minute
                        )
                    } else match
                }
            } catch (e: Exception) {
                Log.e(TAG, "[MatchRepo] Live overlay failed: ${e.message}")
                mapped
            }
        } catch (e: Exception) {
            Log.e(TAG, "[MatchRepo] Daily API-Sports error: ${e.message}")
            emptyList()
        }

        val nexusMatches = try {
            val raw = nexusProvider.getLiveEvents()
            Log.d(TAG, "[MatchRepo-Daily] Nexus items: ${raw.size}")
            raw
        } catch (e: Exception) {
            emptyList()
        }

        // FETCH CRICKET SCORES FOR DAILY
        val cricketScores = if (nexusMatches.any { it.category?.lowercase()?.trim() == "cricket" }) {
            try {
                Log.d(TAG, "[MatchRepo-Daily] Fetching Cricket Scores...")
                val today = SimpleDateFormat("yyyy-MM-dd", Locale.getDefault()).format(Date())
                val resp = cricketApi.getMatches(apiKey = hockeyApiKey, dateStart = today, dateStop = today).result ?: emptyList()
                resp
            } catch (e: Exception) {
                emptyList()
            }
        } else emptyList()

        // Merge and deduplicate (Prefer API-Sports for names/leagues, Nexus for IDs)
        val allMatches = (apiSportsMatches + nexusMatches).toMutableList()
        
        // SELF-HEALING: If Champions League is missing from primary sources, fetch from high-authority fallback
        if (!allMatches.any { (it.league.name.contains("Champions League") || it.league.id.contains("CL")) && it.status != com.pixelperfect.fotty.data.models.MatchStatus.FINISHED }) {
            try {
                Log.d(TAG, "[MatchRepo-Daily] CL Missing or only finished matches found. Fetching authority fallback for $date...")
                // Restrict fallback to the target date to prevent 'yesterday' matches showing as upcoming
                val clResp = footballDataMatches(
                    competition = "CL",
                    dateFrom = date,
                    dateTo = date
                )
                val clMatches = clResp.matches.map { m ->
                    Match(
                        id = "fd-cl-${m.id}",
                        homeTeam = com.pixelperfect.fotty.data.models.Team(
                            id = "t-${m.homeTeam.id}", 
                            name = m.homeTeam.shortName ?: m.homeTeam.name ?: "Unknown",
                            logoUrl = m.homeTeam.crest
                        ),
                        awayTeam = com.pixelperfect.fotty.data.models.Team(
                            id = "t-${m.awayTeam.id}", 
                            name = m.awayTeam.shortName ?: m.awayTeam.name ?: "Unknown",
                            logoUrl = m.awayTeam.crest
                        ),
                        status = when(m.status) {
                            "IN_PLAY" -> com.pixelperfect.fotty.data.models.MatchStatus.LIVE
                            "FINISHED" -> com.pixelperfect.fotty.data.models.MatchStatus.FINISHED
                            else -> com.pixelperfect.fotty.data.models.MatchStatus.SCHEDULED
                        },
                        statusText = if (m.status == "IN_PLAY") "LIVE" else null,
                        homeScore = m.score.fullTime?.home ?: 0,
                        awayScore = m.score.fullTime?.away ?: 0,
                        timestamp = m.utcDate?.let { 
                            try { SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss'Z'", Locale.US).parse(it)?.time } catch (e: Exception) { System.currentTimeMillis() }
                        } ?: System.currentTimeMillis(),
                        league = com.pixelperfect.fotty.data.models.League(
                            id = "l-CL",
                            name = "Champions League",
                            logoUrl = m.competition.emblem
                        ),
                        category = "football"
                    )
                }
                allMatches.addAll(clMatches)
            } catch (e: Exception) {
                Log.e(TAG, "[MatchRepo-Daily] Authority fallback failed: ${e.message}")
            }
        }

        val uniqueMatches = allMatches
            .filter { it.homeTeam.name.isNotBlank() && it.awayTeam.name.isNotBlank() }
            .groupBy { getMatchKey(it) }
            .map { (_, group) ->
                val nexus = group.find { it.id.contains("nexus") }
                val apiSports = group.find { !it.id.contains("nexus") && !it.id.contains("fd-cl") }
                val fallback = group.find { it.id.contains("fd-cl") }
                
                val bestMetadata = apiSports ?: fallback ?: nexus
                
                if (nexus != null && bestMetadata != null) {
                    bestMetadata.copy(
                        id = nexus.id, 
                        status = if (bestMetadata.status == com.pixelperfect.fotty.data.models.MatchStatus.LIVE) bestMetadata.status else nexus.status,
                        statusText = bestMetadata.statusText ?: nexus.statusText,
                        homeScore = bestMetadata.homeScore ?: nexus.homeScore,
                        awayScore = bestMetadata.awayScore ?: nexus.awayScore,
                        category = bestMetadata.category.ifEmpty { nexus.category }
                    )
                } else {
                    group.first()
                }
            }
            .sortedWith(
                compareByDescending<Match> { it.status == com.pixelperfect.fotty.data.models.MatchStatus.LIVE }
                .thenByDescending { it.league.name.contains("Champions League") }
                .thenByDescending { it.category == "football" }
            )
            .map { match ->
            if (match.category?.lowercase()?.trim() == "cricket" && match.status == com.pixelperfect.fotty.data.models.MatchStatus.LIVE) {
                val cricketMatch = cricketScores.find { c ->
                    val ch = normalizeTeamName(c.event_home_team ?: "")
                    val ca = normalizeTeamName(c.event_away_team ?: "")
                    val mh = normalizeTeamName(match.homeTeam.name)
                    val ma = normalizeTeamName(match.awayTeam.name)
                    (ch.contains(mh) || mh.contains(ch)) && (ca.contains(ma) || ma.contains(ca))
                }
                if (cricketMatch != null) {
                    val scoreText = cricketMatch.score ?: "${cricketMatch.event_home_final_score ?: ""} vs ${cricketMatch.event_away_final_score ?: ""}"
                    match.copy(statusText = scoreText.trim().ifEmpty { "Live Pulse" })
                } else {
                    match.copy(statusText = "Live Pulse")
                }
            } else match
        }
        
        Log.d(TAG, "[MatchRepo] Total Daily unique matches: ${uniqueMatches.size}")
        
        dailyFixturesCache = uniqueMatches
        lastDailyFetch = now
        
        return uniqueMatches
    }

    suspend fun getLiveFixtures(): List<Match> {
        val now = System.currentTimeMillis()
        if (liveFixturesCache != null && (now - lastLiveFetch) < LIVE_TTL) {
            return liveFixturesCache!!
        }

        Log.d(TAG, "[MatchRepo] REQ: getLiveFixtures")
        
        val apiSportsMatches = try {
            val raw = provider.getLiveFixtures()
            raw.map { it.toMatch() }
        } catch (e: Exception) {
            emptyList()
        }

        // FALLBACK: If API-Sports is exhausted, try Football-Data.org for high-profile leagues
        val secondaryMatches = if (apiSportsMatches.isEmpty()) {
            try {
                Log.d(TAG, "[MatchRepo] API-Sports exhausted. Fetching from Football-Data.org...")
                val plResp = footballDataMatches(competition = "PL", status = "IN_PLAY")
                val clResp = footballDataMatches(competition = "CL", status = "IN_PLAY")
                
                (plResp.matches + clResp.matches).map { m ->
                    Match(
                        id = "fd-${m.id}",
                        homeTeam = com.pixelperfect.fotty.data.models.Team(
                            id = "t-${m.homeTeam.id}", 
                            name = m.homeTeam.shortName ?: m.homeTeam.name ?: "Unknown",
                            logoUrl = m.homeTeam.crest
                        ),
                        awayTeam = com.pixelperfect.fotty.data.models.Team(
                            id = "t-${m.awayTeam.id}", 
                            name = m.awayTeam.shortName ?: m.awayTeam.name ?: "Unknown",
                            logoUrl = m.awayTeam.crest
                        ),
                        status = com.pixelperfect.fotty.data.models.MatchStatus.LIVE,
                        statusText = "LIVE",
                        homeScore = m.score.fullTime?.home ?: 0,
                        awayScore = m.score.fullTime?.away ?: 0,
                        timestamp = System.currentTimeMillis(),
                        league = com.pixelperfect.fotty.data.models.League(
                            id = "l-${m.competition.id}",
                            name = m.competition.name ?: "Football",
                            logoUrl = m.competition.emblem
                        )
                    )
                }
            } catch (e: Exception) {
                Log.e(TAG, "[MatchRepo] Secondary fetch failed: ${e.message}")
                emptyList()
            }
        } else emptyList()

        val liveScoresSource = if (apiSportsMatches.isNotEmpty()) apiSportsMatches else secondaryMatches

        val nexusMatches = try {
            nexusProvider.getLiveEvents()
        } catch (e: Exception) {
            emptyList()
        }

        // FETCH HOCKEY SCORES
        val hockeyScores = if (nexusMatches.any { it.category?.lowercase()?.trim() == "hockey" }) {
            try {
                val today = SimpleDateFormat("yyyy-MM-dd", Locale.getDefault()).format(Date())
                hockeyApi.getGames(hockeyApiKey, today).response ?: emptyList()
            } catch (e: Exception) {
                emptyList()
            }
        } else emptyList()
        
        // FETCH CRICKET SCORES
        val cricketScores = if (nexusMatches.any { it.category?.lowercase()?.trim() == "cricket" }) {
            try {
                val today = SimpleDateFormat("yyyy-MM-dd", Locale.getDefault()).format(Date())
                cricketApi.getMatches(apiKey = hockeyApiKey, dateStart = today, dateStop = today).result ?: emptyList()
            } catch (e: Exception) {
                emptyList()
            }
        } else emptyList()

        val allMatches = (liveScoresSource + nexusMatches)
            .groupBy { getMatchKey(it) }
            .map { (_, group) ->
                val nexus = group.find { it.id.contains("nexus") }
                val scoreSource = group.find { !it.id.contains("nexus") }
                
                if (nexus != null && scoreSource != null) {
                    // PRIORITIZE: Take the match structure from scoreSource but keep the nexus ID for streams
                    scoreSource.copy(
                        id = nexus.id,
                        category = scoreSource.category.ifEmpty { nexus.category }
                    )
                } else if (nexus != null) {
                    // Try to find a score for this nexus match in our score source even if IDs don't match
                    val mKey = getMatchKey(nexus)
                    val scores = liveScoresSource.find { getMatchKey(it) == mKey }
                    if (scores != null) {
                        nexus.copy(
                            homeScore = scores.homeScore,
                            awayScore = scores.awayScore,
                            status = scores.status,
                            statusText = scores.statusText
                        )
                    } else nexus
                } else {
                    group.first()
                }
            }
            .map { match ->
            val cat = match.category?.lowercase()?.trim() ?: ""
            if (cat == "hockey" && match.status == com.pixelperfect.fotty.data.models.MatchStatus.LIVE) {
                val hockeyMatch = hockeyScores.find { h ->
                    val hh = normalizeTeamName(h.teams?.home?.name ?: "")
                    val ha = normalizeTeamName(h.teams?.away?.name ?: "")
                    val mh = normalizeTeamName(match.homeTeam.name)
                    val ma = normalizeTeamName(match.awayTeam.name)
                    (hh.contains(mh) || mh.contains(hh)) && (ha.contains(ma) || ma.contains(ha))
                }
                if (hockeyMatch != null) {
                    match.copy(
                        homeScore = hockeyMatch.scores?.home,
                        awayScore = hockeyMatch.scores?.away,
                        statusText = hockeyMatch.status?.short ?: match.statusText
                    )
                } else match
            } else if (cat == "cricket" && match.status == com.pixelperfect.fotty.data.models.MatchStatus.LIVE) {
                val cricketMatch = cricketScores.find { c ->
                    val ch = normalizeTeamName(c.event_home_team ?: "")
                    val ca = normalizeTeamName(c.event_away_team ?: "")
                    val mh = normalizeTeamName(match.homeTeam.name)
                    val ma = normalizeTeamName(match.awayTeam.name)
                    (ch.contains(mh) || mh.contains(ch)) && (ca.contains(ma) || ma.contains(ca))
                }
                if (cricketMatch != null) {
                    val scoreText = cricketMatch.score ?: "${cricketMatch.event_home_final_score ?: ""} vs ${cricketMatch.event_away_final_score ?: ""}"
                    match.copy(statusText = scoreText.trim().ifEmpty { "Live Pulse" })
                } else {
                    match.copy(statusText = "Live Pulse")
                }
            } else match
        }
        
        liveFixturesCache = allMatches
        lastLiveFetch = now
        _liveMatches.value = allMatches
        
        return allMatches
    }

    suspend fun getStreamsForEvent(eventId: String): List<com.pixelperfect.fotty.core.network.models.streaming.StreamSource> {
        return nexusProvider.getStreamsForCachedEvent(eventId)
    }

    suspend fun getP2PStreams(eventId: String, homeTeam: String, awayTeam: String, category: String): List<com.pixelperfect.fotty.core.network.models.streaming.StreamSource> {
        return p2pService.findStreams(eventId, homeTeam, awayTeam, category)
    }

    fun findNexusMatchIdByTeams(home: String, away: String): String? {
        val nh = normalizeTeamName(home)
        val na = normalizeTeamName(away)
        return nexusProvider.findMatchIdByNormalizedTeams(nh, na)
    }
}
