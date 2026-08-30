package com.pixelperfect.fotty.data.providers

import com.pixelperfect.fotty.core.Config
import com.pixelperfect.fotty.core.network.api.football.APIFootballInterface
import com.pixelperfect.fotty.core.network.models.football.APIFootballFixture
import com.pixelperfect.fotty.core.network.models.football.APIFootballLeague
import javax.inject.Inject
import javax.inject.Singleton

@Singleton
class APIFootballProvider @Inject constructor(
    private val api: APIFootballInterface
) : IFootballProvider {

    private val apiKey = Config.footballAPIKey

    override suspend fun getLiveFixtures(): List<APIFootballFixture> {
        return try {
            val response = api.getLiveFixtures(apiKey)
            if (response.errors != null && response.errors is kotlinx.serialization.json.JsonObject && response.errors.isNotEmpty()) {
                val errorMsg = response.errors.toString()
                if (errorMsg.contains("request limit")) {
                    android.util.Log.w("APIFootballProvider", "API Quota Reached: Scores will be stale.")
                } else {
                    android.util.Log.e("APIFootballProvider", "Live API Errors: ${response.errors}")
                }
            }
            android.util.Log.d("APIFootballProvider", "Live response: ${response.response?.size} items")
            response.response ?: emptyList()
        } catch (e: Exception) {
            android.util.Log.e("APIFootballProvider", "Live execution error: ${e.message}")
            emptyList()
        }
    }

    override suspend fun getFixturesByDate(date: String): List<APIFootballFixture> {
        return try {
            val response = api.getFixturesByDate(apiKey, date)
            if (response.errors != null && response.errors is kotlinx.serialization.json.JsonObject && response.errors.isNotEmpty()) {
                android.util.Log.e("APIFootballProvider", "Date API Errors: ${response.errors}")
            }
            android.util.Log.d("APIFootballProvider", "Date ($date) response: ${response.response?.size} items")
            response.response ?: emptyList()
        } catch (e: Exception) {
            android.util.Log.e("APIFootballProvider", "Date execution error: ${e.message}")
            emptyList()
        }
    }

    override suspend fun getFixtureDetails(fixtureId: Int): APIFootballFixture? {
        return try {
            val response = api.getFixtureById(apiKey, fixtureId)
            response.response?.firstOrNull()
        } catch (e: Exception) {
            null
        }
    }

    override suspend fun getStandings(leagueId: Int): List<APIFootballLeague>? {
        return emptyList() 
    }

    override suspend fun getLeagues(): List<com.pixelperfect.fotty.core.network.models.football.APIFootballLeagueEntry> {
        return try {
            val response = api.getLeagues(apiKey)
            response.response ?: emptyList()
        } catch (e: Exception) {
            emptyList()
        }
    }

    override suspend fun getTeams(leagueId: Int): List<com.pixelperfect.fotty.core.network.models.football.APIFootballTeamEntry> {
        return try {
            val response = api.getTeams(apiKey, leagueId, 2025) // Season hardcoded for now or use current year
            response.response ?: emptyList()
        } catch (e: Exception) {
            emptyList()
        }
    }
}
