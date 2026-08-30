package com.pixelperfect.fotty.core.util

import java.text.SimpleDateFormat
import java.util.*

object DateUtils {
    private fun getTimeFormatter(): SimpleDateFormat {
        return SimpleDateFormat("h:mm a", Locale.getDefault()).apply {
            timeZone = TimeZone.getDefault()
        }
    }

    private fun getDateFormatter(): SimpleDateFormat {
        return SimpleDateFormat("EEE, d MMM", Locale.getDefault()).apply {
            timeZone = TimeZone.getDefault()
        }
    }

    fun formatTime(timestamp: Long): String {
        // Match timestamps are already in milliseconds from MatchMapper
        return getTimeFormatter().format(Date(timestamp))
    }

    fun formatDate(timestamp: Long): String {
        return getDateFormatter().format(Date(timestamp))
    }

    fun formatIsoTime(isoDate: String?): String {
        if (isoDate == null) return "--:--"
        return try {
            val date = java.time.OffsetDateTime.parse(isoDate, java.time.format.DateTimeFormatter.ISO_OFFSET_DATE_TIME)
            getTimeFormatter().format(Date(date.toInstant().toEpochMilli()))
        } catch (e: Exception) {
            "--:--"
        }
    }
}
