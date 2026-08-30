package com.pixelperfect.fotty.features.auth.viewmodel

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.pixelperfect.fotty.core.network.api.pocketbase.PocketBaseInterface
import com.pixelperfect.fotty.core.network.models.pocketbase.PocketBaseSession
import com.pixelperfect.fotty.core.storage.AuthPreferenceStore
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.launch
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.RequestBody.Companion.toRequestBody
import javax.inject.Inject

@HiltViewModel
class AuthViewModel @Inject constructor(
    private val pbInterface: PocketBaseInterface,
    private val authPreferenceStore: AuthPreferenceStore
) : ViewModel() {

    var email by mutableStateOf("")
    var password by mutableStateOf("")
    var name by mutableStateOf("")
    var isSignupMode by mutableStateOf(false)
    var isGuest by mutableStateOf(false)
    var isRestoring by mutableStateOf(true)
    
    var isLoading by mutableStateOf(false)
    var error by mutableStateOf<String?>(null)
    var session by mutableStateOf<PocketBaseSession?>(null)

    init {
        restorePersistedAuthState()
    }

    private fun restorePersistedAuthState() {
        val persisted = authPreferenceStore.load()
        when (persisted.mode) {
            AuthPreferenceStore.MODE_GUEST -> {
                isGuest = true
                session = null
            }
            AuthPreferenceStore.MODE_SESSION -> {
                val token = persisted.token
                val userId = persisted.userId
                val userEmail = persisted.email
                if (!token.isNullOrBlank() && !userId.isNullOrBlank() && !userEmail.isNullOrBlank()) {
                    session = PocketBaseSession(token = token, userID = userId, email = userEmail)
                    isGuest = false
                } else {
                    authPreferenceStore.clear()
                    isGuest = false
                    session = null
                }
            }
            else -> {
                isGuest = false
                session = null
            }
        }
        isRestoring = false
    }

    fun signIn() {
        val identity = email.trim()
        val pass = password
        if (identity.isBlank() || pass.isBlank()) {
            error = "Email and password are required."
            return
        }

        viewModelScope.launch {
            isLoading = true
            error = null
            try {
                val bodyJson = buildJsonObject {
                    put("identity", identity)
                    put("password", pass)
                }
                val body = bodyJson.toString().toRequestBody("application/json".toMediaType())
                val response = pbInterface.authWithPassword(body)
                session = PocketBaseSession(response.token, response.record.id, response.record.email)
                isGuest = false
                authPreferenceStore.saveSession(
                    token = response.token,
                    userId = response.record.id,
                    email = response.record.email
                )
            } catch (e: Exception) {
                error = e.localizedMessage ?: "Could not sign in."
            } finally {
                isLoading = false
            }
        }
    }

    fun signUp() {
        val displayName = name.trim()
        val userEmail = email.trim()
        val pass = password

        if (displayName.isBlank()) {
            error = "Display name is required."
            return
        }
        if (userEmail.isBlank() || pass.isBlank()) {
            error = "Email and password are required."
            return
        }
        if (pass.length < 8) {
            error = "Password must be at least 8 characters."
            return
        }

        viewModelScope.launch {
            isLoading = true
            error = null
            try {
                val bodyJson = buildJsonObject {
                    put("email", userEmail)
                    put("password", pass)
                    put("passwordConfirm", pass)
                    put("name", displayName)
                }
                val body = bodyJson.toString().toRequestBody("application/json".toMediaType())
                pbInterface.createUser(body)

                val signInBodyJson = buildJsonObject {
                    put("identity", userEmail)
                    put("password", pass)
                }
                val signInBody = signInBodyJson.toString().toRequestBody("application/json".toMediaType())
                val response = pbInterface.authWithPassword(signInBody)
                session = PocketBaseSession(response.token, response.record.id, response.record.email)
                isGuest = false
                isSignupMode = false
                authPreferenceStore.saveSession(
                    token = response.token,
                    userId = response.record.id,
                    email = response.record.email
                )
            } catch (e: Exception) {
                error = e.localizedMessage ?: "Could not create account."
            } finally {
                isLoading = false
            }
        }
    }

    fun continueAsGuest() {
        isGuest = true
        session = null
        authPreferenceStore.saveGuest()
    }

    fun logout() {
        email = ""
        password = ""
        session = null
        isGuest = false
        authPreferenceStore.clear()
    }
}
