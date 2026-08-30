package com.pixelperfect.fotty.core

import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.flow.asSharedFlow
import javax.inject.Inject
import javax.inject.Singleton

sealed class MatchEvent {
    data class Goal(val team: String, val player: String, val minute: Int) : MatchEvent()
    data class RedCard(val team: String, val player: String, val minute: Int) : MatchEvent()
    data class VAR(val decision: String) : MatchEvent()
}

@Singleton
class MatchDayHub @Inject constructor() {
    private val _events = MutableSharedFlow<MatchEvent>(extraBufferCapacity = 10)
    val events = _events.asSharedFlow()

    suspend fun publish(event: MatchEvent) {
        _events.emit(event)
    }
}
