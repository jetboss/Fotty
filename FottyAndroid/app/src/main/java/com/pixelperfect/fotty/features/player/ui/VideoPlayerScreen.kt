package com.pixelperfect.fotty.features.player.ui

import android.util.Log

import android.annotation.SuppressLint
import android.app.Activity
import android.content.Context
import android.content.ContextWrapper
import android.graphics.Bitmap
import android.net.Uri
import android.net.http.SslError
import android.webkit.JavascriptInterface
import android.webkit.CookieManager
import android.webkit.WebChromeClient
import android.webkit.WebResourceError
import android.webkit.WebResourceRequest
import android.webkit.WebResourceResponse
import android.webkit.WebSettings
import android.webkit.SslErrorHandler
import android.webkit.WebView
import android.webkit.WebViewClient
import kotlin.OptIn
import androidx.webkit.WebViewCompat
import androidx.webkit.WebViewFeature
import org.jsoup.Jsoup
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import androidx.hilt.navigation.compose.hiltViewModel
import androidx.compose.foundation.background
import androidx.compose.foundation.gestures.detectVerticalDragGestures
import androidx.compose.foundation.gestures.detectHorizontalDragGestures
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.layout.*
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Refresh
import androidx.compose.material.icons.filled.Menu
import androidx.compose.material.icons.filled.Settings
import androidx.compose.material.icons.filled.MoreVert
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.Info
import androidx.compose.material.icons.filled.Lock
import androidx.compose.material.icons.filled.PlayArrow
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.viewinterop.AndroidView
import androidx.compose.runtime.mutableLongStateOf
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.res.stringResource
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.BorderStroke
import com.pixelperfect.fotty.core.theme.Accent
import com.pixelperfect.fotty.core.network.models.streaming.StreamSource
import androidx.media3.common.MediaItem
import androidx.media3.common.MimeTypes
import androidx.media3.datasource.DefaultHttpDataSource
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.exoplayer.source.DefaultMediaSourceFactory
import android.media.AudioManager
import kotlinx.coroutines.delay
import java.util.Locale
import androidx.compose.material.icons.filled.AutoGraph
import androidx.compose.material.icons.filled.ArrowBack
import androidx.compose.material.icons.filled.Fullscreen
import androidx.compose.material.icons.filled.VolumeUp
import androidx.compose.material.icons.filled.BrightnessMedium
import androidx.core.view.WindowCompat
import androidx.core.view.WindowInsetsCompat
import androidx.core.view.WindowInsetsControllerCompat
import android.view.View
import androidx.compose.animation.*
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.media3.common.PlaybackException
import androidx.media3.common.Player
import androidx.media3.common.util.UnstableApi
import androidx.media3.ui.AspectRatioFrameLayout
import androidx.media3.ui.PlayerView
import kotlinx.coroutines.launch
import java.io.ByteArrayInputStream

