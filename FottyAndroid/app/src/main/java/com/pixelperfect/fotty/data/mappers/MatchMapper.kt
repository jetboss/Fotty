package com.pixelperfect.fotty.data.mappers

import com.pixelperfect.fotty.core.network.models.football.*
import com.pixelperfect.fotty.data.models.Match
import com.pixelperfect.fotty.data.models.MatchStatus
import com.pixelperfect.fotty.data.models.Team
import com.pixelperfect.fotty.data.models.League
import java.time.OffsetDateTime
import java.time.format.DateTimeFormatter

fun APIFootballFixture.toMatch(): Match {
    return Match(
        id = this.fixture.id.toString(),
        homeTeam = this.teams.home.toTeam(),
        awayTeam = this.teams.away.toTeam(),
        homeScore = this.goals.home,
        awayScore = this.goals.away,
        status = this.fixture.status.toMatchStatus(),
        timestamp = this.fixture.date?.let { 
            try {
                OffsetDateTime.parse(it, DateTimeFormatter.ISO_OFFSET_DATE_TIME).toInstant().toEpochMilli()
            } catch (e: Exception) {
                0L
            }
        } ?: 0L,
        league = this.league.toLeague().copy(
            name = com.pixelperfect.fotty.core.util.LeagueResolver.standardize(this.league.name)
        ),
        minute = this.fixture.status.elapsed,
        hypeLevel = 0.5f,
        category = "football",
        statusText = this.fixture.status.long
    )
}

fun APIFootballTeam.toTeam(): Team {
    // Ensure high-fidelity logo resolution
    val resolvedLogo = this.logo
    return Team(
        id = this.id.toString(),
        name = this.name,
        logoUrl = resolvedLogo,
        shortName = null
    )
}

fun APIFootballLeague.toLeague(): League {
    return League(
        id = this.id.toString(),
        name = this.name,
        logoUrl = this.logo
    )
}

fun APIFootballStatus.toMatchStatus(): MatchStatus {
    return when (this.short) {
        "PST" -> MatchStatus.POSTPONED
        "FT", "AET", "PEN" -> MatchStatus.FINISHED
        "1H", "2H", "ET", "P", "BT", "HT", "LIVE", "IN_PLAY", "BREAK", "PAUSED", "SUSP", "INT" -> MatchStatus.LIVE
        else -> MatchStatus.SCHEDULED
    }
}
