package com.pixelperfect.fotty.features.settings.viewmodel

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.pixelperfect.fotty.core.network.models.pocketbase.PBProfileRecord
import com.pixelperfect.fotty.core.network.repository.pocketbase.SocialRepository
import com.pixelperfect.fotty.core.storage.AuthPreferenceStore
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.launch
import javax.inject.Inject

@HiltViewModel
class ProfileViewModel @Inject constructor(
    private val socialRepository: SocialRepository,
    private val authPreferenceStore: AuthPreferenceStore
) : ViewModel() {

    var profile by mutableStateOf<PBProfileRecord?>(null)
        private set
    var isLoading by mutableStateOf(false)
        private set
    var error by mutableStateOf<String?>(null)
        private set
    var isSaving by mutableStateOf(false)
        private set

    init {
        loadProfile()
    }

    fun loadProfile() {
        val authState = authPreferenceStore.load()
        val userId = authState.userId ?: return
        val token = authState.token ?: return
        
        viewModelScope.launch {
            isLoading = true
            error = null
            try {
                profile = socialRepository.fetchUserProfile(userId, token)
                isLoading = false
            } catch (e: Exception) {
                error = e.localizedMessage
                isLoading = false
            }
        }
    }

    fun updateProfile(displayName: String, avatarSymbol: String?, onSuccess: () -> Unit) {
        val authState = authPreferenceStore.load()
        val userId = authState.userId ?: return
        val token = authState.token ?: return

        viewModelScope.launch {
            isSaving = true
            error = null
            try {
                profile = socialRepository.updateUserProfile(
                    userId,
                    displayName,
                    avatarSymbol,
                    token
                )
                isSaving = false
                onSuccess()
            } catch (e: Exception) {
                error = e.localizedMessage
                isSaving = false
            }
        }
    }
}
