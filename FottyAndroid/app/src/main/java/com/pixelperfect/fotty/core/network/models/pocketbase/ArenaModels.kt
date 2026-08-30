package com.pixelperfect.fotty.core.network.models.pocketbase

import kotlinx.serialization.Serializable

@Serializable
data class ArenaMessage(
    val id: String,
    val matchID: String,
    val senderID: String,
    val senderDisplayName: String,
    val senderUsername: String? = null,
    val senderAvatarSymbol: String? = null,
    val senderRole: String? = "fan", // "fan", "pro", "admin"
    val senderBadge: String? = null,
    val content: String,
    val type: String, // "text", "reaction"
    val created: String,
    val updated: String
)

@Serializable
data class ArenaMessageRequest(
    val matchID: String,
    val senderID: String,
    val senderDisplayName: String,
    val senderUsername: String? = null,
    val senderAvatarSymbol: String? = null,
    val senderRole: String? = "fan",
    val senderBadge: String? = null,
    val content: String,
    val type: String = "text"
)

