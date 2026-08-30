package com.pixelperfect.fotty.core.networking

import android.content.Context
import com.pixelperfect.fotty.core.network.models.streaming.StreamSource

class StreamNetworkExtractor(private val context: Context) {

    suspend fun extractSources(
        from: String,
        referer: String,
        providerName: String,
        timeout: Long = 20
    ): List<StreamSource> {
        return HeadlessWebExtraction.extract(
            context = context,
            embedUrl = from,
            referer = referer,
            providerName = providerName,
            timeoutSeconds = timeout,
            // Live resolvers should not early-exit on ad MP4s.
            resolveOnMp4 = false,
            logTag = "StreamNetworkExtractor"
        )
    }
}
