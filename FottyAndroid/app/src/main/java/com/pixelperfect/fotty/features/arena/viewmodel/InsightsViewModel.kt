package com.pixelperfect.fotty.features.arena.viewmodel

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.pixelperfect.fotty.core.network.models.football.*
import com.pixelperfect.fotty.core.network.repository.football.FootballRepository
import com.pixelperfect.fotty.core.network.repository.football.toAPIFootballFixture
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.launch
import kotlinx.coroutines.async
import kotlinx.coroutines.awaitAll
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import android.util.Log
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.stateIn
import javax.inject.Inject

@HiltViewModel
class InsightsViewModel @Inject constructor(
    private val repository: FootballRepository,
    private val preferencesRepository: com.pixelperfect.fotty.core.storage.UserPreferencesRepository,
    val licenseManager: com.pixelperfect.fotty.core.LicenseManager,
    val securityManager: com.pixelperfect.fotty.core.util.AppSecurityManager
) : ViewModel() {

    val followedTeams: StateFlow<Set<String>> = preferencesRepository.followedTeams
        .stateIn(viewModelScope, SharingStarted.WhileSubscribed(5000), emptySet())

    private val _liveMatches = MutableStateFlow<List<APIFootballFixture>>(emptyList())
    val liveMatches: StateFlow<List<APIFootballFixture>> = _liveMatches.asStateFlow()

    private val _isLoading = MutableStateFlow(false)
    val isLoading: StateFlow<Boolean> = _isLoading.asStateFlow()

    private val _selectedMatchStats = MutableStateFlow<List<APIFootballTeamStats>>(emptyList())
    val selectedMatchStats: StateFlow<List<APIFootballTeamStats>> = _selectedMatchStats.asStateFlow()

    private val _selectedMatchLineups = MutableStateFlow<List<APIFootballLineup>>(emptyList())
    val selectedMatchLineups: StateFlow<List<APIFootballLineup>> = _selectedMatchLineups.asStateFlow()

    private val _selectedMatchEvents = MutableStateFlow<List<APIFootballEvent>>(emptyList())
    val selectedMatchEvents: StateFlow<List<APIFootballEvent>> = _selectedMatchEvents.asStateFlow()

    private val _matchMomentum = MutableStateFlow<List<Float>>(emptyList())
    val matchMomentum: StateFlow<List<Float>> = _matchMomentum.asStateFlow()

    private val _insights = MutableStateFlow<List<MatchInsight>>(emptyList())
    val insights: StateFlow<List<MatchInsight>> = _insights.asStateFlow()

    // --- Simple In-Memory Cache ---
    private var lastFetchTime: Long = 0
    private val CACHE_TTL = 5 * 60 * 1000 // 5 minutes

    init {
        refreshLiveMatches()
    }

    private val bigLeagueIds = listOf(
        // API-Football IDs
        1, 2, 3, 4, 9, 39, 61, 78, 135, 140, 848,
        // Football-Data.org IDs (Discovery Fallback)
        2001, 2002, 2014, 2015, 2019, 2021
    )

    fun refreshLiveMatches(force: Boolean = false) {
        val now = System.currentTimeMillis()
        if (!force && _liveMatches.value.isNotEmpty() && (now - lastFetchTime) < CACHE_TTL) {
            return
        }

        viewModelScope.launch {
            _isLoading.value = true
            try {
                // 1. Fetch Live Scores (Immediate priority from API-Football)
                val allLiveMatches = repository.getGlobalLiveScores()
                
                // 2. Fetch Recent Results (Parallelized league history fetches)
                val sdf = java.text.SimpleDateFormat("yyyy-MM-dd", java.util.Locale.US)
                val calendar = java.util.Calendar.getInstance()
                val dateTo = sdf.format(calendar.time)
                calendar.add(java.util.Calendar.DAY_OF_YEAR, -14)
                val dateFrom = sdf.format(calendar.time)
                
                val leagueCodes = listOf("PL", "CL", "BL1", "SA", "PD", "FL1")
                val historyJobs = leagueCodes.map { leagueCode ->
                    async {
                        try {
                            repository.getMatchesByDateRange(leagueCode, dateFrom, dateTo)
                                .map { it.toAPIFootballFixture() }
                        } catch (e: Exception) {
                            emptyList<APIFootballFixture>()
                        }
                    }
                }
                
                val recentMatches = historyJobs.awaitAll().flatten()
                val combinedMatches = (allLiveMatches + recentMatches).distinctBy { it.fixture.id }

                // 3. Filter and Priority
                val filteredMatches = combinedMatches.filter { 
                    it.league.id in bigLeagueIds || it.fixture.status.short in listOf("1H", "2H", "HT", "LIVE") 
                }
                
                // 4. Absolute Fallback
                _liveMatches.value = if (filteredMatches.isEmpty()) {
                    combinedMatches.sortedByDescending { it.fixture.id }.take(30)
                } else {
                    filteredMatches
                }
                
                lastFetchTime = now
            } catch (e: Exception) {
                android.util.Log.e("InsightsViewModel", "Critical failure in match fetch", e)
            } finally {
                _isLoading.value = false
            }
        }
    }

    fun loadMatchInsights(fixtureId: Int) {
        val currentFixture = _liveMatches.value.find { it.fixture.id == fixtureId }
        viewModelScope.launch {
            _isLoading.value = true
            try {
                // Parallel fetch of stats, lineups, and events
                val statsDeferred = async { repository.getMatchStatistics(fixtureId) }
                val lineupsDeferred = async { repository.getMatchLineups(fixtureId) }
                val eventsDeferred = async { repository.getMatchEvents(fixtureId) }
                
                _selectedMatchStats.value = statsDeferred.await()
                _selectedMatchLineups.value = lineupsDeferred.await()
                val events = eventsDeferred.await()
                _selectedMatchEvents.value = events
                
                // ── Calculate Match Momentum ──
                val momentum = MutableList(90) { 0f }
                events.forEach { event ->
                    val minute = (event.time.elapsed ?: 1).coerceIn(1, 90) - 1
                    val weight = when (event.type.lowercase()) {
                        "goal" -> 20f
                        "card" -> -5f
                        "subst" -> 2f
                        else -> 1f
                    }
                    val teamMultiplier = if (event.team.id == (currentFixture?.teams?.home?.id ?: 0)) 1f else -1f
                    momentum[minute] += weight * teamMultiplier
                }
                _matchMomentum.value = momentum.toList()
                
                // ── Generate Smart Insights ──
                val newInsights = mutableListOf<MatchInsight>()
                val homeStats = _selectedMatchStats.value.getOrNull(0)?.statistics ?: emptyList()
                val awayStats = _selectedMatchStats.value.getOrNull(1)?.statistics ?: emptyList()

                fun getStat(stats: List<APIFootballStatistic>, type: String): Float {
                    val element = stats.find { it.type == type }?.value
                    return if (element is kotlinx.serialization.json.JsonPrimitive) {
                        element.content.replace("%", "").toFloatOrNull() ?: 0f
                    } else 0f
                }

                val homeXG = getStat(homeStats, "Expected Goals (xG)")
                val awayXG = getStat(awayStats, "Expected Goals (xG)")
                val homeGoals = currentFixture?.goals?.home ?: 0
                val awayGoals = currentFixture?.goals?.away ?: 0

                if (homeXG > homeGoals + 0.5f) {
                    newInsights.add(MatchInsight("UNLUCKY HOME", "${currentFixture?.teams?.home?.name} is creating quality chances but failing to convert (xG: %.2f)".format(homeXG), InsightType.STATISTICAL, fixtureId))
                }
                if (momentum.filter { it > 5f }.size > 5) {
                    newInsights.add(MatchInsight("HIGH PRESSURE", "Home team is sustaining heavy attacking pressure in the last 15 minutes.", InsightType.MOMENTUM, fixtureId))
                }
                if (homeXG + awayXG > 3.0f) {
                    newInsights.add(MatchInsight("OPEN GAME", "Both sides are abandoning defensive structure for offensive output.", InsightType.TACTICAL, fixtureId))
                }

                _insights.value = newInsights
                
            } catch (e: Exception) {
                android.util.Log.e("InsightsViewModel", "STABILIZATION: Critical error in insights load", e)
            } finally {
                _isLoading.value = false
            }
        }
    }

    private fun normalizeTeamName(name: String): String {
        return com.pixelperfect.fotty.core.util.TeamNameNormalizer.normalize(name)
    }

    fun toggleFollowTeam(teamId: String) {
        viewModelScope.launch {
            val current = followedTeams.value
            if (current.contains(teamId)) {
                preferencesRepository.unfollowTeam(teamId)
            } else {
                preferencesRepository.followTeam(teamId)
            }
        }
    }
}

data class MatchInsight(
    val title: String,
    val description: String,
    val type: InsightType,
    val fixtureId: Int
)

enum class InsightType {
    TACTICAL, STATISTICAL, MOMENTUM
}

