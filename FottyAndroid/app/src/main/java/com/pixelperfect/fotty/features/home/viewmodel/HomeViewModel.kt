package com.pixelperfect.fotty.features.home.viewmodel

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.pixelperfect.fotty.data.models.Match
import com.pixelperfect.fotty.data.repositories.MatchRepository
import com.pixelperfect.fotty.data.repositories.MockDataProvider
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.delay
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import com.pixelperfect.fotty.data.models.NewsItem
import javax.inject.Inject

@HiltViewModel
class HomeViewModel @Inject constructor(
    private val repository: MatchRepository,
    private val preferencesRepository: com.pixelperfect.fotty.core.storage.UserPreferencesRepository,
    private val newsRepository: com.pixelperfect.fotty.data.repositories.NewsRepository
) : ViewModel() {

    private val _uiState = MutableStateFlow<HomeUiState>(HomeUiState.Loading)
    val uiState: StateFlow<HomeUiState> = _uiState

    private val _selectedCategory = MutableStateFlow("football")
    val selectedCategory: StateFlow<String> = _selectedCategory

    // SAFETY TOGGLE: Set to false for production live data
    var isMockMode by mutableStateOf(false)

    fun selectCategory(category: String) {
        _selectedCategory.value = category
    }

    private var pollingJob: kotlinx.coroutines.Job? = null

    init {
        refresh()
        startPolling()
    }

    fun startPolling() {
        pollingJob?.cancel()
        pollingJob = viewModelScope.launch {
            // Observe followed teams to trigger refreshes when interests change
            launch {
                preferencesRepository.followedTeams.collect {
                    refresh(silent = true)
                }
            }

            while (isActive) {
                delay(30_000) // 30 second pulse parity
                refresh(silent = true)
            }
        }
    }

    fun refresh(silent: Boolean = false) {
        viewModelScope.launch {
            if (!silent) _uiState.value = HomeUiState.Loading
            try {
                // If live, we force a refresh from repository to get latest scores
                val matches = if (isMockMode) {
                    MockDataProvider.liveMatches + MockDataProvider.upcomingMatches
                } else {
                    repository.getDailyFixtures(forceRefresh = silent)
                }

                // 2. Fetch News based on interests
                val followedTeams = preferencesRepository.followedTeams.first()
                val followedLeagues = preferencesRepository.followedLeagues.first()
                val news = newsRepository.getNewsForInterests(followedTeams, followedLeagues)

                if (matches.isEmpty() && news.isEmpty()) {
                    _uiState.value = HomeUiState.Empty
                } else {
                    val live = matches.filter { it.status == com.pixelperfect.fotty.data.models.MatchStatus.LIVE }
                        .sortedByDescending { it.activePeers }
                    
                    // SMART HERO SELECTION: Priority = (Followed Live) > (All Live) > (Followed Upcoming) > (All Upcoming)
                    val hero = matches.find { it.status == com.pixelperfect.fotty.data.models.MatchStatus.LIVE && followedTeams.contains(it.homeTeam.id) }
                        ?: live.firstOrNull()
                        ?: matches.find { followedTeams.contains(it.homeTeam.id) }
                        ?: matches.firstOrNull()

                    val categories = (matches).map { it.category }.distinct()
                    
                    _uiState.value = HomeUiState.Success(
                        heroMatch = hero,
                        liveMatches = live,
                        newsFeed = news,
                        availableCategories = categories
                    )
                    
                    if (!categories.contains(_selectedCategory.value)) {
                        _selectedCategory.value = if (categories.contains("football")) "football" else categories.firstOrNull() ?: "football"
                    }
                }
            } catch (e: Exception) {
                if (!silent) _uiState.value = HomeUiState.Error(e.message ?: "Unknown Error")
            }
        }
    }

    override fun onCleared() {
        super.onCleared()
        pollingJob?.cancel()
    }
}

sealed class HomeUiState {
    object Loading : HomeUiState()
    data class Success(
        val heroMatch: com.pixelperfect.fotty.data.models.Match?,
        val liveMatches: List<com.pixelperfect.fotty.data.models.Match>,
        val newsFeed: List<com.pixelperfect.fotty.data.models.NewsItem> = emptyList(),
        val availableCategories: List<String> = emptyList()
    ) : HomeUiState()
    object Empty : HomeUiState()
    data class Error(val message: String) : HomeUiState()
}
