package com.pixelperfect.fotty.data.providers

import com.pixelperfect.fotty.core.network.models.football.APIFootballFixture
import com.pixelperfect.fotty.core.network.models.football.APIFootballLeague
import com.pixelperfect.fotty.core.network.models.football.APIFootballTeam
import com.pixelperfect.fotty.core.network.models.football.APIFootballLeagueEntry
import com.pixelperfect.fotty.core.network.models.football.APIFootballTeamEntry

interface IFootballProvider {
    suspend fun getLiveFixtures(): List<APIFootballFixture>
    suspend fun getFixturesByDate(date: String): List<APIFootballFixture>
    suspend fun getFixtureDetails(fixtureId: Int): APIFootballFixture?
    suspend fun getStandings(leagueId: Int): List<APIFootballLeague>?
    suspend fun getLeagues(): List<APIFootballLeagueEntry>
    suspend fun getTeams(leagueId: Int): List<APIFootballTeamEntry>
}