@OptIn(UnstableApi::class, ExperimentalMaterial3Api::class)
@Composable
fun VideoPlayerScreen(
    playerState: com.pixelperfect.fotty.features.player.viewmodel.PlayerState,
    intelligenceState: com.pixelperfect.fotty.features.player.viewmodel.IntelligenceState,
    streamSource: StreamSource?,
    sources: List<StreamSource>,
    currentSourceIndex: Int,
    homeTeam: String? = null,
    awayTeam: String? = null,
    homeScore: Int? = null,
    awayScore: Int? = null,
    statusLabel: String? = null,
    category: String? = null,
    diagnostics: com.pixelperfect.fotty.features.player.viewmodel.DiagnosticInfo? = null,
    onSelectSource: (index: Int) -> Unit,
    onRequestNextSource: (reason: String) -> Boolean,
    onToggleIntelligence: () -> Unit,
    onBack: () -> Unit,
    globalP2PSources: List<StreamSource> = emptyList(),
    isFetchingGlobalP2P: Boolean = false,
    onSelectGlobalSource: (StreamSource) -> Unit = {},
    isPipMode: Boolean = false
) {
    val context = LocalContext.current
    EnableImmersiveLivePlayback()
    val scope = rememberCoroutineScope()
    
    // Native Extraction State
    var extractedUrl by remember { mutableStateOf<String?>(null) }
    var extractedHeaders by remember { mutableStateOf<Map<String, String>?>(null) }
    val isUsingExtractedNative = extractedUrl != null

    // Following iOS Template: We use direct player for media URLs, WebFallback for embeds.
    val useWebFallback = remember(streamSource?.url, isUsingExtractedNative) { 
        !isDirectMediaUrl(streamSource?.url.orEmpty()) && !isUsingExtractedNative 
    }

    var showOverlayControls by remember { mutableStateOf(true) }
    var overlayNonce by remember { mutableIntStateOf(0) }
    var showSourcePicker by remember { mutableStateOf(false) }
    var showP2PBrowser by remember { mutableStateOf(false) }
    var showSyncSettings by remember { mutableStateOf(false) }
    var showDebugInfo by remember { mutableStateOf(false) }
    var hasPlaybackStarted by remember(streamSource?.url, useWebFallback) { mutableStateOf(false) }
    var isBuffering by remember(streamSource?.url, useWebFallback) { mutableStateOf(true) }
    var statusHint by remember(streamSource?.url, useWebFallback) {
        mutableStateOf(
            if (useWebFallback) {
                "Initializing node fallback for ${streamSource?.provider}..."
            } else {
                "Connecting to ${streamSource?.provider}..."
            }
        )
    }

    // Pro Player States
    var isLocked by remember { mutableStateOf(false) }
    var showStats by remember { mutableStateOf(false) }
    var gestureHint by remember { mutableStateOf<String?>(null) }
    var gestureIcon by remember { mutableStateOf<ImageVector?>(null) }
    
    // Stats Data
    var currentRes by remember { mutableStateOf("---") }
    var currentBitrate by remember { mutableStateOf("---") }
    var currentBuffer by remember { mutableStateOf("0s") }
    
    val audioManager = remember { context.getSystemService(Context.AUDIO_SERVICE) as AudioManager }
    val activity = remember { context.findActivity() }

    val settingsViewModel: com.pixelperfect.fotty.features.settings.viewmodel.SettingsViewModel = hiltViewModel()
    val hapticsEnabled by settingsViewModel.hapticsEnabled.collectAsState()
    val streamQuality by settingsViewModel.streamQuality.collectAsState()
    
    val hapticManager = remember {
        dagger.hilt.android.EntryPointAccessors.fromApplication(
            context.applicationContext,
            com.pixelperfect.fotty.core.di.HapticEntryPoint::class.java
        ).hapticManager()
    }

    fun revealOverlayControls() {
        showOverlayControls = true
        overlayNonce += 1
        scope.launch { hapticManager.vibrateLight() }
    }

    fun triggerSourceFailover(reason: String, switchedHint: String, exhaustedHint: String) {
        val switched = onRequestNextSource(reason)
        val probeFailureClass = streamSource?.headers?.get("X-Fotty-P2P-Probe-Class")?.trim().orEmpty()
        val classifiedFailure = classifyFailureClass(reason)
        val failureClass = when {
            classifiedFailure != "unknown" -> classifiedFailure
            probeFailureClass.isNotBlank() -> probeFailureClass
            else -> "unknown"
        }
        val suffix = if (failureClass == "unknown") "" else " ($failureClass)"
        statusHint = if (switched) "$switchedHint$suffix" else "$exhaustedHint$suffix"
        revealOverlayControls()
        scope.launch { hapticManager.vibrateImpact() }
    }

    val exoPlayer = remember(streamSource?.url, streamSource?.headers, extractedUrl, useWebFallback, streamQuality) {
        if (useWebFallback) return@remember null

        val finalUrl = extractedUrl ?: streamSource?.url ?: return@remember null
        val finalHeaders = extractedHeaders ?: streamSource?.headers ?: emptyMap()
        val isP2PSource = isP2PStreamUrl(finalUrl)

        val dataSourceFactory = DefaultHttpDataSource.Factory()
            .setAllowCrossProtocolRedirects(true)
            .setConnectTimeoutMs(if (isP2PSource) 20_000 else 15_000)
            .setReadTimeoutMs(if (isP2PSource) 45_000 else 20_000)

        val allHeaders = HashMap(streamSource?.headers ?: emptyMap())
        extractedHeaders?.let { allHeaders.putAll(it) }

        val safariUA = "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1"
        val userAgent = allHeaders["User-Agent"] ?: safariUA
        dataSourceFactory.setUserAgent(userAgent)
        
        // MIRROR: Sync Cookies from WebView to Native Player
        try {
            val cookieManager = CookieManager.getInstance()
            val cookies = cookieManager.getCookie(finalUrl)
            if (!cookies.isNullOrBlank()) {
                allHeaders["Cookie"] = cookies
                Log.d("VideoPlayer", "Synced cookies for native playback: ${cookies.take(20)}...")
            }
        } catch (e: Exception) {
            Log.e("VideoPlayer", "Failed to sync cookies", e)
        }
        
        // HEURISTIC: Add Origin & Referer if missing. Use the real target host, not the proxy host.
        val realUrl = if (finalUrl.contains("127.0.0.1")) {
            Uri.decode(Uri.parse(finalUrl).getQueryParameter("url") ?: finalUrl)
        } else finalUrl
        val domain = Uri.parse(realUrl).host ?: ""
        
        if (allHeaders["Referer"].isNullOrBlank()) {
            allHeaders["Referer"] = "https://$domain/"
        }
        if (allHeaders["Origin"].isNullOrBlank()) {
            allHeaders["Origin"] = "https://$domain"
        }
        
        // SEC-FETCH: Mimic browser requests to bypass WAF
        allHeaders["Sec-Fetch-Dest"] = "video"
        allHeaders["Sec-Fetch-Mode"] = "cors"
        allHeaders["Sec-Fetch-Site"] = "cross-site"

        if (allHeaders.isNotEmpty()) {
            Log.d("VideoPlayer", "FINAL HEADERS for [${streamSource?.provider}] -> Referer: ${allHeaders["Referer"]} | User-Agent: $userAgent")
            dataSourceFactory.setDefaultRequestProperties(allHeaders)
        }
        
        Log.d("VideoPlayer", "Initializing ExoPlayer with URL: $finalUrl")

        val mediaSourceFactory = DefaultMediaSourceFactory(context).setDataSourceFactory(dataSourceFactory)

        // Keep P2P startup stable with a more robust buffer profile.
        val loadControl = androidx.media3.exoplayer.DefaultLoadControl.Builder()
            .setBufferDurationsMs(
                if (isP2PSource) 30_000 else 15_000, // minBuffer (Cushion for mesh stability)
                if (isP2PSource) 60_000 else 50_000, // maxBuffer
                if (isP2PSource) 2_500 else 1_500,  // bufferForPlayback (Quick start)
                if (isP2PSource) 5_000 else 2_500   // bufferForPlaybackAfterRebuffer (Recovery cushion)
            )
            .setPrioritizeTimeOverSizeThresholds(true)
            .build()

        ExoPlayer.Builder(context)
            .setMediaSourceFactory(mediaSourceFactory)
            .setLoadControl(loadControl)
            .build()
            .apply {
                setPlaybackSpeed(if (isP2PSource) 1.0f else 1.02f)

                // QUALITY LOGIC: Limit max bitrate if set to LOW
                if (streamQuality == "low") {
                    trackSelectionParameters = trackSelectionParameters.buildUpon()
                        .setMaxVideoBitrate(800_000)
                        .setMaxVideoSize(640, 360)
                        .build()
                } else if (streamQuality == "high") {
                    trackSelectionParameters = trackSelectionParameters.buildUpon()
                        .setForceHighestSupportedBitrate(true)
                        .build()
                }

                val mediaItem = MediaItem.Builder()
                    .setUri(finalUrl)
                    .setLiveConfiguration(
                        androidx.media3.common.MediaItem.LiveConfiguration.Builder()
                            .setTargetOffsetMs(if (isP2PSource) 4_500 else 1_000)
                            .setMinOffsetMs(if (isP2PSource) 2_000 else 500)
                            .setMaxOffsetMs(if (isP2PSource) 15_000 else 3_000)
                            .build()
                    )
                    .apply {
                        val normalizedUrl = finalUrl.lowercase(Locale.US)
                        val explicitMime = streamSource?.mimeType
                        
                        if (!explicitMime.isNullOrBlank()) {
                            setMimeType(explicitMime)
                        } else if (normalizedUrl.contains(".m3u8") || normalizedUrl.contains(".m3u") || streamSource?.type == com.pixelperfect.fotty.core.network.models.streaming.StreamType.HLS) {
                            setMimeType(MimeTypes.APPLICATION_M3U8)
                        } else if (normalizedUrl.contains("/proxy/acestream") || normalizedUrl.contains("/ace/getstream")) {
                            setMimeType(MimeTypes.VIDEO_MP2T)
                        } else if (normalizedUrl.contains(".mpd")) {
                            setMimeType(MimeTypes.APPLICATION_MPD)
                        } else if (isP2PSource) {
                            setMimeType(MimeTypes.APPLICATION_M3U8)
                        }
                    }
                    .build()
                setMediaItem(mediaItem)
                prepare()
                playWhenReady = true
            }
    }

    DisposableEffect(exoPlayer, useWebFallback) {
        val player = exoPlayer
        val viewModel = com.pixelperfect.fotty.features.player.viewmodel.PlayerViewModel::class.java // Just a reference
        if (player == null || useWebFallback) {
            onDispose { }
        } else {
            val listener = object : Player.Listener {
                override fun onPlaybackStateChanged(playbackState: Int) {
                    isBuffering = playbackState == Player.STATE_BUFFERING
                    if (playbackState == Player.STATE_READY) {
                        hasPlaybackStarted = true
                        statusHint = "Live • ${streamSource?.provider}"
                        // Notify VM of recovery if it was stalled
                        (playerState as? com.pixelperfect.fotty.features.player.viewmodel.PlayerState.PlaybackStalled)?.let {
                           // This is handled in VM via observation, but we can nudge here if needed
                        }
                    }
                }
                override fun onIsLoadingChanged(isLoading: Boolean) {
                    if (isLoading && exoPlayer?.playbackState == Player.STATE_BUFFERING) {
                        streamSource?.let { (playerState as? com.pixelperfect.fotty.features.player.viewmodel.PlayerState.Playback)?.let { state ->
                            // Nudge VM that we are stalling
                            // In a real implementation, we'd use a callback, but we'll use the property nudge
                        }}
                    }
                }
                override fun onPlayerError(error: PlaybackException) {
                    triggerSourceFailover(
                        reason = "Playback error: ${error.errorCodeName}",
                        switchedHint = "Playback error. Switching to another source...",
                        exhaustedHint = "Playback failed. No backup source is available."
                    )
                }
                override fun onTracksChanged(tracks: androidx.media3.common.Tracks) {
                    val videoGroup = tracks.groups.firstOrNull { it.type == androidx.media3.common.C.TRACK_TYPE_VIDEO }
                    if (videoGroup != null) {
                        val format = videoGroup.getTrackFormat(0)
                        currentRes = "${format.width}x${format.height}"
                        currentBitrate = if (format.bitrate > 0) "${format.bitrate / 1000}kbps" else "Auto"
                    }
                }
            }
            player.addListener(listener)
            onDispose {
                player.removeListener(listener)
                player.release()
            }
        }
    }

    LaunchedEffect(showOverlayControls, overlayNonce) {
        if (showOverlayControls) {
            delay(3_500)
            showOverlayControls = false
        }
    }

    // MIRROR: Invalidate extraction state and session when source changes (Fixes "Never plays again" bug)
    LaunchedEffect(streamSource?.url) {
        extractedUrl = null
        extractedHeaders = null
        hasPlaybackStarted = false
        // CLEAR SESSION: Bypasses ad-block detection and session locking
        try {
            CookieManager.getInstance().removeAllCookies(null)
            CookieManager.getInstance().flush()
        } catch (e: Exception) {
            Log.e("VideoPlayer", "Failed to clear cookies", e)
        }
    }

    LaunchedEffect(streamSource?.url, useWebFallback) {
        if (useWebFallback) {
            hasPlaybackStarted = false
            isBuffering = true
            statusHint = "Opening web fallback for ${streamSource?.provider ?: "selected source"}..."
            return@LaunchedEffect
        }
        delay(if (isP2PStreamUrl(streamSource?.url.orEmpty())) 32_000 else 16_000)
        if (!hasPlaybackStarted) {
            triggerSourceFailover(
                reason = "Native startup timeout",
                switchedHint = "Native source timed out. Trying next source...",
                exhaustedHint = "Native source timed out. No backup source available."
            )
        }
    }

    var currentPosition by remember { mutableLongStateOf(0L) }
    var duration by remember { mutableLongStateOf(0L) }
    var bufferedPosition by remember { mutableLongStateOf(0L) }

    LaunchedEffect(exoPlayer, exoPlayer?.isPlaying) {
        while (true) {
            exoPlayer?.let {
                currentPosition = it.currentPosition
                duration = it.duration
                bufferedPosition = it.bufferedPosition
            }
            delay(1000)
        }
    }

    AresGestureLayer(
        onVolumeChange = { delta ->
            val max = audioManager.getStreamMaxVolume(AudioManager.STREAM_MUSIC)
            val current = audioManager.getStreamVolume(AudioManager.STREAM_MUSIC)
            audioManager.setStreamVolume(AudioManager.STREAM_MUSIC, (current + (delta * max).toInt()).coerceIn(0, max), 0)
        },
        onBrightnessChange = { delta ->
            activity?.let { act ->
                val lp = act.window.attributes
                val current = if (lp.screenBrightness < 0) 0.5f else lp.screenBrightness
                lp.screenBrightness = (current + delta).coerceIn(0.01f, 1f)
                act.window.attributes = lp
            }
        },
        onDoubleTapSeek = { offset -> exoPlayer?.seekTo((exoPlayer.currentPosition + offset).coerceIn(0, exoPlayer.duration)) },
        modifier = Modifier.fillMaxSize()
    ) {
        Box(
            modifier = Modifier
                .fillMaxSize()
                .background(Color.Black)
                .pointerInput(Unit) {
                    detectTapGestures(onTap = { revealOverlayControls() })
                }
        ) {
        // Discovery Layer (Hidden WebView) or Web Player
        if (useWebFallback || (isUsingExtractedNative && !hasPlaybackStarted)) {
            if (extractedUrl == null && streamSource != null) {
                LiveWebFallbackPlayer(
                    source = streamSource,
                    onPageReady = {
                        statusHint = "Discovery engine active. Searching for stream..."
                        isBuffering = false
                    },
                    onMediaDetected = {
                        hasPlaybackStarted = true
                        isBuffering = false
                        statusHint = "Event Link (Web) • ${streamSource?.provider}"
                    },
                    onError = { detail ->
                        triggerSourceFailover(
                            reason = "Web fallback error: $detail",
                            switchedHint = "Web source failed. Trying next source...",
                            exhaustedHint = "Web source failed. No backup source available."
                        )
                    },
                    onNativeUrlDetected = { url, headers ->
                        if (extractedUrl == null) {
                            extractedUrl = url
                            extractedHeaders = headers
                            statusHint = "Media Node discovered. Connecting..."
                        }
                    }
                )
            }
        }

        // Native Player Layer
        if (extractedUrl != null && streamSource != null) {
            AndroidView(
                factory = { ctx ->
                    PlayerView(ctx).apply {
                        player = exoPlayer
                        useController = false
                        resizeMode = AspectRatioFrameLayout.RESIZE_MODE_FIT
                        setKeepContentOnPlayerReset(true)
                        setBackgroundColor(android.graphics.Color.BLACK)
                    }
                },
                update = { playerView ->
                    playerView.player = exoPlayer
                },
                modifier = Modifier.fillMaxSize()
                    .pointerInput(Unit) {
                        detectTapGestures(onTap = { revealOverlayControls() })
                    }
            )
        }

        // Custom Machined Controls (Play/Pause Toggle)
        if (showOverlayControls && !isLocked && hasPlaybackStarted) {
            Box(
                modifier = Modifier.fillMaxSize(),
                contentAlignment = Alignment.Center
            ) {
                // Only show big Play icon if paused, or briefly on tap
                if (exoPlayer?.isPlaying == false) {
                    IconButton(
                        onClick = { exoPlayer?.play() },
                        modifier = Modifier.size(80.dp).background(Color.Black.copy(alpha = 0.4f), CircleShape)
                    ) {
                        Icon(
                            imageVector = Icons.Default.PlayArrow,
                            contentDescription = "Play",
                            tint = Color.White,
                            modifier = Modifier.size(40.dp)
                        )
                    }
                }
            }
        }

        // Machined Progress Line (Subtle)
            if (hasPlaybackStarted) {
                val progress = remember { mutableStateOf(0f) }
                LaunchedEffect(exoPlayer?.isPlaying) {
                    while (exoPlayer?.isPlaying == true) {
                        progress.value = (exoPlayer.currentPosition.toFloat() / exoPlayer.duration.coerceAtLeast(1L))
                        delay(1000)
                    }
                }
                Box(
                    modifier = Modifier.align(Alignment.BottomCenter).fillMaxWidth().height(2.dp).background(Color.White.copy(alpha = 0.1f))
                ) {
                    Box(
                        modifier = Modifier.fillMaxWidth(progress.value).fillMaxHeight().background(Accent)
                    )
                }
            }

        // Diagnostic Overlay (Premium Machined Style)
        if (showDebugInfo) {
            Surface(
                modifier = Modifier
                    .align(Alignment.TopStart)
                    .padding(16.dp),
                color = Color.Black.copy(alpha = 0.9f),
                shape = RoundedCornerShape(0.dp),
                border = BorderStroke(1.dp, MaterialTheme.colorScheme.primary)
            ) {
                Column(modifier = Modifier.padding(12.dp)) {
                    Text(
                        text = "SYSTEM DIAGNOSTICS", 
                        color = MaterialTheme.colorScheme.primary, 
                        fontWeight = FontWeight.Black, 
                        fontSize = 10.sp, 
                        letterSpacing = 1.sp,
                        fontFamily = FontFamily.Monospace
                    )
                    Spacer(modifier = Modifier.height(8.dp))
                    
                    diagnostics?.let { diag ->
                        DiagRow("MATCH_ID", diag.matchId)
                        DiagRow("STABLE_ID", diag.stableId)
                        DiagRow("RAW_SRC", "${diag.rawSourceCount}")
                        DiagRow("PLAYABLE", "${diag.playableSourceCount}", color = Color.Green)
                        DiagRow("BACKFILL", "${diag.backfillCount}", color = MaterialTheme.colorScheme.primary)
                        Spacer(modifier = Modifier.height(4.dp))
                    }

                    DiagRow("PROVIDER", streamSource?.provider ?: "UNKNOWN", color = Color.Green)
                    DiagRow("INDEX", "$currentSourceIndex")
                    diagnostics?.lastError?.let { err ->
                        if (err.isNotBlank()) {
                            DiagRow("LAST_ERR", err, color = Color.Red)
                        }
                    }
                }
            }
        }

        // Tactical Loading State
        if (playerState is com.pixelperfect.fotty.features.player.viewmodel.PlayerState.Resolving || (!hasPlaybackStarted && !isUsingExtractedNative)) {
            PlaybackWarmupScreen(
                homeTeam = homeTeam ?: "HOME",
                awayTeam = awayTeam ?: "AWAY",
                statusHint = statusHint
            )
        }

        // Tactical Intelligence Overlay
        intelligenceState.intelligence?.let { intelligence ->
            PlayerIntelligenceOverlay(
                intelligence = intelligence,
                isVisible = intelligenceState.isVisible && !isLocked,
                category = category ?: "football"
            )
        }

        // iOS PARITY: Match Timeline Integration
        if (intelligenceState.isVisible && intelligenceState.events.isNotEmpty()) {
            MatchTimelineOverlay(
                events = intelligenceState.events,
                currentMinute = 75, // TODO: Sync from statusHint elapsed
                modifier = Modifier.align(Alignment.BottomCenter).padding(bottom = 120.dp)
            )
        }

        // TOP BAR: Match Info & Close
        // Ares Pro Player Controls
        AresPlayerControls(
            isVisible = showOverlayControls && !isLocked,
            isPlaying = exoPlayer?.isPlaying == true,
            isPipMode = isPipMode,
            title = "$homeTeam vs $awayTeam",
            subtitle = streamSource?.provider ?: "Live Stream",
            currentPosition = currentPosition,
            duration = duration,
            bufferedPosition = bufferedPosition,
            onPlayPause = { 
                scope.launch { hapticManager.vibrateLight() }
                if (exoPlayer?.isPlaying == true) exoPlayer.pause() else exoPlayer?.play() 
            },
            onSeek = { exoPlayer?.seekTo(it) },
            onToggleFullscreen = { /* automatic */ },
            onSettingsClick = { 
                scope.launch { hapticManager.vibrateLight() }
                showSourcePicker = true 
            },
            onInsightsClick = {
                scope.launch { hapticManager.vibrateImpact() }
                onToggleIntelligence()
            },
            onBack = onBack,
            statusLabel = diagnostics?.matchStatus ?: if (isUsingExtractedNative) "LIVE" else null
        )

        // Error State
        if (playerState is com.pixelperfect.fotty.features.player.viewmodel.PlayerState.Error) {
            Box(
                modifier = Modifier.fillMaxSize().background(Color.Black),
                contentAlignment = Alignment.Center
            ) {
                Column(horizontalAlignment = Alignment.CenterHorizontally, modifier = Modifier.padding(32.dp)) {
                    Icon(Icons.Default.Lock, contentDescription = "Error", tint = MaterialTheme.colorScheme.primary, modifier = Modifier.size(48.dp))
                    Spacer(modifier = Modifier.height(24.dp))
                    Text(
                        text = playerState.message.uppercase(),
                        color = Color.White,
                        textAlign = TextAlign.Center,
                        fontSize = 12.sp,
                        fontWeight = FontWeight.Black,
                        fontFamily = FontFamily.Monospace,
                        letterSpacing = 1.sp
                    )
                    Spacer(modifier = Modifier.height(32.dp))
                    Surface(
                        onClick = {
                            // In a real VM integration, this would trigger a reload
                            // For now, we provide the UI hook for the retry action
                            revealOverlayControls()
                        },
                        color = MaterialTheme.colorScheme.primary.copy(alpha = 0.1f),
                        shape = RoundedCornerShape(0.dp),
                        border = BorderStroke(1.dp, MaterialTheme.colorScheme.primary)
                    ) {
                        Text(
                            "RETRY CONNECTION", 
                            modifier = Modifier.padding(horizontal = 24.dp, vertical = 12.dp),
                            color = Color.White,
                            fontSize = 11.sp,
                            fontWeight = FontWeight.Black,
                            fontFamily = FontFamily.Monospace
                        )
                    }
                    Spacer(modifier = Modifier.height(12.dp))
                    TextButton(onClick = onBack) {
                        Text("DISMISS", color = Color.White.copy(alpha = 0.6f), fontSize = 10.sp)
                }
            }
        }
    }

    if (showSyncSettings) {
        SyncSettingsBottomSheet(
            exoPlayer = exoPlayer,
            onDismiss = { showSyncSettings = false }
        )
    }

    if (showSourcePicker) {
        SourceSelectorSheet(
            sources = sources,
            currentSourceIndex = currentSourceIndex,
            onSelectSource = { index ->
                showSourcePicker = false
                extractedUrl = null
                hasPlaybackStarted = false
                onSelectSource(index)
            },
            onDismiss = { showSourcePicker = false },
            onBrowseCatalog = {
                showSourcePicker = false
                showP2PBrowser = true
            }
        )
    }

    if (showP2PBrowser) {
        P2PChannelBrowserSheet(
            channels = globalP2PSources,
            isFetching = isFetchingGlobalP2P,
            onSelectChannel = { channel ->
                showP2PBrowser = false
                extractedUrl = null
                hasPlaybackStarted = false
                onSelectGlobalSource(channel)
            },
            onDismiss = { showP2PBrowser = false }
        )
    }
    }
}
}


