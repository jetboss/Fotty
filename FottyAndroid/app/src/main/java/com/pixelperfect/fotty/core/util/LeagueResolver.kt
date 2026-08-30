package com.pixelperfect.fotty.core.util

import com.pixelperfect.fotty.data.models.League

object LeagueResolver {
    
    const val PREMIER_LEAGUE = "Premier League"
    const val CHAMPIONS_LEAGUE = "Champions League"
    const val LA_LIGA = "La Liga"
    const val SERIE_A = "Serie A"
    const val BUNDESLIGA = "Bundesliga"
    const val LIGUE_1 = "Ligue 1"
    const val INTERNATIONAL = "International"

    /**
     * Standardizes raw league names from various APIs to match our UI tabs.
     */
    fun standardize(rawName: String?): String {
        val name = normalize(rawName)
        
        return when {
            name.contains("premier league") || name.contains("epl") -> {
                if (name.contains("u21") || name.contains("u23") || name.contains("women") || name.contains("division 2")) INTERNATIONAL
                else PREMIER_LEAGUE
            }
            name.contains("champions league") || name.contains("ucl") || name.contains("uefa") -> CHAMPIONS_LEAGUE
            name.contains("la liga") || name.contains("primera division") || name.contains("laliga") -> LA_LIGA
            name.contains("serie a") -> SERIE_A
            name.contains("bundesliga") -> BUNDESLIGA
            name.contains("ligue 1") -> LIGUE_1
            else -> INTERNATIONAL
        }
    }

    /**
     * Infers the league based on team names and match title (used for fuzzy sources like Nexus).
     */
    fun infer(title: String, home: String, away: String): String {
        val t = normalize(title)
        val h = normalize(home)
        val a = normalize(away)

        // 1. Check title keywords first (Highest Authority)
        val fromTitle = standardize(t)
        if (fromTitle != INTERNATIONAL) return fromTitle

        // 2. Cross-League Detection
        val isHomeEnglish = isEnglishElite(h)
        val isAwayEnglish = isEnglishElite(a)
        val isHomeSpanish = isSpanishElite(h)
        val isAwaySpanish = isSpanishElite(a)
        val isHomeItalian = isItalianElite(h)
        val isAwayItalian = isItalianElite(a)
        val isHomeGerman = isGermanElite(h)
        val isAwayGerman = isGermanElite(a)
        val isHomeFrench = isFrenchElite(h)
        val isAwayFrench = isFrenchElite(a)

        // If teams are from different elite domestic leagues, it's Champions League/International
        val isCrossLeague = (isHomeEnglish && (isAwaySpanish || isAwayItalian || isAwayGerman || isAwayFrench)) ||
                           (isAwayEnglish && (isHomeSpanish || isHomeItalian || isHomeGerman || isHomeFrench)) ||
                           (isHomeSpanish && (isAwayItalian || isAwayGerman || isAwayFrench)) ||
                           (isAwaySpanish && (isHomeItalian || isHomeGerman || isHomeFrench)) ||
                           (isHomeItalian && (isAwayGerman || isAwayFrench)) ||
                           (isAwayItalian && (isHomeGerman || isHomeFrench))

        if (isCrossLeague) return CHAMPIONS_LEAGUE

        // 3. Domestic elite check (both teams in same league)
        if (isHomeEnglish && isAwayEnglish) return PREMIER_LEAGUE
        if (isHomeSpanish && isAwaySpanish) return LA_LIGA
        if (isHomeItalian && isAwayItalian) return SERIE_A
        if (isHomeGerman && isAwayGerman) return BUNDESLIGA
        if (isHomeFrench && isAwayFrench) return LIGUE_1

        // 4. Single-team fallback
        if (isHomeEnglish || isAwayEnglish) return PREMIER_LEAGUE
        if (isHomeSpanish || isAwaySpanish) return LA_LIGA
        if (isHomeItalian || isAwayItalian) return SERIE_A
        if (isHomeGerman || isAwayGerman) return BUNDESLIGA
        if (isHomeFrench || isAwayFrench) return LIGUE_1

        return INTERNATIONAL
    }

    private fun normalize(s: String?): String {
        if (s == null) return ""
        return s.lowercase()
            .replace("á", "a").replace("é", "e").replace("í", "i").replace("ó", "o").replace("ú", "u")
            .replace("ü", "u").replace("ö", "o").replace("ä", "a").replace("ñ", "n")
            .trim()
    }

    private fun isEnglishElite(n: String) = n.contains("arsenal") || n.contains("liverpool") || n.contains("man city") || n.contains("manchester city") || n.contains("chelsea") || n.contains("spurs") || n.contains("tottenham") || n.contains("man united") || n.contains("manchester united") || n.contains("aston villa") || n.contains("newcastle") || n.contains("brighton") || n.contains("west ham") || n.contains("everton") || n.contains("wolves") || n.contains("wolverhampton")
    private fun isSpanishElite(n: String) = n.contains("real madrid") || n.contains("barcelona") || n.contains("atletico") || n.contains("atleti") || n.contains("sevilla") || n.contains("girona") || n.contains("sociedad") || n.contains("valencia") || n.contains("betis") || n.contains("villarreal") || n.contains("bilbao") || n.contains("athletic")
    private fun isItalianElite(n: String) = n.contains("inter") || n.contains("milan") || n.contains("juventus") || n.contains("napoli") || n.contains("roma") || n.contains("lazio") || n.contains("atalanta") || n.contains("fiorentina") || n.contains("bologna")
    private fun isGermanElite(n: String) = n.contains("bayern") || n.contains("dortmund") || n.contains("leverkusen") || n.contains("leipzig") || n.contains("frankfurt") || n.contains("stuttgart")
    private fun isFrenchElite(n: String) = n.contains("psg") || n.contains("paris") || n.contains("monaco") || n.contains("marseille") || n.contains("lyon") || n.contains("lille") || n.contains("nice") || n.contains("lens")
}
