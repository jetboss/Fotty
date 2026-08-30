package com.pixelperfect.fotty.core.network.models.streaming

interface StreamingProvider {
    val name: String
    val priority: Int
    
    suspend fun findStreams(event: SportEvent): List<StreamSource>
}