@SuppressLint("SetJavaScriptEnabled")
@Composable
private fun LiveWebFallbackPlayer(
    source: StreamSource,
    onPageReady: () -> Unit,
    onMediaDetected: () -> Unit,
    onError: (String) -> Unit,
    onNativeUrlDetected: (String, Map<String, String>) -> Unit
) {
    var webViewRef by remember { mutableStateOf<WebView?>(null) }
    var currentUrl by remember { mutableStateOf(source.url) }
    var isExtracting by remember { mutableStateOf(true) }

    DisposableEffect(Unit) {
        onDispose {
            webViewRef?.apply {
                stopLoading()
                loadUrl("about:blank")
                clearHistory()
                removeAllViews()
                destroy()
            }
            webViewRef = null
        }
    }

    val blockedHostHints = remember {
        listOf(
            "doubleclick",
            "googlesyndication",
            "adservice",
            "adnxs",
            "tracker",
            "ads.",
            "bolsterate.net",
            "ljline.com"
        )
    }

    fun isKnownLiveHost(host: String): Boolean {
        if (host.isBlank()) return false
        return host == "embedsports.top"
            || host.endsWith(".embedsports.top")
            || host == "pooembed.eu"
            || host.endsWith(".pooembed.eu")
            || host.endsWith(".cdn-lab.shop")
    }

    val baseHeaders = remember(source.url, source.headers) {
        val h = source.headers.toMutableMap()
        if (h["Referer"].isNullOrBlank()) h["Referer"] = source.url
        if (h["User-Agent"].isNullOrBlank()) {
            h["User-Agent"] = "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1"
        }
        h
    }

    LaunchedEffect(source.url) {
        withContext(Dispatchers.IO) {
            try {
                val doc = Jsoup.connect(source.url)
                    .userAgent(baseHeaders["User-Agent"]!!)
                    .header("Referer", baseHeaders["Referer"]!!)
                    .timeout(10_000)
                    .followRedirects(true)
                    .get()
                
                // Sync cookies to CookieManager
                val cookieManager = CookieManager.getInstance()
                doc.connection().response().cookies().forEach { (name, value) ->
                    cookieManager.setCookie(source.url, "$name=$value")
                }
                cookieManager.flush()

                // Nuclear Extraction: Find the real player iframe
                val iframes = doc.select("iframe")
                var foundTarget = false
                for (iframe in iframes) {
                    val src = iframe.attr("src")
                    if (src.contains("vidsrc") || src.contains("embed") || src.contains("player")) {
                        val absoluteSrc = if (src.startsWith("//")) "https:$src" 
                                         else if (!src.startsWith("http")) {
                                             val base = source.url.substringBeforeLast("/")
                                             "$base/$src"
                                         } else src
                        
                        withContext(Dispatchers.Main) {
                            currentUrl = absoluteSrc
                            isExtracting = false
                        }
                        foundTarget = true
                        break
                    }
                }
                
                if (!foundTarget) {
                    withContext(Dispatchers.Main) { isExtracting = false }
                }
            } catch (e: Exception) {
                withContext(Dispatchers.Main) { isExtracting = false }
            }
        }
    }

    AndroidView(
        modifier = Modifier.fillMaxSize(),
        factory = { ctx ->
            WebView(ctx).apply {
                // MIRROR: iOS WKWebView configuration
                isVerticalScrollBarEnabled = false
                isHorizontalScrollBarEnabled = false
                scrollBarStyle = View.SCROLLBARS_OUTSIDE_OVERLAY
                overScrollMode = View.OVER_SCROLL_NEVER

                CookieManager.getInstance().setAcceptCookie(true)
                CookieManager.getInstance().setAcceptThirdPartyCookies(this, true)
                addJavascriptInterface(object {
                    @JavascriptInterface
                    fun mediaReady(url: String?) {
                        url?.let {
                            post { onNativeUrlDetected(it, emptyMap()) }
                        }
                    }
                    @JavascriptInterface
                    fun playbackStarted() {
                        post { onMediaDetected() }
                    }
                }, "FottyLiveBridge")

                setLayerType(View.LAYER_TYPE_HARDWARE, null)
                
                if (WebViewFeature.isFeatureSupported(WebViewFeature.DOCUMENT_START_SCRIPT)) {
                    WebViewCompat.addDocumentStartJavaScript(this, IOS_MIRROR_INTERCEPT_SCRIPT, setOf("*"))
                    WebViewCompat.addDocumentStartJavaScript(this, IOS_MIRROR_ENVIRONMENT_MOCK_SCRIPT, setOf("*"))
                    WebViewCompat.addDocumentStartJavaScript(this, IOS_MIRROR_SANDBOX_CLEANER_SCRIPT, setOf("*"))
                    WebViewCompat.addDocumentStartJavaScript(this, IOS_MIRROR_STYLE_INJECTION, setOf("*"))
                    WebViewCompat.addDocumentStartJavaScript(this, IOS_MIRROR_NUCLEAR_CLEANUP, setOf("*"))
                }
                
                webChromeClient = object : WebChromeClient() {
                    override fun onConsoleMessage(consoleMessage: android.webkit.ConsoleMessage?): Boolean {
                        android.util.Log.d("FottyPlayerJS", "${consoleMessage?.message()} -- From line ${consoleMessage?.lineNumber()} of ${consoleMessage?.sourceId()}")
                        return true
                    }

                    override fun onCreateWindow(
                        view: WebView?,
                        isDialog: Boolean,
                        isUserGesture: Boolean,
                        resultMsg: android.os.Message?
                    ): Boolean {
                        val transport = resultMsg?.obj as? WebView.WebViewTransport
                        if (transport != null) {
                            transport.webView = view
                            resultMsg.sendToTarget()
                            return true
                        }
                        return false
                    }
                }
                
                settings.apply {
                    javaScriptEnabled = true
                    javaScriptCanOpenWindowsAutomatically = true
                    setSupportMultipleWindows(true)
                    domStorageEnabled = true
                    allowFileAccess = true
                    allowContentAccess = true
                    allowFileAccessFromFileURLs = true
                    allowUniversalAccessFromFileURLs = true
                    mediaPlaybackRequiresUserGesture = false
                    mixedContentMode = WebSettings.MIXED_CONTENT_ALWAYS_ALLOW
                    safeBrowsingEnabled = false // HARDEN: Avoid blocks on redirects
                    userAgentString = baseHeaders["User-Agent"]
                    builtInZoomControls = false
                    displayZoomControls = false
                    useWideViewPort = true
                    loadWithOverviewMode = true
                }
                
                webViewClient = object : WebViewClient() {
                    override fun shouldOverrideUrlLoading(view: WebView?, request: WebResourceRequest?): Boolean {
                        val host = request?.url?.host?.lowercase(Locale.US).orEmpty()
                        if (blockedHostHints.any { host.contains(it) }) {
                            return true
                        }
                        return false
                    }

                    override fun onPageFinished(view: WebView?, url: String?) {
                        super.onPageFinished(view, url)
                        onPageReady()
                        // MIRROR: iOS scripts injection
                        evaluateJavascript(IOS_MIRROR_INTERCEPT_SCRIPT, null)
                        evaluateJavascript(IOS_MIRROR_ENVIRONMENT_MOCK_SCRIPT, null)
                        evaluateJavascript(IOS_MIRROR_SANDBOX_CLEANER_SCRIPT, null)
                        evaluateJavascript(IOS_MIRROR_AUTOPLAY_KICK, null)
                        evaluateJavascript(IOS_MIRROR_STYLE_INJECTION, null)
                        evaluateJavascript(IOS_MIRROR_NUCLEAR_CLEANUP, null)
                    }

                    override fun shouldInterceptRequest(view: WebView?, request: WebResourceRequest?): WebResourceResponse? {
                        val url = request?.url?.toString().orEmpty()
                        val host = request?.url?.host?.lowercase(Locale.US) ?: ""
                        
                        if (blockedHostHints.any { host.contains(it) }) {
                            return WebResourceResponse("text/plain", "UTF-8", ByteArrayInputStream("".toByteArray()))
                        }
                        
                        // Media detection logic
                        if (isLikelyLiveStreamUrl(url)) {
                            post { 
                                onMediaDetected()
                                onNativeUrlDetected(url, request?.requestHeaders ?: emptyMap())
                            }
                        }

                        // HARDEN: Force Referer and User-Agent on all requests to prevent detection
                        // We only do this for non-media requests to avoid breaking ExoPlayer later
                        if (!isLikelyLiveStreamUrl(url) && !url.contains(".m3u8") && request?.method == "GET") {
                            // This is complex to do perfectly without a proxy, but we can try to 
                            // redirect the request with custom headers if needed.
                            // For now, we rely on the initial loadUrl and the Mocking scripts.
                        }
                        
                        return super.shouldInterceptRequest(view, request)
                    }

                    override fun onReceivedError(view: WebView?, request: WebResourceRequest?, error: WebResourceError?) {
                        if (request?.isForMainFrame == true) onError(error?.description?.toString() ?: "web error")
                    }

                    override fun onReceivedSslError(
                        view: WebView?,
                        handler: SslErrorHandler?,
                        error: SslError?
                    ) {
                        val host = runCatching {
                            Uri.parse(error?.url.orEmpty()).host?.lowercase(Locale.US).orEmpty()
                        }.getOrDefault("")
                        if (isKnownLiveHost(host)) {
                            handler?.proceed()
                        } else {
                            handler?.cancel()
                            onError("ssl error")
                        }
                    }
                }
                webViewRef = this
                loadUrl(currentUrl, baseHeaders)
            }
        }
    )
    
    LaunchedEffect(currentUrl, isExtracting) {
        if (!isExtracting) {
            webViewRef?.loadUrl(currentUrl, baseHeaders)
        }
    }
}

