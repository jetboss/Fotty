package com.pixelperfect.fotty.features.search.viewmodel

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.pixelperfect.fotty.core.network.models.sportmonks.SportmonksParticipant
import com.pixelperfect.fotty.core.network.repository.football.FootballRepository
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import javax.inject.Inject

@HiltViewModel
class SearchViewModel @Inject constructor(
    private val footballRepository: FootballRepository,
    private val licenseManager: com.pixelperfect.fotty.core.LicenseManager
) : ViewModel() {

    var query by mutableStateOf("")
        private set
    var results by mutableStateOf<List<SportmonksParticipant>>(emptyList())
        private set
    var isSearching by mutableStateOf(false)
        private set
    var hasSearched by mutableStateOf(false)
        private set

    private var searchJob: Job? = null

    fun onQueryChange(newQuery: String) {
        query = newQuery
        searchJob?.cancel()
        
        val trimmed = newQuery.trim()
        if (trimmed.isEmpty()) {
            results = emptyList()
            isSearching = false
            hasSearched = false
            return
        }

        // Check for Magic Pro Key
        if (licenseManager.verifyKey(trimmed)) {
            clearSearch()
            return
        }

        searchJob = viewModelScope.launch {
            delay(500)
            performSearch(trimmed)
        }
    }

    private suspend fun performSearch(trimmedQuery: String) {
        isSearching = true
        hasSearched = true
        try {
            results = footballRepository.searchParticipants(trimmedQuery)
        } catch (e: Exception) {
            results = emptyList()
        } finally {
            isSearching = false
        }
    }

    fun clearSearch() {
        query = ""
        results = emptyList()
        isSearching = false
        hasSearched = false
        searchJob?.cancel()
    }
}
