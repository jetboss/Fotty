package com.pixelperfect.fotty.core.network.api.news

import retrofit2.http.GET
import retrofit2.http.Query

interface NewsInterface {
    @GET("top-headlines")
    suspend fun getSportsNews(
        @Query("category") category: String = "sports",
        @Query("language") language: String = "en",
        @Query("apiKey") apiKey: String,
        @Query("q") query: String? = null
    ): NewsResponse
}

data class NewsResponse(
    val status: String,
    val totalResults: Int,
    val articles: List<Article>
)

data class Article(
    val title: String,
    val description: String?,
    val url: String,
    val urlToImage: String?,
    val publishedAt: String,
    val source: Source
)

data class Source(
    val name: String
)
