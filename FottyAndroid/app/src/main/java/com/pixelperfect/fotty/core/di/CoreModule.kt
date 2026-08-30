package com.pixelperfect.fotty.core.di

import android.content.Context
import com.pixelperfect.fotty.core.LicenseManager
import dagger.Module
import dagger.Provides
import dagger.hilt.InstallIn
import dagger.hilt.android.qualifiers.ApplicationContext
import dagger.hilt.components.SingletonComponent
import javax.inject.Singleton

@Module
@InstallIn(SingletonComponent::class)
object CoreModule {

    @Provides
    @Singleton
    fun provideLicenseManager(@ApplicationContext context: Context): LicenseManager {
        return LicenseManager(context)
    }
}
