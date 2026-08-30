package com.pixelperfect.fotty.core.network.repository.football

import com.pixelperfect.fotty.core.Config
import com.pixelperfect.fotty.core.network.api.football.FootballInterface
import com.pixelperfect.fotty.core.network.models.football.*
import com.pixelperfect.fotty.core.network.models.sportmonks.*
import kotlinx.serialization.json.JsonPrimitive
import javax.inject.Inject
import javax.inject.Singleton

@Singleton
class FootballRepository @Inject constructor(
    private val footballInterface: FootballInterface,
    private val fottyFootballProxy: com.pixelperfect.fotty.core.network.api.football.FottyFootballProxyInterface,
    private val apiFootballInterface: com.pixelperfect.fotty.core.network.api.football.APIFootballInterface,
    private val footballProInterface: com.pixelperfect.fotty.core.network.api.football.FootballProInterface
) {
    private val apiKey = Config.footballAPIKey
    private val rapidAPIKey = Config.rapidAPIKey
    private val apiFootballKey = Config.apiFootballKey

    private suspend fun footballDataMatches(
        competition: String? = null,
        status: String? = null,
        limit: Int? = null,
        dateFrom: String? = null,
        dateTo: String? = null,
        season: String? = null,
    ): List<FootballMatch> {
        if (Config.prefersFootballDataProxy) {
            try {
                return fottyFootballProxy.getMatches(
                    competition = competition,
                    status = status,
                    limit = limit,
                    dateFrom = dateFrom,
                    dateTo = dateTo,
                    season = season,
                ).matches
            } catch (e: Exception) {
                android.util.Log.w("FootballRepository", "Fotty football proxy failed; falling back to direct API", e)
            }
        }
        if (apiKey.isBlank()) return emptyList()
        val league = competition ?: return emptyList()
        return footballInterface.getMatches(
            league = league,
            apiKey = apiKey,
            status = status,
            limit = limit,
            dateFrom = dateFrom,
            dateTo = dateTo,
        ).matches
    }

    // ── Fixture Fetching ─────────────────────────────────────────────────────

    suspend fun getGlobalLiveScores(): List<com.pixelperfect.fotty.core.network.models.football.APIFootballFixture> {
        return try {
            apiFootballInterface.getLiveFixtures(
                apiKey = apiFootballKey
            ).response ?: emptyList()
        } catch (e: Exception) {
            android.util.Log.e("FootballRepository", "Error fetching live scores", e)
            emptyList()
        }
    }

    suspend fun getFixturesByDate(date: String, leagueName: String? = null): List<com.pixelperfect.fotty.core.network.models.football.APIFootballFixture> {
        // Dynamic Season Calculation: August starts the new season for most leagues
        val year = try { date.substring(0, 4).toInt() } catch (e: Exception) { 2025 }
        val month = try { date.substring(5, 7).toInt() } catch (e: Exception) { 1 }
        val calculatedSeason = if (month >= 8) year else year - 1
        
        android.util.Log.d("FootballRepository", "STABILIZATION: Dynamic Season Resolution -> $date belongs to Season $calculatedSeason")
        
        return try {
            // We use the Date-First approach for maximum compatibility across all leagues
            apiFootballInterface.getFixturesByDate(
                apiKey = apiFootballKey, 
                date = date,
                season = calculatedSeason
            ).response ?: emptyList()
        } catch (e: Exception) {
            android.util.Log.e("FootballRepository", "Error fetching fixtures for $date", e)
            emptyList()
        }
    }

    suspend fun getMatchDetails(fixtureId: Int): APIFootballFixture? {
        return try {
            apiFootballInterface.getFixtureById(
                apiKey = apiFootballKey,
                fixtureId = fixtureId
            ).response?.firstOrNull()
        } catch (e: Exception) {
            android.util.Log.e("FootballRepository", "Error fetching fixture details for $fixtureId", e)
            null
        }
    }

    suspend fun searchParticipants(teamName: String): List<com.pixelperfect.fotty.core.network.models.sportmonks.SportmonksParticipant> {
        return try {
            footballProInterface.searchParticipants(apiKey = rapidAPIKey, name = teamName).data
        } catch (e: Exception) {
            android.util.Log.e("FootballRepository", "Participant search failed for $teamName", e)
            emptyList()
        }
    }

    suspend fun getFixturesByParticipant(from: String, to: String, participantId: Int): List<APIFootballFixture> {
        return try {
            val response = footballProInterface.getFixturesByParticipant(
                apiKey = rapidAPIKey,
                from = from,
                to = to,
                participantId = participantId
            ).data
            response.map { it.toAPIFootballFixture() }
        } catch (e: Exception) {
            android.util.Log.e("FootballRepository", "Fixture fetch failed for participant $participantId", e)
            emptyList()
        }
    }

    suspend fun getSportmonksFixturesByDate(date: String): List<APIFootballFixture> {
        return try {
            val response = footballProInterface.getFixturesByDate(
                apiKey = rapidAPIKey,
                date = date
            ).data
            response.map { it.toAPIFootballFixture() }
        } catch (e: Exception) {
            android.util.Log.e("FootballRepository", "Sportmonks date fetch failed for $date", e)
            emptyList()
        }
    }

    suspend fun getUpcomingMatches(league: League, limit: Int = 15): List<FootballMatch> {
        return footballDataMatches(
            competition = league.code,
            status = "SCHEDULED,TIMED,IN_PLAY,PAUSED",
            limit = limit,
        )
    }

    suspend fun getRecentResults(league: League, limit: Int = 10): List<FootballMatch> {
        return footballDataMatches(
            competition = league.code,
            status = "FINISHED",
            limit = limit,
        )
    }

    suspend fun getMatchesByDateRange(league: String, from: String, to: String): List<FootballMatch> {
        return try {
            footballDataMatches(
                competition = league,
                dateFrom = from,
                dateTo = to,
            )
        } catch (e: Exception) {
            android.util.Log.e("FootballRepository", "Error fetching matches for $league range", e)
            emptyList()
        }
    }

    // ── Analytics Fetching ───────────────────────────────────────────────────

    suspend fun getMatchLineups(fixtureId: Int): List<APIFootballLineup> {
        return try {
            // AUTHORITATIVE PRO BRIDGE: Use Sportmonks directly for lineups
            android.util.Log.w("FootballRepository", "PRO_BRIDGE: Fetching Lineups from Sportmonks for $fixtureId")
            val proFixture = footballProInterface.getFixtureById(apiKey = rapidAPIKey, id = fixtureId).data
            proFixture.toAPIFootballLineups()
        } catch (e: Exception) {
            android.util.Log.e("FootballRepository", "PRO_BRIDGE: Lineups fetch failed for $fixtureId", e)
            emptyList()
        }
    }

    suspend fun getLegacyMatchLineups(fixtureId: Int): List<APIFootballLineup> {
        return try {
            apiFootballInterface.getFixtureLineups(
                apiKey = apiFootballKey,
                fixtureId = fixtureId
            ).response
        } catch (e: Exception) {
            emptyList()
        }
    }

    suspend fun getMatchStatistics(fixtureId: Int): List<APIFootballTeamStats> {
        return try {
            // AUTHORITATIVE PRO BRIDGE: Use Sportmonks directly for stats
            android.util.Log.w("FootballRepository", "PRO_BRIDGE: Fetching Stats from Sportmonks for $fixtureId")
            val proFixture = footballProInterface.getFixtureById(apiKey = rapidAPIKey, id = fixtureId).data
            proFixture.toAPIFootballStats()
        } catch (e: Exception) {
            android.util.Log.e("FootballRepository", "PRO_BRIDGE: Stats fetch failed for $fixtureId", e)
            emptyList()
        }
    }

    suspend fun getLegacyMatchStatistics(fixtureId: Int): List<APIFootballTeamStats> {
        return try {
            apiFootballInterface.getFixtureStatistics(
                apiKey = apiFootballKey,
                fixtureId = fixtureId
            ).response
        } catch (e: Exception) {
            emptyList()
        }
    }

    suspend fun getMatchEvents(fixtureId: Int): List<APIFootballEvent> {
        return try {
            // AUTHORITATIVE PRO BRIDGE: Use Sportmonks directly for events
            android.util.Log.w("FootballRepository", "PRO_BRIDGE: Fetching Events from Sportmonks for $fixtureId")
            val proFixture = footballProInterface.getFixtureById(apiKey = rapidAPIKey, id = fixtureId).data
            proFixture.toAPIFootballEvents()
        } catch (e: Exception) {
            android.util.Log.e("FootballRepository", "PRO_BRIDGE: Events fetch failed for $fixtureId", e)
            emptyList()
        }
    }

    suspend fun getLegacyMatchEvents(fixtureId: Int): List<APIFootballEvent> {
        return try {
            apiFootballInterface.getFixtureEvents(
                apiKey = apiFootballKey,
                fixtureId = fixtureId
            ).response
        } catch (e: Exception) {
            emptyList()
        }
    }

    suspend fun getMatchIntelligence(fixtureId: Int): com.pixelperfect.fotty.data.models.MatchIntelligence? {
        return try {
            val stats = getMatchStatistics(fixtureId)
            if (stats.size < 2) return null

            val homeStats = stats[0].statistics
            val awayStats = stats[1].statistics

            fun extractValue(statsList: List<APIFootballStatistic>, type: String): Float {
                val element = statsList.find { it.type == type }?.value ?: return 0f
                return try {
                    if (element is kotlinx.serialization.json.JsonPrimitive) {
                        element.content.replace("%", "").toFloatOrNull() ?: 0f
                    } else 0f
                } catch (e: Exception) { 0f }
            }

            com.pixelperfect.fotty.data.models.MatchIntelligence(
                possessionHome = extractValue(homeStats, "Ball Possession").toInt().coerceIn(0, 100),
                possessionAway = extractValue(awayStats, "Ball Possession").toInt().coerceIn(0, 100),
                shotsOnGoalHome = extractValue(homeStats, "Shots on Goal").toInt(),
                shotsOnGoalAway = extractValue(awayStats, "Shots on Goal").toInt(),
                xGHome = extractValue(homeStats, "Expected Goals (xG)"),
                xGAway = extractValue(awayStats, "Expected Goals (xG)"),
                winProbabilityHome = 0.45f,
                winProbabilityAway = 0.30f
            )
        } catch (e: Exception) {
            android.util.Log.e("FootballRepository", "Error building intelligence for $fixtureId", e)
            null
        }
    }
}

