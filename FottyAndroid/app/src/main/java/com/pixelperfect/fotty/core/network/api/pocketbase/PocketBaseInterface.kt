package com.pixelperfect.fotty.core.network.api.pocketbase

import com.pixelperfect.fotty.core.network.models.pocketbase.*
import okhttp3.RequestBody
import retrofit2.http.*

interface PocketBaseInterface {
    @POST("api/collections/users/auth-with-password")
    suspend fun authWithPassword(
        @Body body: RequestBody
    ): PBAuthResponse

    @POST("api/collections/users/records")
    suspend fun createUser(
        @Body body: RequestBody
    ): PBUserRecord

    @GET("api/collections/{collection}/records")
    suspend fun getRecords(
        @Path("collection") collection: String,
        @Header("Authorization") token: String,
        @Query("page") page: Int,
        @Query("perPage") perPage: Int,
        @Query("filter") filter: String? = null,
        @Query("sort") sort: String? = null
    ): PBPaginatedResponse<PBProfileRecord>

    @GET("api/collections/arena_messages/records")
    suspend fun getArenaMessages(
        @Header("Authorization") token: String,
        @Query("page") page: Int,
        @Query("perPage") perPage: Int,
        @Query("filter") filter: String? = null,
        @Query("sort") sort: String? = null
    ): PBPaginatedResponse<ArenaMessage>

    @POST("api/collections/{collection}/records")
    suspend fun createRecord(
        @Path("collection") collection: String,
        @Header("Authorization") token: String,
        @Body body: RequestBody
    ): PBProfileRecord

    @PATCH("api/collections/{collection}/records/{id}")
    suspend fun updateRecord(
        @Path("collection") collection: String,
        @Path("id") id: String,
        @Header("Authorization") token: String,
        @Body body: RequestBody
    ): PBProfileRecord

    @GET("api/collections/{collection}/records/{id}")
    suspend fun getRecord(
        @Path("collection") collection: String,
        @Path("id") id: String,
        @Header("Authorization") token: String
    ): PBProfileRecord

    @DELETE("api/collections/{collection}/records/{id}")
    suspend fun deleteRecord(
        @Path("collection") collection: String,
        @Path("id") id: String,
        @Header("Authorization") token: String
    )
}
