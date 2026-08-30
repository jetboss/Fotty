package com.pixelperfect.fotty.data.repositories

import com.pixelperfect.fotty.data.models.League
import com.pixelperfect.fotty.data.providers.IFootballProvider
import javax.inject.Inject
import javax.inject.Singleton

@Singleton
class LeagueRepository @Inject constructor(
    private val provider: IFootballProvider
) {
    suspend fun getLeagues(): List<League> {
        val entries = provider.getLeagues()
        return entries.map { entry ->
            League(
                id = entry.league.id.toString(),
                name = entry.league.name,
                logoUrl = entry.league.logo ?: ""
            )
        }
    }
}
