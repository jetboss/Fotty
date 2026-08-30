package com.pixelperfect.fotty.core.ui.components

import android.view.ViewGroup
import android.webkit.WebChromeClient
import android.webkit.WebSettings
import android.webkit.WebView
import android.webkit.WebViewClient
import androidx.annotation.OptIn
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Fullscreen
import androidx.compose.material.icons.filled.FullscreenExit
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.viewinterop.AndroidView
import androidx.media3.common.MediaItem
import androidx.media3.common.util.UnstableApi
import androidx.media3.datasource.DefaultHttpDataSource
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.exoplayer.source.DefaultMediaSourceFactory
import androidx.media3.ui.PlayerView
import com.pixelperfect.fotty.core.theme.*

import com.pixelperfect.fotty.core.network.models.streaming.ResolvedStream
import com.pixelperfect.fotty.core.network.models.streaming.StreamType

@OptIn(UnstableApi::class)
@Composable
fun FottyPlayer(
    resolvedStream: ResolvedStream,
    isFullScreen: Boolean,
    onFullScreenToggle: () -> Unit,
    modifier: Modifier = Modifier
) {
    val context = LocalContext.current
    val url = resolvedStream.playbackUrl
    val headers = resolvedStream.headers
    
    val isHls = remember(url, resolvedStream.streamType) {
        val lower = url.lowercase()
        val match = resolvedStream.streamType == StreamType.P2P || 
                    resolvedStream.streamType == StreamType.HLS ||
                    lower.contains(".m3u8") ||
                    lower.contains(".mpd") ||
                    lower.contains("/proxy/acestream") ||
                    lower.contains("/ace/getstream")
        match
    }

    // Shared Player Instance
    val exoPlayer = if (isHls) {
        remember(url) {
            val dataSourceFactory = DefaultHttpDataSource.Factory()
                .setAllowCrossProtocolRedirects(true)
                .setConnectTimeoutMs(15_000)
                .setReadTimeoutMs(20_000)

            val userAgent = headers["User-Agent"] ?: "Mozilla/5.0 (Linux; Android 14; SM-S928B) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/123.0.0.0 Mobile Safari/537.36"
            dataSourceFactory.setUserAgent(userAgent)
            
            if (headers.isNotEmpty()) {
                dataSourceFactory.setDefaultRequestProperties(HashMap(headers))
            }

            val mediaSourceFactory = DefaultMediaSourceFactory(context)
                .setDataSourceFactory(dataSourceFactory)

            ExoPlayer.Builder(context)
                .setMediaSourceFactory(mediaSourceFactory)
                .build().apply {
                    val mediaItem = MediaItem.Builder()
                        .setUri(url)
                        .setMimeType(
                            if (url.contains(".m3u8")) "application/x-mpegURL"
                            else if (url.contains(".mpd")) "application/dash+xml"
                            else "video/mp2t"
                        )
                        .build()
                    setMediaItem(mediaItem)
                    prepare()
                    playWhenReady = true
                }
        }
    } else null

    if (isHls) {
        DisposableEffect(url) {
            onDispose { exoPlayer?.release() }
        }
    }

    @Composable
    fun PlayerContent(isFull: Boolean) {
        Box(modifier = Modifier.fillMaxSize()) {
            if (isHls && exoPlayer != null) {
                AndroidView(
                    factory = {
                        PlayerView(it).apply {
                            player = exoPlayer
                            useController = true
                            setBackgroundColor(android.graphics.Color.BLACK)
                        }
                    },
                    modifier = Modifier.fillMaxSize()
                )
            } else {
                AndroidView(
                    factory = { context ->
                        WebView(context).apply {
                            setBackgroundColor(android.graphics.Color.BLACK)
                            settings.apply {
                                javaScriptEnabled = true
                                domStorageEnabled = true
                                databaseEnabled = true
                                mediaPlaybackRequiresUserGesture = false
                                mixedContentMode = WebSettings.MIXED_CONTENT_ALWAYS_ALLOW
                                javaScriptCanOpenWindowsAutomatically = false
                                setSupportMultipleWindows(false)
                                allowFileAccess = true
                                allowContentAccess = true
                                loadWithOverviewMode = true
                                useWideViewPort = true
                                userAgentString = "Mozilla/5.0 (Linux; Android 14; SM-S928B) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/123.0.0.0 Mobile Safari/537.36"
                            }
                            
                            webChromeClient = object : WebChromeClient() {
                                override fun onCreateWindow(view: WebView?, isDialog: Boolean, isUserGesture: Boolean, resultMsg: android.os.Message?): Boolean {
                                    return false // Block all popups
                                }
                            }
                            
                            webViewClient = object : WebViewClient() {
                                private val adBlacklist = listOf(
                                    "popads", "popcash", "onclickads", "adsterra", "bet365", "1xbet",
                                    "doubleclick", "googlesyndication", "adnxs", "ads.", "tracker.",
                                    "bolsterate.net", "ljline.com", "ad-score.com", "cloudfront.net",
                                    "analytics", "pemsrv", "adservice", "fast-ad", "adsystem",
                                    "onclick", "wigetmedia", "mellowads", "a-ads", "coinad",
                                    "vidoza", "streamtape", "doodstream", "vidhide"
                                )

                                private fun isAd(targetUrl: String): Boolean {
                                    val low = targetUrl.lowercase()
                                    return adBlacklist.any { low.contains(it) }
                                }

                                override fun shouldInterceptRequest(view: WebView?, request: android.webkit.WebResourceRequest?): android.webkit.WebResourceResponse? {
                                    val target = request?.url?.toString().orEmpty()
                                    if (isAd(target)) {
                                        return android.webkit.WebResourceResponse("text/plain", "utf-8", java.io.ByteArrayInputStream(ByteArray(0)))
                                    }
                                    return super.shouldInterceptRequest(view, request)
                                }

                                override fun shouldOverrideUrlLoading(view: WebView?, request: android.webkit.WebResourceRequest?): Boolean {
                                    val target = request?.url?.toString().orEmpty()
                                    if (isAd(target)) return true
                                    
                                    val originalHost = android.net.Uri.parse(url).host
                                    val targetHost = request?.url?.host
                                    if (targetHost != null && originalHost != null && targetHost != originalHost) {
                                        return true 
                                    }
                                    return false 
                                }

                                override fun onPageFinished(view: WebView?, url: String?) {
                                    super.onPageFinished(view, url)
                                    // High-velocity play nudge
                                    view?.evaluateJavascript("""
                                        (function() {
                                            setInterval(function() {
                                                var selectors = ['.vjs-big-play-button', '.plyr__control--overlaid', '.play-button', 'button[title=\"Play\"]'];
                                                selectors.forEach(function(sel) {
                                                    document.querySelectorAll(sel).forEach(function(node) { try { node.click(); } catch(e) {} });
                                                });
                                            }, 500);
                                        })();
                                    """.trimIndent(), null)
                                }
                            }
                            
                            loadUrl(url, headers)
                        }
                    },
                    modifier = Modifier.fillMaxSize()
                )
            }

            IconButton(
                onClick = onFullScreenToggle,
                modifier = Modifier
                    .align(Alignment.BottomEnd)
                    .padding(8.dp)
                    .background(Color.Black.copy(alpha = 0.5f), CircleShape)
            ) {
                Icon(
                    imageVector = if (isFull) Icons.Default.FullscreenExit else Icons.Default.Fullscreen,
                    contentDescription = "Toggle Fullscreen",
                    tint = Color.White
                )
            }
        }
    }

    if (isFullScreen) {
        androidx.compose.ui.window.Dialog(
            onDismissRequest = onFullScreenToggle,
            properties = androidx.compose.ui.window.DialogProperties(
                usePlatformDefaultWidth = false,
                dismissOnBackPress = true
            )
        ) {
            Surface(
                modifier = Modifier.fillMaxSize(),
                color = Color.Black
            ) {
                PlayerContent(isFull = true)
            }
        }
    }

    Box(
        modifier = modifier.background(Color.Black),
        contentAlignment = Alignment.Center
    ) {
        if (!isFullScreen) {
            PlayerContent(isFull = false)
        } else {
            // Placeholder while in fullscreen
            Text("PLAYING IN FULLSCREEN", style = MaterialTheme.typography.labelSmall, color = Color.Gray)
        }
    }
}

@Composable
fun PlayerPlaceholder(
    message: String = "INITIALIZING STREAM...",
    modifier: Modifier = Modifier
) {
    Box(
        modifier = modifier
            .fillMaxSize()
            .background(Color.Black)
            .shimmerEffect(),
        contentAlignment = Alignment.Center
    ) {
        Column(horizontalAlignment = Alignment.CenterHorizontally) {
            CircularProgressIndicator(
                strokeWidth = 2.dp,
                modifier = Modifier.size(32.dp),
                color = MaterialTheme.colorScheme.primary
            )
            Spacer(modifier = Modifier.height(16.dp))
            Text(
                text = message.uppercase(),
                style = MaterialTheme.typography.labelMedium.copy(
                    fontWeight = FontWeight.Black,
                    letterSpacing = 1.5.sp,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
            )
        }
    }
}