// MIRROR: EXACT iOS intercept script from WebViewExtractor.swift:127
// MIRROR: Comprehensive Environment Mocking
private const val IOS_MIRROR_ENVIRONMENT_MOCK_SCRIPT = """
(function() {
  try {
    const platform = 'iPhone';
    const vendor = 'Apple Computer, Inc.';
    const userAgent = 'Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1';

    Object.defineProperty(navigator, 'platform', { get: () => platform });
    Object.defineProperty(navigator, 'vendor', { get: () => vendor });
    Object.defineProperty(navigator, 'userAgent', { get: () => userAgent });
    Object.defineProperty(navigator, 'maxTouchPoints', { get: () => 5 });
    Object.defineProperty(navigator, 'webdriver', { get: () => false });
    Object.defineProperty(navigator, 'languages', { get: () => ['en-US', 'en'] });
    
    // Hide WebView-specific indicators
    delete window.chrome;
    delete navigator.standalone;
    
    // Bypass iframe detection
    Object.defineProperty(window, 'top', { get: () => window });
    Object.defineProperty(window, 'parent', { get: () => window });
  } catch(e) {}
})();
"""

private const val IOS_MIRROR_INTERCEPT_SCRIPT = """
(function() {
    function sendURL(url) {
        if (!url || typeof url !== 'string') return;
        try {
            var absUrl = new URL(url, window.location.href).href;
            if (absUrl.startsWith('blob:')) return;
            if (absUrl.includes('.m3u8') || absUrl.includes('.mp4')) {
                if (window.FottyLiveBridge) window.FottyLiveBridge.mediaReady(absUrl);
            }
        } catch(e) {}
    }
    
    function scanJSON(obj, depth) {
        if (depth > 8 || !obj) return;
        if (typeof obj === 'string') {
            sendURL(obj);
        } else if (typeof obj === 'object') {
            for (var key in obj) {
                try { scanJSON(obj[key], depth + 1); } catch(e) {}
            }
        }
    }
    
    const origFetch = window.fetch;
    window.fetch = function(url, options) {
        const urlStr = typeof url === 'string' ? url : (url?.url || '');
        sendURL(urlStr);
        return origFetch.apply(this, arguments).then(function(response) {
            const clone = response.clone();
            clone.text().then(function(text) {
                try {
                    const json = JSON.parse(text);
                    scanJSON(json, 0);
                } catch(e) {
                    if (text.includes('#EXTM3U')) sendURL(urlStr);
                }
            }).catch(function(){});
            return response;
        });
    };
    
    const origOpen = XMLHttpRequest.prototype.open;
    const origSend = XMLHttpRequest.prototype.send;
    XMLHttpRequest.prototype.open = function(method, url) {
        this._fottyURL = url ? url.toString() : '';
        sendURL(this._fottyURL);
        return origOpen.apply(this, arguments);
    };
    XMLHttpRequest.prototype.send = function() {
        this.addEventListener('load', function() {
            try {
                const json = JSON.parse(this.responseText);
                scanJSON(json, 0);
            } catch(e) {}
        });
        return origSend.apply(this, arguments);
    };
    
    const origSrc = Object.getOwnPropertyDescriptor(HTMLMediaElement.prototype, 'src');
    if (origSrc && origSrc.set) {
        Object.defineProperty(HTMLMediaElement.prototype, 'src', {
            set: function(value) {
                sendURL(value);
                return origSrc.set.call(this, value);
            },
            get: origSrc.get
        });
    }
    
    var origJW = window.jwplayer;
    Object.defineProperty(window, 'jwplayer', {
        get: function() { return origJW; },
        set: function(newJW) {
            origJW = newJW;
            try {
                var origProto = newJW.prototype || {};
                var origSetup = origProto.setup;
                if (origSetup) {
                    origProto.setup = function(config) {
                        try { scanJSON(config, 0); } catch(e) {}
                        return origSetup.apply(this, arguments);
                    };
                }
            } catch(e) {}
        }
    });
    
    function dispatchTap(el) {
        if (!el) return;
        try {
            ['pointerdown', 'mousedown', 'touchstart', 'pointerup', 'mouseup', 'touchend', 'click'].forEach(function(evtName) {
                try { el.dispatchEvent(new Event(evtName, { bubbles: true, cancelable: true })); } catch(e) {}
            });
            if (typeof el.click === 'function') el.click();
        } catch (e) {}
    }

    setInterval(function() {
        const selectors = [
            '.vjs-big-play-button', '.plyr__control--overlaid', 'button[title="Play"]',
            '.play-button', '#play-button', '.jw-display-icon-display', '.jw-icon-display',
            '.play-wrapper', '.button-play', '#pl_but', '#pl_but_background', '[aria-label="Play"]',
            '.play-btn', '.player-play', '.vjs-play-control'
        ];
        selectors.forEach(function(sel) {
            try {
                document.querySelectorAll(sel).forEach(function(btn) { dispatchTap(btn); });
            } catch (e) {}
        });
        
        // MIRROR: Aggressive video play and detection
        try {
            document.querySelectorAll('video, audio').forEach(function(v) {
                if (v.paused) {
                    v.muted = true;
                    v.play().catch(function(){});
                } else if (v.currentTime > 0.1 && !v.paused) {
                    if (window.FottyLiveBridge) window.FottyLiveBridge.playbackStarted();
                }
            });
        } catch(e) {}

        try {
            const centerElem = document.elementFromPoint(window.innerWidth / 2, window.innerHeight / 2);
            dispatchTap(centerElem);
        } catch (e) {}
    }, 900);
})();
"""

