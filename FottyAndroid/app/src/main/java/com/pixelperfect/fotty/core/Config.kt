package com.pixelperfect.fotty.core

import com.pixelperfect.fotty.BuildConfig

object Config {
    /** Set `P2P_API_PASSWORD` in `local.properties` for dev builds — never commit the real value. */
    val p2pApiPassword: String
        get() = BuildConfig.P2P_API_PASSWORD
    const val pocketBaseBaseURLString = "https://fotty-api.pixel-invoice.com"
    /** Homelab web host for football-data.org proxying (`/api/football/matches`). */
    val footballProxyBaseURLString: String
        get() = BuildConfig.FOTTY_WEB_BASE_URL.ifBlank { "https://fotty.pixel-invoice.com" }
    val prefersFootballDataProxy: Boolean
        get() = BuildConfig.FOTTY_FOOTBALL_PROXY_ENABLED
    
    // Development credentials come from gitignored local.properties.
    val footballAPIKey: String
        get() = BuildConfig.FOOTBALL_DATA_API_KEY
    
    // Football Pro (RapidAPI - Sportmonks v3)
    val rapidAPIKey: String
        get() = BuildConfig.RAPID_API_KEY
    const val footballProHost = "football-pro.p.rapidapi.com"
    
    // API-Football (api-sports.io)
    val apiFootballKey: String
        get() = BuildConfig.API_FOOTBALL_KEY
    const val apiFootballHost = "v3.football.api-sports.io"
    
    const val legalBaseURLString = "https://getfotty.com"
    const val privacyPolicyPath = "/privacy"
    const val termsOfUsePath = "/terms"

    enum class AppDistributionMode(val value: String) {
        FULL("full"),
        REVIEW_SAFE("review-safe");

        companion object {
            fun fromString(rawValue: String): AppDistributionMode {
                val normalized = rawValue.trim().lowercase().replace("_", "-")
                return when (normalized) {
                    "review-safe", "reviewsafe", "safe", "appstore", "testflight" -> REVIEW_SAFE
                    else -> FULL
                }
            }
        }
    }
}

object AppCapabilities {
    var distributionMode: Config.AppDistributionMode = Config.AppDistributionMode.FULL
        private set

    val liveSportsEnabled: Boolean
        get() = distributionMode == Config.AppDistributionMode.FULL

    val highlightsEnabled: Boolean
        get() = distributionMode == Config.AppDistributionMode.FULL

    val intelligenceHubEnabled: Boolean
        get() = distributionMode == Config.AppDistributionMode.FULL
}