// Extension to map Football-Data.org models to API-Football models for UI compatibility
fun FootballMatch.toAPIFootballFixture(): com.pixelperfect.fotty.core.network.models.football.APIFootballFixture {
    return com.pixelperfect.fotty.core.network.models.football.APIFootballFixture(
        fixture = com.pixelperfect.fotty.core.network.models.football.APIFootballFixtureInfo(
            id = this.id,
            status = com.pixelperfect.fotty.core.network.models.football.APIFootballStatus(
                long = this.status,
                short = when(this.status) {
                    "IN_PLAY" -> "LIVE"
                    "PAUSED" -> "HT"
                    "FINISHED" -> "FT"
                    else -> "TBD"
                },
                elapsed = null
            ),
            date = this.utcDate
        ),
        league = com.pixelperfect.fotty.core.network.models.football.APIFootballLeague(
            id = this.competition.id ?: 0,
            name = this.competition.name ?: "",
            logo = this.competition.emblem ?: ""
        ),
        teams = com.pixelperfect.fotty.core.network.models.football.APIFootballTeams(
            home = com.pixelperfect.fotty.core.network.models.football.APIFootballTeam(
                id = this.homeTeam.id ?: 0,
                name = this.homeTeam.shortName ?: this.homeTeam.name ?: "Home",
                logo = this.homeTeam.crest ?: ""
            ),
            away = com.pixelperfect.fotty.core.network.models.football.APIFootballTeam(
                id = this.awayTeam.id ?: 0,
                name = this.awayTeam.shortName ?: this.awayTeam.name ?: "Away",
                logo = this.awayTeam.crest ?: ""
            )
        ),
        goals = com.pixelperfect.fotty.core.network.models.football.APIFootballGoals(
            home = this.score.fullTime?.home,
            away = this.score.fullTime?.away
        ),
        score = com.pixelperfect.fotty.core.network.models.football.APIFootballScore(
            halftime = com.pixelperfect.fotty.core.network.models.football.APIFootballGoals(
                home = this.score.halfTime?.home,
                away = this.score.halfTime?.away
            ),
            fulltime = com.pixelperfect.fotty.core.network.models.football.APIFootballGoals(
                home = this.score.fullTime?.home,
                away = this.score.fullTime?.away
            )
        )
    )
}

