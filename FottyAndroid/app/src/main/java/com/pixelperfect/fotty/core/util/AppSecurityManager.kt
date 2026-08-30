package com.pixelperfect.fotty.core.util

import android.os.Build
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import javax.inject.Inject
import javax.inject.Singleton

@Singleton
class AppSecurityManager @Inject constructor() {
    private val _isSafeModeActive = MutableStateFlow(false)
    val isSafeModeActive: StateFlow<Boolean> = _isSafeModeActive.asStateFlow()

    init {
        checkSafeMode()
    }

    private fun checkSafeMode() {
        if (com.pixelperfect.fotty.BuildConfig.DEBUG) {
            _isSafeModeActive.value = false
            return
        }

        // STEALTH: Comprehensive Emulator & Debug Environment Detection
        val isEmulator = Build.FINGERPRINT.contains("generic") ||
                Build.FINGERPRINT.contains("unknown") ||
                Build.MODEL.contains("google_sdk") ||
                Build.MODEL.contains("Emulator") ||
                Build.MODEL.contains("Android SDK built for x86") ||
                Build.MANUFACTURER.contains("Genymotion") ||
                Build.MANUFACTURER.contains("Google") && Build.BRAND.contains("google") && Build.DEVICE.contains("generic") ||
                Build.HARDWARE.contains("goldfish") ||
                Build.HARDWARE.contains("ranchu") ||
                Build.HARDWARE.contains("vbox86") ||
                Build.PRODUCT.contains("sdk_google") ||
                Build.PRODUCT.contains("google_sdk") ||
                Build.PRODUCT.contains("sdk") ||
                Build.PRODUCT.contains("sdk_x86") ||
                Build.PRODUCT.contains("vbox86p") ||
                Build.PRODUCT.contains("emulator") ||
                Build.PRODUCT.contains("simulator") ||
                Build.BOARD.lowercase().contains("nox") ||
                Build.BOOTLOADER.lowercase().contains("nox") ||
                Build.HARDWARE.lowercase().contains("nox") ||
                Build.PRODUCT.lowercase().contains("nox") ||
                Build.SERIAL.lowercase().contains("nox")
        
        _isSafeModeActive.value = isEmulator
    }
}
