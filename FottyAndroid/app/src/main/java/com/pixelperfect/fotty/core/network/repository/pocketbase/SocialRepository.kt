package com.pixelperfect.fotty.core.network.repository.pocketbase

import com.pixelperfect.fotty.core.network.api.pocketbase.PocketBaseInterface
import com.pixelperfect.fotty.core.network.models.pocketbase.ArenaMessage
import com.pixelperfect.fotty.core.network.models.pocketbase.ArenaMessageRequest
import com.pixelperfect.fotty.core.network.models.pocketbase.PBProfileRecord
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.RequestBody.Companion.toRequestBody
import javax.inject.Inject
import javax.inject.Singleton

@Singleton
class SocialRepository @Inject constructor(
    private val pbInterface: PocketBaseInterface,
    private val json: Json
) {
    suspend fun fetchArenaMessages(matchID: String, token: String): List<ArenaMessage> {
        val response = pbInterface.getArenaMessages(
            token = "Bearer $token",
            page = 1,
            perPage = 100,
            filter = "matchID = '$matchID'",
            sort = "-created"
        )
        return response.items
    }

    suspend fun deleteArenaMessage(messageID: String, token: String) {
        pbInterface.deleteRecord(
            collection = "arena_messages",
            id = messageID,
            token = "Bearer $token"
        )
    }

    suspend fun fetchUserProfile(userID: String, token: String): PBProfileRecord {
        return pbInterface.getRecord(
            collection = "users",
            id = userID,
            token = "Bearer $token"
        )
    }

    suspend fun updateUserProfile(userID: String, displayName: String, avatarSymbol: String?, token: String): PBProfileRecord {
        val update = mapOf(
            "displayName" to displayName,
            "avatarSymbol" to avatarSymbol
        )
        val bodyString = json.encodeToString(update)
        val body = bodyString.toRequestBody("application/json".toMediaType())
        return pbInterface.updateRecord(
            collection = "users",
            id = userID,
            token = "Bearer $token",
            body = body
        )
    }

    suspend fun sendArenaMessage(request: ArenaMessageRequest, token: String) {
        val bodyString = json.encodeToString(request)
        val body = bodyString.toRequestBody("application/json".toMediaType())
        pbInterface.createRecord(
            collection = "arena_messages",
            token = "Bearer $token",
            body = body
        )
    }

    suspend fun reportMessage(messageID: String, reporterID: String, reason: String, token: String) {
        val report = mapOf(
            "messageID" to messageID,
            "reporterID" to reporterID,
            "reason" to reason,
            "status" to "pending"
        )
        val bodyString = json.encodeToString(report)
        val body = bodyString.toRequestBody("application/json".toMediaType())
        pbInterface.createRecord(
            collection = "reports",
            token = "Bearer $token",
            body = body
        )
    }

    suspend fun blockUser(userID: String, targetUserID: String, token: String) {
        // Fetch current user profile, update blockedUsers list
        // Simplified for now: just log the block request to a collection
        val block = mapOf(
            "userID" to userID,
            "blockedUserID" to targetUserID
        )
        val bodyString = json.encodeToString(block)
        val body = bodyString.toRequestBody("application/json".toMediaType())
        pbInterface.createRecord(
            collection = "user_blocks",
            token = "Bearer $token",
            body = body
        )
    }
}