// Mapping Sportmonks Pro data to API-Football UI Models
fun com.pixelperfect.fotty.core.network.models.sportmonks.SportmonksFixture.toAPIFootballFixture(): com.pixelperfect.fotty.core.network.models.football.APIFootballFixture {
    val homeParticipant = this.participants?.find { it.meta?.location == "home" } ?: this.participants?.firstOrNull()
    val awayParticipant = this.participants?.find { it.meta?.location == "away" } ?: this.participants?.getOrNull(1)
    
    val homeScore = this.scores?.find { it.participant_id == homeParticipant?.id }?.score?.goals
    val awayScore = this.scores?.find { it.participant_id == awayParticipant?.id }?.score?.goals

    return com.pixelperfect.fotty.core.network.models.football.APIFootballFixture(
        fixture = com.pixelperfect.fotty.core.network.models.football.APIFootballFixtureInfo(
            id = this.id,
            status = com.pixelperfect.fotty.core.network.models.football.APIFootballStatus(
                long = "Finished",
                short = "FT",
                elapsed = 90
            ),
            date = this.starting_at
        ),
        league = com.pixelperfect.fotty.core.network.models.football.APIFootballLeague(
            id = this.league?.id ?: 0,
            name = this.league?.name ?: "",
            logo = this.league?.image_path ?: ""
        ),
        teams = com.pixelperfect.fotty.core.network.models.football.APIFootballTeams(
            home = com.pixelperfect.fotty.core.network.models.football.APIFootballTeam(
                id = homeParticipant?.id ?: 0,
                name = homeParticipant?.name ?: "Home",
                logo = homeParticipant?.image_path ?: ""
            ),
            away = com.pixelperfect.fotty.core.network.models.football.APIFootballTeam(
                id = awayParticipant?.id ?: 0,
                name = awayParticipant?.name ?: "Away",
                logo = awayParticipant?.image_path ?: ""
            )
        ),
        goals = com.pixelperfect.fotty.core.network.models.football.APIFootballGoals(home = homeScore, away = awayScore),
        score = com.pixelperfect.fotty.core.network.models.football.APIFootballScore(
            halftime = com.pixelperfect.fotty.core.network.models.football.APIFootballGoals(null, null),
            fulltime = com.pixelperfect.fotty.core.network.models.football.APIFootballGoals(homeScore, awayScore)
        )
    )
}

