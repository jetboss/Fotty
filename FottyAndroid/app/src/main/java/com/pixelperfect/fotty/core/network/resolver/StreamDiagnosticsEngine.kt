package com.pixelperfect.fotty.core.network.resolver

import android.util.Log
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow
import java.util.*
import javax.inject.Inject
import javax.inject.Singleton

@Singleton
class StreamDiagnosticsEngine @Inject constructor() {
    
    private val _currentTimeline = MutableStateFlow<List<DiagnosticEvent>>(emptyList())
    val currentTimeline = _currentTimeline.asStateFlow()

    private var activeAttemptId: String? = null

    fun startNewAttempt(attemptId: String, matchTitle: String) {
        activeAttemptId = attemptId
        _currentTimeline.value = listOf(
            DiagnosticEvent(
                name = "Attempt Started",
                message = "Resolving streams for: $matchTitle",
                attemptId = attemptId
            )
        )
        Log.d(TAG, "Diagnostic Session Started: $attemptId")
    }

    fun recordEvent(name: String, message: String, metadata: Map<String, String> = emptyMap()) {
        val event = DiagnosticEvent(
            name = name,
            message = message,
            attemptId = activeAttemptId ?: "Unknown",
            metadata = metadata
        )
        _currentTimeline.value = _currentTimeline.value + event
        Log.d(TAG, "[DIAG] $name: $message | Meta: $metadata")
    }

    fun recordError(name: String, message: String, error: Throwable? = null) {
        val metadata = mutableMapOf<String, String>()
        error?.let { metadata["exception"] = it.javaClass.simpleName; metadata["reason"] = it.message ?: "No message" }
        recordEvent(name, message, metadata)
    }

    fun clear() {
        activeAttemptId = null
        _currentTimeline.value = emptyList()
    }

    companion object {
        private const val TAG = "StreamDiagnostics"
    }
}

data class DiagnosticEvent(
    val id: String = UUID.randomUUID().toString(),
    val timestamp: Long = System.currentTimeMillis(),
    val name: String,
    val message: String,
    val attemptId: String,
    val metadata: Map<String, String> = emptyMap()
)
