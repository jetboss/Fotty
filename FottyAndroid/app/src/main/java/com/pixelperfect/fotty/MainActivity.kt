package com.pixelperfect.fotty

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.core.view.WindowCompat
import com.pixelperfect.fotty.core.theme.FottyTheme
import com.pixelperfect.fotty.core.ui.MainScreen
import com.pixelperfect.fotty.core.storage.AuthPreferenceStore
import dagger.hilt.android.AndroidEntryPoint
import javax.inject.Inject

import androidx.compose.runtime.mutableStateOf

@AndroidEntryPoint
class MainActivity : ComponentActivity() {
    private var isPipMode = mutableStateOf(false)
    @Inject lateinit var authStore: AuthPreferenceStore

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        WindowCompat.setDecorFitsSystemWindows(window, false)
        
        setContent {
            FottyTheme {
                MainScreen(
                    authStore = authStore,
                    isPipMode = isPipMode.value
                )
            }
        }
    }

    override fun onPictureInPictureModeChanged(isInPictureInPictureMode: Boolean, newConfig: android.content.res.Configuration) {
        super.onPictureInPictureModeChanged(isInPictureInPictureMode, newConfig)
        isPipMode.value = isInPictureInPictureMode
    }

    override fun onUserLeaveHint() {
        // Trigger PiP if something is playing (handled via a broadcast or shared state in real apps)
        // For now, we allow the player to request PiP when leaving.
        super.onUserLeaveHint()
    }
}
