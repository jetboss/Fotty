package com.pixelperfect.fotty.features.settings.viewmodel

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.pixelperfect.fotty.core.storage.UserPreferencesRepository
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import javax.inject.Inject

@HiltViewModel
class SettingsViewModel @Inject constructor(
    private val userPreferencesRepository: UserPreferencesRepository
) : ViewModel() {

    // Mock/Internal states for the new preferences (DataStore integration can follow)
    private val _themeMode = MutableStateFlow("system")
    val themeMode: StateFlow<String> = _themeMode.asStateFlow()

    private val _dynamicColorEnabled = MutableStateFlow(true)
    val dynamicColorEnabled: StateFlow<Boolean> = _dynamicColorEnabled.asStateFlow()

    private val _chatNotifications = MutableStateFlow(true)
    val chatNotifications: StateFlow<Boolean> = _chatNotifications.asStateFlow()

    private val _enterToSend = MutableStateFlow(false)
    val enterToSend: StateFlow<Boolean> = _enterToSend.asStateFlow()

    private val _defaultDataView = MutableStateFlow("grid")
    val defaultDataView: StateFlow<String> = _defaultDataView.asStateFlow()

    private val _dataRefreshRate = MutableStateFlow("30s")
    val dataRefreshRate: StateFlow<String> = _dataRefreshRate.asStateFlow()

    private val _customServerUrl = MutableStateFlow("https://api.streamed.pk")
    val customServerUrl: StateFlow<String> = _customServerUrl.asStateFlow()

    // Legacy support for other modules
    val hapticsEnabled = MutableStateFlow(true)
    val streamQuality = MutableStateFlow("auto")

    fun setThemeMode(mode: String) {
        _themeMode.value = mode
    }

    fun setDynamicColorEnabled(enabled: Boolean) {
        _dynamicColorEnabled.value = enabled
    }

    fun setChatNotifications(enabled: Boolean) {
        _chatNotifications.value = enabled
    }

    fun setEnterToSend(enabled: Boolean) {
        _enterToSend.value = enabled
    }

    fun setDefaultDataView(view: String) {
        _defaultDataView.value = view
    }

    fun setDataRefreshRate(rate: String) {
        _dataRefreshRate.value = rate
    }

    fun setCustomServerUrl(url: String) {
        _customServerUrl.value = url
    }
    
    fun clearCache() {
        // Implementation for clearing cache
    }
}
