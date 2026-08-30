package com.pixelperfect.fotty.features.player.viewmodel

import com.pixelperfect.fotty.core.extractors.LiveSportsExtractor
import java.text.Normalizer
import java.util.Locale

object MatchMatcher {

    data class MatchLookupResult(
        val match: LiveSportsExtractor.StreamexMatch?,
        val mappedByRequestedId: Boolean
    )

    fun mapBestMatch(
        matches: List<LiveSportsExtractor.StreamexMatch>,
        matchId: String,
        homeTeam: String,
        awayTeam: String
    ): MatchLookupResult {
        if (matches.isEmpty()) {
            return MatchLookupResult(match = null, mappedByRequestedId = false)
        }

        val exactMatch = matches.find { it.stableId == matchId }
        val fuzzyIdMatch = if (exactMatch == null) {
            findByFuzzyStableId(matches, matchId)
        } else {
            null
        }
        val mappedByRequestedId = exactMatch != null || fuzzyIdMatch != null
        val sourceBackedMatches = matches.filter { !it.sources.isNullOrEmpty() }

        val mapped = when {
            exactMatch != null && !exactMatch.sources.isNullOrEmpty() -> exactMatch
            exactMatch != null -> {
                LiveSportsExtractor.findBestTeamMatch(
                    matches = sourceBackedMatches.ifEmpty { matches },
                    homeTeam = exactMatch.homeName.ifBlank { homeTeam },
                    awayTeam = exactMatch.awayName.ifBlank { awayTeam }
                ) ?: exactMatch
            }
            fuzzyIdMatch != null && !fuzzyIdMatch.sources.isNullOrEmpty() -> fuzzyIdMatch
            fuzzyIdMatch != null -> {
                LiveSportsExtractor.findBestTeamMatch(
                    matches = sourceBackedMatches.ifEmpty { matches },
                    homeTeam = fuzzyIdMatch.homeName.ifBlank { homeTeam },
                    awayTeam = fuzzyIdMatch.awayName.ifBlank { awayTeam },
                    minScore = 1
                ) ?: fuzzyIdMatch
            }
            else -> {
                LiveSportsExtractor.findBestTeamMatch(
                    matches = sourceBackedMatches.ifEmpty { matches },
                    homeTeam = homeTeam,
                    awayTeam = awayTeam,
                    minScore = 6
                ) ?: LiveSportsExtractor.findBestTeamMatch(
                    matches = sourceBackedMatches.ifEmpty { matches },
                    homeTeam = homeTeam,
                    awayTeam = awayTeam,
                    minScore = 1
                )
            }
        }

        return MatchLookupResult(match = mapped, mappedByRequestedId = mappedByRequestedId)
    }

    private fun findByFuzzyStableId(
        matches: List<LiveSportsExtractor.StreamexMatch>,
        requestedId: String
    ): LiveSportsExtractor.StreamexMatch? {
        if (requestedId.isBlank()) return null
        val requested = normalizeStableId(requestedId)
        if (requested.isBlank()) return null

        return matches.firstOrNull { normalizeStableId(it.stableId) == requested }
            ?: matches.firstOrNull { normalizeStableId(it.stableId).contains(requested) || requested.contains(normalizeStableId(it.stableId)) }
    }

    private fun normalizeStableId(value: String): String {
        return Normalizer.normalize(value, Normalizer.Form.NFD)
            .replace("\\p{M}+".toRegex(), "")
            .lowercase(Locale.US)
            .replace("[^a-z0-9]+".toRegex(), "")
            .trim()
    }

    fun dedupeMatchesByStableId(
        input: List<LiveSportsExtractor.StreamexMatch>
    ): List<LiveSportsExtractor.StreamexMatch> {
        val deduped = LinkedHashMap<String, LiveSportsExtractor.StreamexMatch>()
        input.forEach { match ->
            val key = match.stableId
            if (!deduped.containsKey(key)) {
                deduped[key] = match
            }
        }
        return deduped.values.toList()
    }

    fun buildHintedMatch(
        matchId: String,
        homeTeam: String,
        awayTeam: String,
        sourceHints: List<LiveSportsExtractor.StreamexSource>,
        baseMatch: LiveSportsExtractor.StreamexMatch?,
        includeBaseSources: Boolean
    ): LiveSportsExtractor.StreamexMatch? {
        if (sourceHints.isEmpty()) return null

        val cleanedHints = sourceHints.mapNotNull { source ->
            val code = source.source.trim()
            val id = source.id.trim()
            if (code.isBlank() || id.isBlank()) null else LiveSportsExtractor.StreamexSource(code, id)
        }
        if (cleanedHints.isEmpty()) return null

        val fallbackTitle = buildList {
            if (homeTeam.isNotBlank()) add(homeTeam.trim())
            if (awayTeam.isNotBlank()) add(awayTeam.trim())
        }.joinToString(" vs ").ifBlank { matchId }

        val seededMatch = baseMatch ?: LiveSportsExtractor.StreamexMatch(
            id = matchId,
            title = fallbackTitle,
            teams = LiveSportsExtractor.StreamexTeams(
                home = homeTeam.trim().takeIf { it.isNotBlank() }?.let {
                    LiveSportsExtractor.StreamexTeam(name = it)
                },
                away = awayTeam.trim().takeIf { it.isNotBlank() }?.let {
                    LiveSportsExtractor.StreamexTeam(name = it)
                }
            )
        )

        val baseSources = if (includeBaseSources) seededMatch.sources.orEmpty() else emptyList()
        val mergedSources = (cleanedHints + baseSources).distinctBy { source ->
            "${source.source.lowercase(Locale.US)}|${source.id.lowercase(Locale.US)}"
        }

        if (mergedSources.isEmpty()) return null

        return seededMatch.copy(
            id = seededMatch.id?.takeIf { it.isNotBlank() } ?: matchId,
            sources = mergedSources
        )
    }

    fun buildTeamFallbackMatch(
        matchId: String,
        homeTeam: String,
        awayTeam: String
    ): LiveSportsExtractor.StreamexMatch {
        val fallbackTitle = buildList {
            if (homeTeam.isNotBlank()) add(homeTeam.trim())
            if (awayTeam.isNotBlank()) add(awayTeam.trim())
        }.joinToString(" vs ").ifBlank { matchId }

        return LiveSportsExtractor.StreamexMatch(
            id = matchId,
            title = fallbackTitle,
            teams = LiveSportsExtractor.StreamexTeams(
                home = homeTeam.trim().takeIf { it.isNotBlank() }?.let {
                    LiveSportsExtractor.StreamexTeam(name = it)
                },
                away = awayTeam.trim().takeIf { it.isNotBlank() }?.let {
                    LiveSportsExtractor.StreamexTeam(name = it)
                }
            )
        )
    }
}
