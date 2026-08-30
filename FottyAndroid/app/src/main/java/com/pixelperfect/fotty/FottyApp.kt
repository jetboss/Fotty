package com.pixelperfect.fotty

import android.app.Application
import dagger.hilt.android.HiltAndroidApp

import coil.ImageLoader
import coil.ImageLoaderFactory
import okhttp3.OkHttpClient
import javax.inject.Inject

@HiltAndroidApp
class FottyApp : Application(), ImageLoaderFactory {
    @Inject lateinit var okHttpClient: OkHttpClient

    override fun newImageLoader(): ImageLoader {
        return ImageLoader.Builder(this)
            .okHttpClient(okHttpClient)
            .respectCacheHeaders(false)
            .build()
    }
}
