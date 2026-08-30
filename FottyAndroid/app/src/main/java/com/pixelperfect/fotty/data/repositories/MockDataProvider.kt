package com.pixelperfect.fotty.data.repositories

import com.pixelperfect.fotty.data.models.*

object MockDataProvider {
    val teams = listOf(
        Team("1", "Manchester City", "https://crests.football-data.org/65.png", "MCI"),
        Team("2", "Arsenal", "https://crests.football-data.org/57.png", "ARS"),
        Team("3", "Real Madrid", "https://crests.football-data.org/86.png", "RMA"),
        Team("4", "Barcelona", "https://crests.football-data.org/81.png", "BAR"),
        Team("9", "Bayern Munich", "https://crests.football-data.org/5.png", "BAY"),
        Team("10", "Paris Saint-Germain", "https://crests.football-data.org/524.png", "PSG"),
        Team("5", "LA Lakers", "https://logos-world.net/wp-content/uploads/2020/11/Los-Angeles-Lakers-Logo.png", "LAL"),
        Team("6", "GS Warriors", "https://logos-world.net/wp-content/uploads/2020/11/Golden-State-Warriors-Logo.png", "GSW")
    )

    val leagues = listOf(
        League("1", "Premier League", "https://crests.football-data.org/PL.png"),
        League("2", "Champions League", "https://crests.football-data.org/CL.png"),
        League("3", "NBA", "https://logos-world.net/wp-content/uploads/2020/11/NBA-Logo.png"),
        League("4", "UFC", "https://logos-world.net/wp-content/uploads/2020/11/UFC-Logo.png")
    )

    val liveMatches = listOf(
        Match(
            id = "101",
            homeTeam = teams[4], // Bayern
            awayTeam = teams[5], // PSG
            homeScore = 0,
            awayScore = 0,
            status = MatchStatus.SCHEDULED,
            timestamp = System.currentTimeMillis() + 3600000 * 9, // Tonight
            league = leagues[1],
            hypeLevel = 1.0f,
            category = "football",
            activePeers = 0,
            healthScore = 100
        )
    )

    val upcomingMatches = emptyList<Match>()

    val highlights = listOf(
        Highlight(
            id = "h1",
            title = "Man City vs Arsenal - Full Highlights",
            thumbnailUrl = "https://images.unsplash.com/photo-1574629810360-7efbbe195018",
            duration = "10:24",
            videoUrl = ""
        ),
        Highlight(
            id = "h2",
            title = "LeBron James - 40pt Masterclass",
            thumbnailUrl = "https://images.unsplash.com/photo-1508098682722-e99c43a406b2",
            duration = "04:15",
            videoUrl = ""
        )
    )
}