fun com.pixelperfect.fotty.core.network.models.sportmonks.SportmonksFixture.toAPIFootballLineups(): List<com.pixelperfect.fotty.core.network.models.football.APIFootballLineup> {
    val flatLineups = this.lineups ?: return emptyList()
    
    // Group by Team ID
    return flatLineups.groupBy { it.team_id }.map { (teamId, players) ->
        val participant = this.participants?.find { it.id == teamId }
        
        val homeXI = players.filter { it.type_id == 11 } // 11 is Starting Lineup in v3
        val subs = players.filter { it.type_id == 12 } // 12 is Substitutes in v3

        com.pixelperfect.fotty.core.network.models.football.APIFootballLineup(
            team = com.pixelperfect.fotty.core.network.models.football.APIFootballTeam(
                id = teamId,
                name = participant?.name ?: "Unknown Team",
                logo = participant?.image_path ?: ""
            ),
            formation = "Tactical",
            startXI = homeXI.map { it.toAPIFootballPlayerEntry() },
            substitutes = subs.map { it.toAPIFootballPlayerEntry() },
            coach = com.pixelperfect.fotty.core.network.models.football.APIFootballCoach(name = "TBD")
        )
    }
}

fun com.pixelperfect.fotty.core.network.models.sportmonks.SportmonksLineup.toAPIFootballPlayerEntry(): com.pixelperfect.fotty.core.network.models.football.APIFootballPlayerEntry {
    // Sportmonks v3 Grid Fallback: V3 uses 'formation_field' for X:Y coordinates
    val resolvedGrid = this.formation_field ?: when(this.formation_position) {
        1 -> "1:1" // GK
        2, 3, 4, 5 -> "2:${this.formation_position - 1}" // Defense
        6, 7, 8 -> "3:${this.formation_position - 5}" // Midfield
        9, 10, 11 -> "4:${this.formation_position - 8}" // Attack
        else -> "5:1" // Subs/Other
    }

    val xG = this.statistics?.find { it.type_id == 5304 }?.data?.value ?: 0f
    val xA = this.statistics?.find { it.type_id == 1548 }?.data?.value ?: 0f // Standard xA ID fallback

    return com.pixelperfect.fotty.core.network.models.football.APIFootballPlayerEntry(
        player = com.pixelperfect.fotty.core.network.models.football.APIFootballPlayerInfo(
            id = this.player_id,
            name = this.player_name,
            number = this.jersey_number,
            pos = null,
            grid = resolvedGrid,
            xg = xG,
            xa = xA
        )
    )
}

