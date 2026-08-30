package com.pixelperfect.fotty.core.storage

import android.content.Context
import android.content.SharedPreferences
import androidx.security.crypto.EncryptedSharedPreferences
import androidx.security.crypto.MasterKey
import dagger.hilt.android.qualifiers.ApplicationContext
import kotlinx.serialization.Serializable
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json
import javax.inject.Inject
import javax.inject.Singleton

@Serializable
data class PersistedAuthState(
    val mode: String = "none",
    val token: String? = null,
    val userId: String? = null,
    val email: String? = null
)

@Singleton
class AuthPreferenceStore @Inject constructor(
    @ApplicationContext private val context: Context,
    private val json: Json
) {
    // Dedicated high-reliability store for onboarding only
    private val onboardingPrefs = context.getSharedPreferences("fotty_onboarding_v2", Context.MODE_PRIVATE)
    
    // Lazy initialization to avoid crashes during DI or if Keystore is busy
    private val securePrefs: SharedPreferences by lazy { createSecurePreferences() }
    private val legacyPrefs: SharedPreferences by lazy { context.getSharedPreferences(LEGACY_PREFS_NAME, Context.MODE_PRIVATE) }

    fun load(): PersistedAuthState {
        // PRIORITY 1: Check the high-reliability onboarding flag first
        val isFinished = onboardingPrefs.getBoolean(KEY_ONBOARDING_FINISHED, false)
        android.util.Log.d("AuthStore", "Checking onboarding status: $isFinished")

        // Try to load from secure storage
        val raw = try {
            securePrefs.getString(KEY_AUTH_STATE, null) ?: legacyPrefs.getString(KEY_AUTH_STATE, null)
        } catch (e: Exception) {
            android.util.Log.e("AuthStore", "Failed to read primary prefs", e)
            null
        }

        val state = if (raw != null) {
            runCatching { json.decodeFromString<PersistedAuthState>(raw) }.getOrNull()
        } else null

        // If we have a session (token/user), always prioritize it
        if (state != null && state.mode == MODE_SESSION) {
            return state
        }

        // If onboarding is finished but we don't have a session, we are a GUEST
        if (isFinished) {
            android.util.Log.d("AuthStore", "Onboarding is finished, forcing GUEST mode")
            return PersistedAuthState(mode = MODE_GUEST)
        }

        // Otherwise, return whatever we have or 'none'
        return state ?: PersistedAuthState()
    }

    fun saveGuest() {
        android.util.Log.i("AuthStore", "Saving GUEST state and locking onboarding flag")
        // Synchronous commit to ensure it's on disk before navigation
        onboardingPrefs.edit().putBoolean(KEY_ONBOARDING_FINISHED, true).commit()
        persist(PersistedAuthState(mode = MODE_GUEST))
    }

    fun saveSession(token: String, userId: String, email: String) {
        onboardingPrefs.edit().putBoolean(KEY_ONBOARDING_FINISHED, true).commit()
        persist(
            PersistedAuthState(
                mode = MODE_SESSION,
                token = token,
                userId = userId,
                email = email
            )
        )
    }

    fun clear() {
        onboardingPrefs.edit().clear().commit()
        runCatching { securePrefs.edit().clear().apply() }
        legacyPrefs.edit().clear().apply()
    }

    private fun persist(state: PersistedAuthState) {
        val raw = json.encodeToString(state)
        try {
            securePrefs.edit().putString(KEY_AUTH_STATE, raw).apply()
        } catch (e: Exception) {
            android.util.Log.e("AuthStore", "Secure persist failed, using legacy", e)
            legacyPrefs.edit().putString(KEY_AUTH_STATE, raw).apply()
        }
    }

    private fun createSecurePreferences(): SharedPreferences {
        return runCatching {
            val masterKey = MasterKey.Builder(context)
                .setKeyScheme(MasterKey.KeyScheme.AES256_GCM)
                .build()

            EncryptedSharedPreferences.create(
                context,
                ENCRYPTED_PREFS_NAME,
                masterKey,
                EncryptedSharedPreferences.PrefKeyEncryptionScheme.AES256_SIV,
                EncryptedSharedPreferences.PrefValueEncryptionScheme.AES256_GCM
            )
        }.getOrElse {
            android.util.Log.e("AuthStore", "EncryptedSharedPreferences creation failed", it)
            context.getSharedPreferences(LEGACY_PREFS_NAME, Context.MODE_PRIVATE)
        }
    }

    companion object {
        private const val LEGACY_PREFS_NAME = "fotty_auth_v1"
        private const val ENCRYPTED_PREFS_NAME = "fotty_auth_secure_v1"
        private const val KEY_AUTH_STATE = "auth_state"
        private const val KEY_ONBOARDING_FINISHED = "onboarding_finished_v2"
        const val MODE_SESSION = "session"
        const val MODE_GUEST = "guest"
    }
}
