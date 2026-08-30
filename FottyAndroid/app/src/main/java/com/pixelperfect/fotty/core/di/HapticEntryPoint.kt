package com.pixelperfect.fotty.core.di

import com.pixelperfect.fotty.core.util.HapticManager
import dagger.hilt.EntryPoint
import dagger.hilt.InstallIn
import dagger.hilt.components.SingletonComponent

@EntryPoint
@InstallIn(SingletonComponent::class)
interface HapticEntryPoint {
    fun hapticManager(): HapticManager
}