fun com.pixelperfect.fotty.core.network.models.sportmonks.SportmonksFixture.toAPIFootballStats(): List<com.pixelperfect.fotty.core.network.models.football.APIFootballTeamStats> {
    val homeParticipant = this.participants?.find { it.meta?.location == "home" } ?: this.participants?.firstOrNull()
    val awayParticipant = this.participants?.find { it.meta?.location == "away" } ?: this.participants?.getOrNull(1)

    val stats = this.statistics ?: emptyList()

    fun mapStats(participantId: Int?): List<com.pixelperfect.fotty.core.network.models.football.APIFootballStatistic> {
        val teamStats = stats.filter { it.participant_id == participantId }
        return listOfNotNull(
            teamStats.find { it.type_id == 45 }?.let { com.pixelperfect.fotty.core.network.models.football.APIFootballStatistic("Ball Possession", JsonPrimitive((it.data?.value?.toInt() ?: 0).toString())) },
            teamStats.find { it.type_id == 5304 }?.let { com.pixelperfect.fotty.core.network.models.football.APIFootballStatistic("Expected Goals (xG)", JsonPrimitive((it.data?.value ?: 0f).toString())) },
            teamStats.find { it.type_id == 5305 }?.let { com.pixelperfect.fotty.core.network.models.football.APIFootballStatistic("xG on Target (xGoT)", JsonPrimitive((it.data?.value ?: 0f).toString())) },
            teamStats.find { it.type_id == 580 }?.let { com.pixelperfect.fotty.core.network.models.football.APIFootballStatistic("Big Chances Created", JsonPrimitive((it.data?.value?.toInt() ?: 0).toString())) },
            teamStats.find { it.type_id == 116 }?.let { com.pixelperfect.fotty.core.network.models.football.APIFootballStatistic("Total Passes", JsonPrimitive((it.data?.value?.toInt() ?: 0).toString())) }
        )
    }

    return listOf(
        com.pixelperfect.fotty.core.network.models.football.APIFootballTeamStats(
            team = com.pixelperfect.fotty.core.network.models.football.APIFootballTeam(
                id = homeParticipant?.id ?: 0,
                name = homeParticipant?.name ?: "Home",
                logo = homeParticipant?.image_path ?: ""
            ),
            statistics = mapStats(homeParticipant?.id)
        ),
        com.pixelperfect.fotty.core.network.models.football.APIFootballTeamStats(
            team = com.pixelperfect.fotty.core.network.models.football.APIFootballTeam(
                id = awayParticipant?.id ?: 0,
                name = awayParticipant?.name ?: "Away",
                logo = awayParticipant?.image_path ?: ""
            ),
            statistics = mapStats(awayParticipant?.id)
        )
    )
}

fun com.pixelperfect.fotty.core.network.models.sportmonks.SportmonksFixture.toAPIFootballEvents(): List<com.pixelperfect.fotty.core.network.models.football.APIFootballEvent> {
    val events = this.events ?: return emptyList()
    return events.map { event ->
        com.pixelperfect.fotty.core.network.models.football.APIFootballEvent(
            time = com.pixelperfect.fotty.core.network.models.football.APIFootballEventTime(
                elapsed = event.minute,
                extra = null
            ),
            team = com.pixelperfect.fotty.core.network.models.football.APIFootballTeam(
                id = event.team_id ?: 0,
                name = "",
                logo = ""
            ),
            player = com.pixelperfect.fotty.core.network.models.football.APIFootballPlayerInfo(
                id = 0,
                name = event.player_name ?: "Unknown"
            ),
            assist = com.pixelperfect.fotty.core.network.models.football.APIFootballPlayerInfo(
                id = 0,
                name = event.related_player_name ?: ""
            ),
            type = when(event.type_id) {
                14 -> "Goal"
                17 -> "Card"
                18 -> "subst"
                else -> "Other"
            },
            detail = if (event.type_id == 17) "Yellow Card" else "",
            comments = null
        )
    }
}
