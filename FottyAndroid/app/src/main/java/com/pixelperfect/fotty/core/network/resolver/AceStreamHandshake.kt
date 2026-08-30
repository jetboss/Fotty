package com.pixelperfect.fotty.core.network.resolver

import android.util.Log
import kotlinx.coroutines.delay
import kotlinx.coroutines.withContext
import kotlinx.coroutines.Dispatchers
import okhttp3.OkHttpClient
import okhttp3.Request
import org.json.JSONObject
import java.util.Date
import javax.inject.Inject
import javax.inject.Singleton

@Singleton
class AceStreamHandshake @Inject constructor(
    private val httpClient: OkHttpClient
) {
    data class P2PUpdate(
        val activePeers: Int,
        val status: String,
        val progress: Int
    )

    /**
     * Replicates the iOS 'performPeerAwareHandshake' logic.
     * Polls the AceStream engine for status and resolves the playable stream URL.
     */
    suspend fun performHandshake(
        cid: String,
        serverIP: String,
        onUpdate: (P2PUpdate) -> Unit
    ): String = withContext(Dispatchers.IO) {
        val API_PASSWORD = com.pixelperfect.fotty.core.Config.p2pApiPassword
        val manifestUrl = "https://p2p.pixel-invoice.com/proxy/acestream/manifest.m3u8?infohash=$cid&api_password=$API_PASSWORD"
        val statusUrl = "https://p2p.pixel-invoice.com/proxy/acestream/status?infohash=$cid&api_password=$API_PASSWORD"
        val startTime = System.currentTimeMillis()
        val timeout = 60_000L // Increased for high-fidelity discovery

        Log.d("P2PHandshake", "Triggering Pre-Flight manifest for $cid...")
        try {
            val preflightRequest = Request.Builder().url(manifestUrl).build()
            httpClient.newCall(preflightRequest).execute().use { _ -> } // Wake up proxy
        } catch (e: Exception) {
            Log.w("P2PHandshake", "Pre-flight wake failed: ${e.message}")
        }

        while (System.currentTimeMillis() - startTime < timeout) {
            try {
                val request = Request.Builder()
                    .url(statusUrl)
                    .header("Authorization", "Bearer $API_PASSWORD")
                    .build()
                    
                httpClient.newCall(request).execute().use { response ->
                    if (response.isSuccessful) {
                        val body = response.body?.string() ?: ""
                        val json = JSONObject(body)
                        
                        val activePeers = json.optInt("active_peers", 0)
                        val status = json.optString("status", "idle")
                        val progress = json.optInt("progress", 0)

                        Log.d("P2PHandshake", "Status Update: $status ($progress%) Peers: $activePeers")
                        onUpdate(P2PUpdate(activePeers, status, progress))

                        // Success conditions
                        if (status == "ok" || status == "dl" || (status == "prebuf" && progress > 5)) {
                            Log.d("P2PHandshake", "Handshake Success! Returning manifest.")
                            return@withContext manifestUrl
                        }
                    } else if (response.code == 404 || response.code == 524 || response.code == 504) {
                        onUpdate(P2PUpdate(0, "warming swarm", 0))
                    }
                }
            } catch (e: Exception) {
                Log.e("P2PHandshake", "Status poll failed: ${e.message}")
            }
            
            delay(1500)
        }

        throw Exception("P2P Handshake Timeout: Swarm not healthy within ${timeout/1000}s")
    }
}
