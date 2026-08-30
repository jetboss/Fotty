package com.pixelperfect.fotty.core.networking

import android.content.Context
import com.pixelperfect.fotty.core.network.models.streaming.StreamSource

class WebViewExtractor(private val context: Context) {

    suspend fun extractSources(
        from: String,
        referer: String,
        providerName: String,
        timeout: Long = 15
    ): List<StreamSource> {
        return HeadlessWebExtraction.extract(
            context = context,
            embedUrl = from,
            referer = referer,
            providerName = providerName,
            timeoutSeconds = timeout,
            resolveOnMp4 = false,
            logTag = "WebViewExtractor"
        )
    }
}
