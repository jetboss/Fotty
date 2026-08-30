package com.pixelperfect.fotty.data.local

import androidx.room.Database
import androidx.room.RoomDatabase
import androidx.room.TypeConverters
import com.pixelperfect.fotty.data.local.dao.MatchDao
import com.pixelperfect.fotty.data.local.entities.MatchEntity

@Database(entities = [MatchEntity::class], version = 1, exportSchema = false)
abstract class FottyDatabase : RoomDatabase() {
    abstract fun matchDao(): MatchDao
}
