package com.pixelperfect.fotty.core.network.models.music

import kotlinx.serialization.Serializable

@Serializable
data class MusicTrack(
    val id: Int,
    val title: String,
    val artist: Artist? = null,
    val album: Album? = null,
    val previewUrl: String? = null
)

@Serializable
data class Artist(
    val id: Int,
    val name: String,
    val picture: String? = null
)

@Serializable
data class Album(
    val id: Int,
    val title: String,
    val cover: String? = null
) {
    val coverURL: String? get() = cover
}