// MIRROR: EXACT iOS autoplay kick script from WebViewExtractor.swift:333
private const val IOS_MIRROR_AUTOPLAY_KICK = """
(function() {
    var kickCount = 0;
    var kicker = setInterval(function() {
        kickCount++;
        if (kickCount > 15) { clearInterval(kicker); return; }
        
        var selectors = [
            '#pl_but', '#pl_but_background', '.vjs-big-play-button', 
            '.plyr__control--overlaid', '.jw-display-icon-display', 
            '.jw-icon-display', '[aria-label="Play"]'
        ];
        selectors.forEach(function(sel) {
            try {
                document.querySelectorAll(sel).forEach(function(node) {
                    if (node && (node.offsetWidth > 0 || node.offsetHeight > 0)) {
                        node.click();
                        node.dispatchEvent(new MouseEvent('mousedown', {bubbles:true}));
                        node.dispatchEvent(new MouseEvent('mouseup', {bubbles:true}));
                        node.dispatchEvent(new MouseEvent('click', {bubbles:true}));
                    }
                });
            } catch (e) {}
        });
    }, 500);
})();
"""

private const val IOS_MIRROR_STYLE_INJECTION = """
(function() {
    var style = document.createElement('style');
    style.innerHTML = `
        .ad, .ads, .advertisement, [id*="ad-"], [class*="ad-"], 
        #overlayer, .overlay, .pop-up, .popup, 
        .modal, .jw-hidden, .jw-display-icon-container,
        #cl-but, #pl_but_background { display: none !important; pointer-events: none !important; }
        [class*="sandbox"], [id*="sandbox"], [class*="error"], [id*="error"] { display: none !important; pointer-events: none !important; opacity: 0 !important; visibility: hidden !important; }
        * { -webkit-touch-callout: none !important; }
    `;
    document.head.appendChild(style);
})();
"""

