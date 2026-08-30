package com.pixelperfect.fotty.features.player.viewmodel

import android.app.Application
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import androidx.media3.common.MediaItem
import androidx.media3.common.PlaybackException
import androidx.media3.common.Player
import androidx.media3.exoplayer.ExoPlayer
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch

sealed class PlaybackState {
    object Idle : PlaybackState()
    object Buffering : PlaybackState()
    object Ready : PlaybackState()
    object Ended : PlaybackState()
    data class Error(val message: String) : PlaybackState()
}

class StreamPlayerViewModel(application: Application) : AndroidViewModel(application) {

    private var _player: ExoPlayer? = null
    val player: Player? get() = _player

    private val _playbackState = MutableStateFlow<PlaybackState>(PlaybackState.Idle)
    val playbackState = _playbackState.asStateFlow()

    private val _currentPosition = MutableStateFlow(0L)
    val currentPosition = _currentPosition.asStateFlow()

    private val _duration = MutableStateFlow(0L)
    val duration = _duration.asStateFlow()

    init {
        initializePlayer()
    }

    private fun initializePlayer() {
        _player = ExoPlayer.Builder(getApplication())
            .build()
            .apply {
                addListener(object : Player.Listener {
                    override fun onPlaybackStateChanged(state: Int) {
                        _playbackState.value = when (state) {
                            Player.STATE_BUFFERING -> PlaybackState.Buffering
                            Player.STATE_READY -> PlaybackState.Ready
                            Player.STATE_ENDED -> PlaybackState.Ended
                            else -> PlaybackState.Idle
                        }
                        if (state == Player.STATE_READY) {
                            _duration.value = duration
                        }
                    }

                    override fun onPlayerError(error: PlaybackException) {
                        _playbackState.value = PlaybackState.Error(error.localizedMessage ?: "Unknown Error")
                    }
                })
            }
        
        startPositionTracker()
    }

    private fun startPositionTracker() {
        viewModelScope.launch {
            while (true) {
                _player?.let {
                    if (it.isPlaying) {
                        _currentPosition.value = it.currentPosition
                    }
                }
                delay(1000)
            }
        }
    }

    fun playStream(url: String) {
        val mediaItem = MediaItem.fromUri(url)
        _player?.setMediaItem(mediaItem)
        _player?.prepare()
        _player?.play()
    }

    fun togglePlayPause() {
        _player?.let {
            if (it.isPlaying) it.pause() else it.play()
        }
    }

    fun seekTo(position: Long) {
        _player?.seekTo(position)
    }

    override fun onCleared() {
        super.onCleared()
        releasePlayer()
    }

    private fun releasePlayer() {
        _player?.release()
        _player = null
    }
}
