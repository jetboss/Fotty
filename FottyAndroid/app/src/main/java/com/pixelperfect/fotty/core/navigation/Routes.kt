package com.pixelperfect.fotty.core.navigation

sealed class Route(val path: String) {
    // Foundation
    object Splash : Route("splash")
    object Onboarding : Route("onboarding")
    
    // Core Bottom Nav
    object Home : Route("home")
    object Matches : Route("matches")
    object Live : Route("live")
    object Arena : Route("arena")
    object Clips : Route("clips")
    object Explore : Route("explore")
    object JusticeTable : Route("justice_table")
    object Settings : Route("settings")
    
    // Detail Views
    object MatchDetail : Route("match/{fixtureId}") {
        fun create(fixtureId: String) = "match/$fixtureId"
    }
    object Player : Route("player/{fixtureId}?home={home}&away={away}&category={category}") {
        fun create(fixtureId: String, home: String = "", away: String = "", category: String = "football") = 
            "player/$fixtureId?home=$home&away=$away&category=$category"
    }
    object TeamDetail : Route("team/{teamId}") {
        fun create(teamId: String) = "team/$teamId"
    }
    object LeagueDetail : Route("league/{leagueId}") {
        fun create(leagueId: String) = "league/$leagueId"
    }
    object NewsDetail : Route("news_detail?url={url}&title={title}") {
        fun create(url: String, title: String) = "news_detail?url=${java.net.URLEncoder.encode(url, "UTF-8")}&title=${java.net.URLEncoder.encode(title, "UTF-8")}"
    }
}