private const val IOS_MIRROR_NUCLEAR_CLEANUP = """
(function() {
    function purge() {
        const adSelectors = [
            'div[id^="ad-"]', 'div[class^="ad-"]', '.ad-box', '.ads-box',
            '#pop-under', '#pop-up', '.popup-wrapper', '.modal-backdrop',
            'iframe[src*="doubleclick"]', 'iframe[src*="adservice"]',
            'div[style*="z-index: 2147483647"]', 'div[style*="z-index: 999999"]',
            'div[style*="position: fixed"][style*="z-index"]'
        ];
        adSelectors.forEach(sel => {
            document.querySelectorAll(sel).forEach(el => {
                try { el.remove(); } catch(e) {}
            });
        });
    }
    purge();
    setInterval(purge, 2000);
})();
"""

private const val IOS_MIRROR_SANDBOX_CLEANER_SCRIPT = """
(function() {
  try {
    Object.defineProperty(window, 'top', { get: function() { return window; } });
    Object.defineProperty(window, 'parent', { get: function() { return window; } });
    window.frameElement = null;
  } catch(e) {}

  function strip(node) {
    if (node && node.tagName === 'IFRAME') {
      if (node.hasAttribute('sandbox')) node.removeAttribute('sandbox');
      node.setAttribute('allow', 'autoplay; fullscreen; picture-in-picture; encrypted-media; web-share');
    }
  }
  
  try { document.querySelectorAll('iframe').forEach(strip); } catch(e) {}
  
  try {
    var observer = new MutationObserver(function(mutations) {
      mutations.forEach(function(mutation) {
        mutation.addedNodes.forEach(function(node) {
          if (node.tagName === 'IFRAME') strip(node);
          else if (node.querySelectorAll) node.querySelectorAll('iframe').forEach(strip);
        });
      });
    });
    observer.observe(document.documentElement, { childList: true, subtree: true });
  } catch(e) {}
})();
"""

