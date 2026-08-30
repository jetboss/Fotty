package com.pixelperfect.fotty.core.util

import android.content.Context
import android.content.pm.PackageManager
import android.os.Build
import android.os.VibrationEffect
import android.os.Vibrator
import android.os.VibratorManager
import android.util.Log
import androidx.core.content.ContextCompat
import com.pixelperfect.fotty.core.storage.UserPreferencesRepository
import dagger.hilt.android.qualifiers.ApplicationContext
import kotlinx.coroutines.flow.first
import javax.inject.Inject
import javax.inject.Singleton

@Singleton
class HapticManager @Inject constructor(
    @ApplicationContext private val context: Context,
    private val preferencesRepository: UserPreferencesRepository
) {
    private val tag = "HapticManager"

    private val vibrator: Vibrator? = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
        val vibratorManager = context.getSystemService(Context.VIBRATOR_MANAGER_SERVICE) as? VibratorManager
        vibratorManager?.defaultVibrator
    } else {
        @Suppress("DEPRECATION")
        context.getSystemService(Context.VIBRATOR_SERVICE) as? Vibrator
    }

    suspend fun vibrateLight() {
        if (!preferencesRepository.hapticsEnabled.first()) return
        if (!canVibrate()) return
        runCatching {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                vibrator?.vibrate(VibrationEffect.createOneShot(20, VibrationEffect.DEFAULT_AMPLITUDE))
            } else {
                @Suppress("DEPRECATION")
                vibrator?.vibrate(20)
            }
        }.onFailure { error ->
            Log.w(tag, "Light haptic ignored: ${error.message}")
        }
    }

    suspend fun vibrateImpact() {
        if (!preferencesRepository.hapticsEnabled.first()) return
        if (!canVibrate()) return
        runCatching {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                vibrator?.vibrate(VibrationEffect.createOneShot(50, VibrationEffect.DEFAULT_AMPLITUDE))
            } else {
                @Suppress("DEPRECATION")
                vibrator?.vibrate(50)
            }
        }.onFailure { error ->
            Log.w(tag, "Impact haptic ignored: ${error.message}")
        }
    }

    private fun canVibrate(): Boolean {
        val permissionGranted = ContextCompat.checkSelfPermission(
            context,
            android.Manifest.permission.VIBRATE
        ) == PackageManager.PERMISSION_GRANTED
        return permissionGranted && (vibrator?.hasVibrator() == true)
    }
}
