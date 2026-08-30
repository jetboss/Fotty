package com.pixelperfect.fotty.core.storage

import android.content.Context
import androidx.datastore.core.DataStore
import androidx.datastore.preferences.core.*
import androidx.datastore.preferences.preferencesDataStore
import dagger.hilt.android.qualifiers.ApplicationContext
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.map
import javax.inject.Inject
import javax.inject.Singleton

private val Context.dataStore: DataStore<Preferences> by preferencesDataStore(name = "settings")

@Singleton
class UserPreferencesRepository @Inject constructor(
    @ApplicationContext private val context: Context
) {
    private object Keys {
        val THEME_MODE = stringPreferencesKey("theme_mode") // "dark", "light", "system"
        val HAPTICS_ENABLED = booleanPreferencesKey("haptics_enabled")
        val STREAM_QUALITY = stringPreferencesKey("stream_quality") // "auto", "high", "low"
        val FOLLOWED_TEAMS = stringSetPreferencesKey("followed_teams")
        val FOLLOWED_LEAGUES = stringSetPreferencesKey("followed_leagues")
    }

    val themeMode: Flow<String> = context.dataStore.data.map { preferences ->
        preferences[Keys.THEME_MODE] ?: "system"
    }

    val hapticsEnabled: Flow<Boolean> = context.dataStore.data.map { preferences ->
        preferences[Keys.HAPTICS_ENABLED] ?: true
    }

    val streamQuality: Flow<String> = context.dataStore.data.map { preferences ->
        preferences[Keys.STREAM_QUALITY] ?: "auto"
    }

    val followedTeams: Flow<Set<String>> = context.dataStore.data.map { preferences ->
        preferences[Keys.FOLLOWED_TEAMS] ?: emptySet()
    }

    val followedLeagues: Flow<Set<String>> = context.dataStore.data.map { preferences ->
        preferences[Keys.FOLLOWED_LEAGUES] ?: emptySet()
    }

    suspend fun setThemeMode(mode: String) {
        context.dataStore.edit { preferences ->
            preferences[Keys.THEME_MODE] = mode
        }
    }

    suspend fun setHapticsEnabled(enabled: Boolean) {
        context.dataStore.edit { preferences ->
            preferences[Keys.HAPTICS_ENABLED] = enabled
        }
    }

    suspend fun setStreamQuality(quality: String) {
        context.dataStore.edit { preferences ->
            preferences[Keys.STREAM_QUALITY] = quality
        }
    }

    suspend fun followTeam(teamId: String) {
        context.dataStore.edit { preferences ->
            val current = preferences[Keys.FOLLOWED_TEAMS] ?: emptySet()
            preferences[Keys.FOLLOWED_TEAMS] = current + teamId
        }
    }

    suspend fun unfollowTeam(teamId: String) {
        context.dataStore.edit { preferences ->
            val current = preferences[Keys.FOLLOWED_TEAMS] ?: emptySet()
            preferences[Keys.FOLLOWED_TEAMS] = current - teamId
        }
    }

    suspend fun followLeague(leagueId: String) {
        context.dataStore.edit { preferences ->
            val current = preferences[Keys.FOLLOWED_LEAGUES] ?: emptySet()
            preferences[Keys.FOLLOWED_LEAGUES] = current + leagueId
        }
    }

    suspend fun unfollowLeague(leagueId: String) {
        context.dataStore.edit { preferences ->
            val current = preferences[Keys.FOLLOWED_LEAGUES] ?: emptySet()
            preferences[Keys.FOLLOWED_LEAGUES] = current - leagueId
        }
    }
}
