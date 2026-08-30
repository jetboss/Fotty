package com.pixelperfect.fotty.data.repositories

import com.pixelperfect.fotty.data.models.Team
import com.pixelperfect.fotty.data.providers.IFootballProvider
import javax.inject.Inject
import javax.inject.Singleton

@Singleton
class TeamRepository @Inject constructor(
    private val provider: IFootballProvider
) {
    suspend fun getTeams(leagueId: String): List<Team> {
        val entries = provider.getTeams(leagueId.toIntOrNull() ?: 0)
        return entries.map { entry ->
            Team(
                id = entry.team.id.toString(),
                name = entry.team.name,
                logoUrl = entry.team.logo ?: ""
            )
        }
    }
}
