package com.pixelperfect.fotty.core.network.resolver

import android.content.Context
import android.net.Uri
import android.util.Log
import kotlinx.coroutines.*
import okhttp3.OkHttpClient
import okhttp3.Request
import java.io.*
import java.net.ServerSocket
import java.net.Socket
import java.util.concurrent.Executors
import javax.inject.Inject
import javax.inject.Singleton

/**
 * A local reverse proxy for Android (Mirroring iOS LocalStreamProxy.swift).
 * Handles manifest rewriting, header injection, and P2P segment retries.
 */
@Singleton
class LocalStreamProxy @Inject constructor(
    private val httpClient: OkHttpClient
) {
    private var serverSocket: ServerSocket? = null
    private var proxyPort: Int = 0
    private var isRunning = false
    private val proxyScope = CoroutineScope(Dispatchers.IO + SupervisorJob())
    private val executor = Executors.newCachedThreadPool()

    fun start(): Int {
        if (isRunning) return proxyPort
        
        try {
            serverSocket = ServerSocket(0) // Bind to random available port
            proxyPort = serverSocket?.localPort ?: 0
            isRunning = true
            
            proxyScope.launch {
                while (isRunning) {
                    try {
                        val clientSocket = serverSocket?.accept() ?: break
                        executor.execute { handleClient(clientSocket) }
                    } catch (e: Exception) {
                        if (isRunning) Log.e(TAG, "Accept error", e)
                    }
                }
            }
            
            Log.d(TAG, "Local Proxy started on port: $proxyPort")
            return proxyPort
        } catch (e: Exception) {
            Log.e(TAG, "Failed to start proxy", e)
            return 0
        }
    }

    fun stop() {
        isRunning = false
        try {
            serverSocket?.close()
        } catch (e: Exception) {
            Log.e(TAG, "Stop error", e)
        }
        serverSocket = null
    }

    fun getProxiedUrl(originalUrl: String): String {
        if (proxyPort == 0) return originalUrl
        return "http://127.0.0.1:$proxyPort/proxy?url=${Uri.encode(originalUrl)}"
    }

    private fun handleClient(socket: Socket) {
        try {
            val reader = BufferedReader(InputStreamReader(socket.getInputStream()))
            val firstLine = reader.readLine() ?: return
            
            val parts = firstLine.split(" ")
            if (parts.size < 2) return
            
            val path = parts[1]
            if (!path.startsWith("/proxy?url=")) {
                sendError(socket, 400, "Bad Request")
                return
            }
            
            val remoteUrl = Uri.decode(path.substringAfter("/proxy?url="))
            Log.d(TAG, "Proxying request for: $remoteUrl")
            
            // Read headers from client
            val clientHeaders = mutableMapOf<String, String>()
            var line: String?
            while (reader.readLine().also { line = it } != null && line!!.isNotBlank()) {
                val headerParts = line!!.split(": ", limit = 2)
                if (headerParts.size == 2) {
                    clientHeaders[headerParts[0]] = headerParts[1]
                }
            }
            
            Log.d(TAG, "Client Headers: ${clientHeaders.keys}")
            forwardRequest(socket, remoteUrl, clientHeaders)
            
        } catch (e: Exception) {
            Log.e(TAG, "Handler error", e)
        } finally {
            try { socket.close() } catch (_: Exception) {}
        }
    }

    private fun forwardRequest(socket: Socket, url: String, clientHeaders: Map<String, String>) {
        val isP2P = url.contains("p2p.pixel-invoice.com") || 
                    url.contains("/proxy/acestream") || 
                    url.contains(":6878")
        // STABILITY V1.6: baseline 5 retries for all streams, cap P2P at 15
        val maxRetries = if (isP2P) 15 else 5
        var attempt = 0
        
        while (attempt <= maxRetries) {
            try {
                val requestBuilder = Request.Builder().url(url)
                
                // Forward all headers from client
                clientHeaders.forEach { (name, value) ->
                    if (!name.equals("Host", true) && !name.equals("Connection", true)) {
                        requestBuilder.header(name, value)
                    }
                }
                
                // Default fallback for critical headers if missing
                if (!clientHeaders.containsKey("User-Agent")) {
                    requestBuilder.header("User-Agent", "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15")
                }
                if (!clientHeaders.containsKey("Referer") && !url.contains("127.0.0.1")) {
                    requestBuilder.header("Referer", url.substringBeforeLast("/") + "/")
                }
                
                val request = requestBuilder.build()
                Log.d(TAG, "Forwarding to upstream: ${request.url} | Referer: ${request.header("Referer")}")
                
                httpClient.newCall(request).execute().use { response ->
                    Log.d(TAG, "Upstream Response: ${response.code} ${response.message} for ${request.url}")
                    if (isP2P && (response.code == 503 || response.code == 504) && attempt < maxRetries) {
                        attempt++
                        Thread.sleep(1000)
                        return@use
                    }
                    
                    val out = socket.getOutputStream()
                    val writer = BufferedWriter(OutputStreamWriter(out))
                    
                    val isManifest = url.contains(".m3u8", true) || 
                                     response.header("Content-Type")?.contains("mpegurl", true) == true

                    if (isManifest) {
                        // Manifests MUST be read fully and rewritten
                        val content = response.body?.bytes() ?: byteArrayOf()
                        val manifest = String(content)
                        val rewritten = rewriteManifest(manifest, url)
                        val finalContent = rewritten.toByteArray()
                        
                        writer.write("HTTP/1.1 ${response.code} ${response.message}\r\n")
                        response.headers.forEach { (name, value) ->
                            if (!name.equals("Content-Length", true) && !name.equals("Transfer-Encoding", true)) {
                                writer.write("$name: $value\r\n")
                            }
                        }
                        writer.write("Content-Length: ${finalContent.size}\r\n")
                        writer.write("Connection: close\r\n")
                        writer.write("\r\n")
                        writer.flush()
                        out.write(finalContent)
                        out.flush()
                    } else {
                        // Video segments or raw streams MUST be streamed directly (iOS Parity)
                        writer.write("HTTP/1.1 ${response.code} ${response.message}\r\n")
                        var contentTypeSet = false
                        response.headers.forEach { (name, value) ->
                            if (!name.equals("Content-Length", true) && !name.equals("Transfer-Encoding", true)) {
                                if (name.equals("Content-Type", true) && isP2P) {
                                    writer.write("$name: video/mp2t\r\n") // Force TS for P2P
                                    contentTypeSet = true
                                } else {
                                    writer.write("$name: $value\r\n")
                                }
                            }
                        }
                        if (!contentTypeSet && isP2P) {
                            writer.write("Content-Type: video/mp2t\r\n")
                        }
                        writer.write("Transfer-Encoding: chunked\r\n") // Enable streaming
                        writer.write("Connection: keep-alive\r\n")
                        writer.write("\r\n")
                        writer.flush()

                        response.body?.byteStream()?.use { input ->
                            val buffer = ByteArray(64 * 1024) // 64KB Buffer like iOS
                            var bytesRead: Int
                            while (input.read(buffer).also { bytesRead = it } != -1) {
                                // Chunked encoding: HEX length \r\n Data \r\n
                                out.write(Integer.toHexString(bytesRead).toByteArray())
                                out.write("\r\n".toByteArray())
                                out.write(buffer, 0, bytesRead)
                                out.write("\r\n".toByteArray())
                                out.flush()
                            }
                            // End of chunked stream: 0 \r\n \r\n
                            out.write("0\r\n\r\n".toByteArray())
                            out.flush()
                        }
                    }
                    return // Success
                }
            } catch (e: Exception) {
                if (attempt < maxRetries) {
                    attempt++
                    Thread.sleep(1000)
                } else {
                    Log.e(TAG, "Forward failed for $url", e)
                    sendError(socket, 500, "Internal Server Error")
                    return
                }
            }
        }
    }

    private fun rewriteManifest(manifest: String, baseUrl: String): String {
        val base = baseUrl.substringBeforeLast("/") + "/"
        return manifest.lines().joinToString("\n") { line ->
            val trimmed = line.trim()
            if (trimmed.isEmpty() || trimmed.startsWith("#")) {
                // Check for URI tags like #EXT-X-KEY:METHOD=AES-128,URI="key.php"
                if (trimmed.contains("URI=\"")) {
                    rewriteLineWithUri(trimmed, base)
                } else {
                    line
                }
            } else {
                val absoluteUrl = if (trimmed.startsWith("http")) trimmed else base + trimmed
                getProxiedUrl(absoluteUrl)
            }
        }
    }

    private fun rewriteLineWithUri(line: String, base: String): String {
        val regex = Regex("URI=\"([^\"]+)\"")
        return regex.replace(line) { match ->
            val originalUri = match.groupValues[1]
            val absoluteUrl = if (originalUri.startsWith("http")) originalUri else base + originalUri
            "URI=\"${getProxiedUrl(absoluteUrl)}\""
        }
    }

    private fun sendError(socket: Socket, code: Int, message: String) {
        try {
            val writer = BufferedWriter(OutputStreamWriter(socket.getOutputStream()))
            writer.write("HTTP/1.1 $code $message\r\n")
            writer.write("Content-Type: text/plain\r\n")
            writer.write("Connection: close\r\n")
            writer.write("\r\n")
            writer.write(message)
            writer.flush()
        } catch (_: Exception) {}
    }

    companion object {
        private const val TAG = "LocalStreamProxy"
    }
}
