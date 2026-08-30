package com.pixelperfect.fotty.core.network.models.pocketbase

import kotlinx.serialization.Serializable

@Serializable
data class PBUserRecord(
    val id: String,
    val email: String,
    val name: String? = null
)

@Serializable
data class PBAuthResponse(
    val token: String,
    val record: PBUserRecord
)

@Serializable
data class PBPaginatedResponse<T>(
    val page: Int,
    val perPage: Int,
    val totalItems: Int,
    val totalPages: Int,
    val items: List<T>
)

@Serializable
data class PBProfileRecord(
    val id: String,
    val user: String? = null,
    val displayName: String,
    val username: String? = null,
    val bio: String? = null,
    val avatarSymbol: String? = null,
    val role: String? = "fan",
    val badge: String? = null,
    val isSignedIn: Boolean? = null,
    val localProfileId: String? = null,
    val lastUpdatedAt: String? = null,
    val created: String? = null,
    val updated: String? = null
)

@Serializable
data class PocketBaseSession(
    val token: String,
    val userID: String,
    val email: String
)
