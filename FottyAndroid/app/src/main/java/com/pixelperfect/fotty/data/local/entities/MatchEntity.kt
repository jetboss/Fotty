package com.pixelperfect.fotty.data.local.entities

import androidx.room.Entity
import androidx.room.PrimaryKey
import com.pixelperfect.fotty.data.models.MatchStatus

@Entity(tableName = "matches")
data class MatchEntity(
    @PrimaryKey val id: String,
    val homeTeamName: String,
    val awayTeamName: String,
    val homeTeamLogo: String?,
    val awayTeamLogo: String?,
    val homeScore: Int?,
    val awayScore: Int?,
    val status: MatchStatus,
    val statusText: String?,
    val timestamp: Long,
    val leagueName: String,
    val category: String?,
    val minute: Int?
)
