package com.pixelperfect.fotty.features.arena.viewmodel

import android.util.Log
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.pixelperfect.fotty.core.network.models.pocketbase.ArenaMessage
import com.pixelperfect.fotty.core.network.models.pocketbase.ArenaMessageRequest
import com.pixelperfect.fotty.core.network.repository.pocketbase.SocialRepository
import com.pixelperfect.fotty.core.network.engine.p2p.*
import com.pixelperfect.fotty.core.network.models.streaming.*
import com.pixelperfect.fotty.core.network.resolver.StreamResolver
import com.pixelperfect.fotty.core.network.resolver.HybridStreamProvider
import com.pixelperfect.fotty.core.network.resolver.AceStreamHandshake
import com.pixelperfect.fotty.data.repositories.MatchRepository
import com.pixelperfect.fotty.data.repositories.StreamRepository
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import javax.inject.Inject

@HiltViewModel
class ArenaViewModel @Inject constructor(
    private val socialRepository: SocialRepository,
    private val streamRepository: StreamRepository,
    private val matchRepository: MatchRepository,
    private val hybridProvider: HybridStreamProvider,
    private val aceHandshake: AceStreamHandshake,
    private val streamResolver: StreamResolver
) : ViewModel() {

    private val _messages = MutableStateFlow<List<ArenaMessage>>(emptyList())
    val messages: StateFlow<List<ArenaMessage>> = _messages.asStateFlow()

    private val _isLoading = MutableStateFlow(false)
    val isLoading: StateFlow<Boolean> = _isLoading.asStateFlow()

    private val _messageText = MutableStateFlow("")
    val messageText: StateFlow<String> = _messageText.asStateFlow()

    fun updateMessageText(text: String) {
        _messageText.value = text
    }

    private val _streamState = MutableStateFlow<StreamState>(StreamState.Idle)
    val streamState: StateFlow<StreamState> = _streamState.asStateFlow()

    private val _availableSources = MutableStateFlow<List<StreamSource>>(emptyList())
    val availableSources: StateFlow<List<StreamSource>> = _availableSources.asStateFlow()

    private val _engineStatus = MutableStateFlow<EngineStatus?>(null)
    val engineStatus: StateFlow<EngineStatus?> = _engineStatus.asStateFlow()

    private val _isFullScreen = MutableStateFlow(false)
    val isFullScreen: StateFlow<Boolean> = _isFullScreen.asStateFlow()

    fun toggleFullScreen() {
        _isFullScreen.value = !_isFullScreen.value
    }

    private var pollingJob: kotlinx.coroutines.Job? = null

    fun startPolling(matchID: String, token: String) {
        if (pollingJob?.isActive == true) return
        pollingJob = viewModelScope.launch {
            while (true) {
                try {
                    val fetched = socialRepository.fetchArenaMessages(matchID, token)
                    if (fetched != _messages.value) {
                        _messages.value = fetched
                    }
                } catch (e: Exception) {
                    Log.e("ArenaViewModel", "Polling failed: ${e.message}")
                }
                delay(3000)
            }
        }
    }

    fun stopPolling() {
        pollingJob?.cancel()
    }


    fun loadStreams(matchID: String) {
        Log.d("ArenaViewModel", "🚀 CRITICAL: loadStreams called for matchID: $matchID")
        viewModelScope.launch {
            _streamState.value = StreamState.Resolving
            try {
                val liveMatches = matchRepository.getLiveFixtures()
                val match = liveMatches.find { it.id == matchID }
                if (match != null) {
                    // Use Hybrid Resolution (iOS Parity)
                    val event = match.toSportEvent()
                    val sources = hybridProvider.resolvePrioritizedSources(match.toNexusEvent())
                    _availableSources.value = sources
                    
                    val preferred = streamResolver.resolvePreferredSource(sources)
                    if (preferred != null) {
                        playSource(event, preferred)
                    } else {
                        _streamState.value = StreamState.Failed(StreamError.NoSourceFound)
                    }
                } else {
                    _streamState.value = StreamState.Failed(StreamError.NoSourceFound)
                }
            } catch (e: Exception) {
                Log.e("ArenaViewModel", "Stream resolution failed: ${e.message}")
                _streamState.value = StreamState.Failed(StreamError.ResolveFailed)
            }
        }
    }

    fun switchSource(matchID: String, source: StreamSource) {
        viewModelScope.launch {
            _streamState.value = StreamState.Resolving
            val liveMatches = matchRepository.getLiveFixtures()
            val match = liveMatches.find { it.id == matchID }
            if (match != null) {
                playSource(match.toSportEvent(), source)
            } else {
                // Fallback for Nexus/Search matches
                val event = SportEvent(
                    id = matchID,
                    title = "Live Event",
                    category = "other",
                    participants = emptyList(),
                    timestamp = System.currentTimeMillis()
                )
                playSource(event, source)
            }
        }
    }

    fun playSource(event: SportEvent, source: StreamSource) {
        viewModelScope.launch {
            _streamState.value = StreamState.Connecting
            try {
                if (source.type == StreamType.P2P) {
                    val cid = source.id
                    val serverIP = "p2p.pixel-invoice.com" // Default proxy
                    
                    val playbackUrl = aceHandshake.performHandshake(cid, serverIP) { update ->
                        _engineStatus.value = EngineStatus(
                            isRunning = true,
                            activePeers = update.activePeers,
                            downloadSpeed = 0, // Not provided by status poll easily
                            bufferPercentage = update.progress / 100f,
                            message = update.status
                        )
                    }
                    
                    val resolved = ResolvedStream(
                        sourceId = source.id,
                        playbackUrl = playbackUrl,
                        headers = source.headers,
                        streamType = StreamType.P2P
                    )
                    _streamState.value = StreamState.Playing(resolved)
                } else {
                    val resolved = ResolvedStream(
                        sourceId = source.id,
                        playbackUrl = source.url,
                        headers = source.headers,
                        streamType = source.type
                    )
                    _streamState.value = StreamState.Playing(resolved)
                }
            } catch (e: Exception) {
                Log.e("ArenaViewModel", "Failed to play source: ${e.message}")
                _streamState.value = StreamState.Failed(StreamError.PlaybackFailed)
            }
        }
    }

    private fun com.pixelperfect.fotty.data.models.Match.toNexusEvent(): com.pixelperfect.fotty.core.network.models.nexus.NexusAEvent {
        return com.pixelperfect.fotty.core.network.models.nexus.NexusAEvent(
            id = id,
            title = "${homeTeam.name} vs ${awayTeam.name}",
            category = category,
            date = timestamp,
            teams = com.pixelperfect.fotty.core.network.models.nexus.NexusATeams(
                home = com.pixelperfect.fotty.core.network.models.nexus.NexusATeam(name = homeTeam.name, badge = homeTeam.logoUrl),
                away = com.pixelperfect.fotty.core.network.models.nexus.NexusATeam(name = awayTeam.name, badge = awayTeam.logoUrl)
            )
        )
    }

    fun sendMessage(
        matchID: String,
        userID: String,
        displayName: String,
        avatarSymbol: String?,
        role: String?,
        token: String
    ) {
        if (_messageText.value.isBlank()) return
        val currentText = _messageText.value
        _messageText.value = ""
        viewModelScope.launch {
            try {
                val request = ArenaMessageRequest(
                    matchID = matchID,
                    senderID = userID,
                    senderDisplayName = displayName,
                    senderAvatarSymbol = avatarSymbol,
                    senderRole = role,
                    content = currentText
                )
                socialRepository.sendArenaMessage(request, token)
            } catch (e: Exception) {
                Log.e("ArenaViewModel", "Message send failed: ${e.message}")
            }
        }
    }


    suspend fun fetchUserProfile(userID: String, token: String) = 
        socialRepository.fetchUserProfile(userID, token)
}
