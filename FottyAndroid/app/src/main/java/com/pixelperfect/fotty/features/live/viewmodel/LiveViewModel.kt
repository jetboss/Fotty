package com.pixelperfect.fotty.features.live.viewmodel

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.pixelperfect.fotty.data.models.Match
import com.pixelperfect.fotty.data.models.MatchStatus
import com.pixelperfect.fotty.data.repositories.MatchRepository
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import javax.inject.Inject

@HiltViewModel
class LiveViewModel @Inject constructor(
    private val repository: MatchRepository
) : ViewModel() {

    private val _allMatches = MutableStateFlow<List<Match>>(emptyList())
    private val _selectedSport = MutableStateFlow("Football")
    val selectedSport: StateFlow<String> = _selectedSport.asStateFlow()
    private val _selectedLeague = MutableStateFlow("All Leagues")
    val selectedLeague: StateFlow<String> = _selectedLeague.asStateFlow()
    private val _forYouMatches = MutableStateFlow<List<Match>>(emptyList())
    val forYouMatches: StateFlow<List<Match>> = _forYouMatches.asStateFlow()
    
    val sports = listOf("Football", "Basketball", "Fighting", "Baseball", "Hockey", "Other")
    val leagues: StateFlow<List<String>> = MutableStateFlow(listOf("All Leagues", "Premier League", "Champions League", "La Liga", "Serie A", "Bundesliga", "Ligue 1")).asStateFlow()

    private val _isLoading = MutableStateFlow(false)
    private val _error = MutableStateFlow<String?>(null)

    val uiState: StateFlow<LiveUiState> = kotlinx.coroutines.flow.combine(
        _allMatches,
        _selectedSport,
        _selectedLeague,
        _isLoading,
        _error
    ) { matches, sport, league, loading, error ->
        android.util.Log.d("LiveViewModel", "UI State Pipe -> Matches: ${matches.size} | Loading: $loading | Error: $error")
        
        if (error != null && matches.isEmpty()) {
            return@combine LiveUiState.Error(error)
        }
        
        val filtered = matches.filter { match ->
            val matchSport = match.category.lowercase()
            val sportMatches = if (sport.lowercase() == "other") {
                matchSport !in listOf("football", "basketball", "fighting", "baseball", "hockey")
            } else {
                matchSport == sport.lowercase()
            }
            
            val leagueMatches = if (league == "All Leagues") {
                true
            } else {
                val ml = match.league.name.lowercase().trim()
                val sl = league.lowercase().trim()
                ml.contains(sl) || sl.contains(ml)
            }
            
            sportMatches && leagueMatches
        }

        android.util.Log.d("LiveViewModel", "UI State Pipe -> Filtered Matches: ${filtered.size}")

        when {
            loading && filtered.isEmpty() -> LiveUiState.Loading
            filtered.isEmpty() -> LiveUiState.Empty
            else -> LiveUiState.Success(filtered)
        }
    }.stateIn(viewModelScope, SharingStarted.WhileSubscribed(5000), LiveUiState.Loading)


    init {
        refresh()
        startPeriodicRefresh()
    }

    private fun startPeriodicRefresh() {
        viewModelScope.launch {
            while (true) {
                kotlinx.coroutines.delay(30_000)
                android.util.Log.d("LiveViewModel", "PITCH: Periodic Refresh Triggered")
                refresh()
            }
        }
    }

    fun setSport(sport: String) {
        _selectedSport.value = sport
        _selectedLeague.value = "All Leagues"
        _error.value = null
    }

    fun setLeague(league: String) {
        _selectedLeague.value = league
        _error.value = null
    }

    fun refresh() {
        viewModelScope.launch {
            _isLoading.value = true
            _error.value = null
            try {
                android.util.Log.d("LiveViewModel", "🚀 Refreshing fixtures...")
                
                // Use the full daily pool (Live + Upcoming) for the Live tab to act as the daily schedule
                val matches = repository.getDailyFixtures()
                android.util.Log.d("LiveViewModel", "Total daily matches found: ${matches.size}")

                // Warm the stream extractor cache in background
                viewModelScope.launch(kotlinx.coroutines.Dispatchers.IO) {
                    try {
                        com.pixelperfect.fotty.core.extractors.LiveSportsExtractor.fetchLiveEvents()
                    } catch (e: Exception) {
                        android.util.Log.w("LiveViewModel", "Failed to warm extractor cache: ${e.message}")
                    }
                }
                
                if (matches.isEmpty()) {
                    // If even daily is empty, it might be a silent API issue or just a dead day
                    // We don't necessarily set an error here, but we could if we wanted to be aggressive
                }
                
                android.util.Log.d("LiveViewModel", "Final match list size: ${matches.size}")
                _allMatches.value = matches
                _forYouMatches.value = matches.filter { it.hypeLevel > 0.7f || it.status == MatchStatus.LIVE }.take(5)
            } catch (e: Exception) {
                android.util.Log.e("LiveViewModel", "Refresh failed: ${e.message}")
                _error.value = e.message ?: "An unexpected error occurred"
            } finally {
                _isLoading.value = false
            }
        }
    }
}


sealed class LiveUiState {
    object Loading : LiveUiState()
    data class Success(val matches: List<Match>) : LiveUiState()
    object Empty : LiveUiState()
    data class Error(val message: String) : LiveUiState()
}