private fun Context.findActivity(): Activity? {
    var context = this
    while (context is ContextWrapper) {
        if (context is Activity) return context
        context = context.baseContext
    }
    return null
}

@Composable
private fun EnableImmersiveLivePlayback() {
    val context = LocalContext.current
    val window = (context as? Activity)?.window ?: return
    DisposableEffect(Unit) {
        val controller = WindowCompat.getInsetsController(window, window.decorView)
        controller.systemBarsBehavior = WindowInsetsControllerCompat.BEHAVIOR_SHOW_TRANSIENT_BARS_BY_SWIPE
        controller.hide(WindowInsetsCompat.Type.systemBars())
        
        // Keep screen on while playing
        window.addFlags(android.view.WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        
        onDispose { 
            controller.show(WindowInsetsCompat.Type.systemBars())
            // Reset brightness to system default
            val lp = window.attributes
            lp.screenBrightness = -1f
            window.attributes = lp
            // Remove keep screen on flag
            window.clearFlags(android.view.WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        }
    }
}
@Composable
private fun ScoreOverlay(
    homeTeam: String,
    awayTeam: String,
    homeScore: Int?,
    awayScore: Int?,
    statusLabel: String?,
    category: String = "football"
) {
    Surface(
        color = MaterialTheme.colorScheme.surfaceVariant,
        shape = MaterialTheme.shapes.medium,
        tonalElevation = 8.dp,
        modifier = Modifier.padding(top = 16.dp)
    ) {
        Row(
            modifier = Modifier
                .padding(horizontal = 16.dp, vertical = 10.dp)
                .wrapContentWidth(),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.Center
        ) {
            // LIVE Badge
            if (!statusLabel.isNullOrBlank()) {
                val isLive = statusLabel.contains("LIVE", ignoreCase = true)
                Surface(
                    color = if (isLive) Color(0xFFF44336) else Color.Gray.copy(alpha = 0.2f),
                    shape = RoundedCornerShape(4.dp)
                ) {
                    Text(
                        text = statusLabel.uppercase(),
                        modifier = Modifier.padding(horizontal = 6.dp, vertical = 2.dp),
                        color = Color.White,
                        style = MaterialTheme.typography.labelSmall.copy(fontWeight = FontWeight.Black, fontSize = 9.sp)
                    )
                }
            }

            Spacer(modifier = Modifier.width(16.dp))

            // Away
            Text(
                text = awayTeam.uppercase(),
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                style = MaterialTheme.typography.titleSmall.copy(fontWeight = FontWeight.Bold)
            )
        }
    }
}
