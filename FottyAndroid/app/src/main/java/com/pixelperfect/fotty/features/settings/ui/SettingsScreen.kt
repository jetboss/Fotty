package com.pixelperfect.fotty.features.settings.ui

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.input.nestedscroll.nestedScroll
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel
import com.pixelperfect.fotty.features.settings.viewmodel.SettingsViewModel

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun SettingsScreen(
    viewModel: SettingsViewModel = hiltViewModel()
) {
    val scrollBehavior = TopAppBarDefaults.exitUntilCollapsedScrollBehavior()
    
    val themeMode by viewModel.themeMode.collectAsState()
    val dynamicColorEnabled by viewModel.dynamicColorEnabled.collectAsState()
    val chatNotifications by viewModel.chatNotifications.collectAsState()
    val enterToSend by viewModel.enterToSend.collectAsState()
    val defaultDataView by viewModel.defaultDataView.collectAsState()
    val dataRefreshRate by viewModel.dataRefreshRate.collectAsState()
    val customServerUrl by viewModel.customServerUrl.collectAsState()

    var showThemeDialog by remember { mutableStateOf(false) }
    var showDataViewDialog by remember { mutableStateOf(false) }
    var showRefreshRateDialog by remember { mutableStateOf(false) }
    var showServerDialog by remember { mutableStateOf(false) }
    var serverUrlInput by remember { mutableStateOf(customServerUrl) }

    Scaffold(
        modifier = Modifier.nestedScroll(scrollBehavior.nestedScrollConnection),
        topBar = {
            LargeTopAppBar(
                title = { Text("Settings") },
                scrollBehavior = scrollBehavior
            )
        }
    ) { padding ->
        LazyColumn(
            modifier = Modifier
                .fillMaxSize()
                .padding(padding)
        ) {
            item {
                PreferenceCategory("Appearance")
                ListPreference(
                    title = "App Theme",
                    summary = when(themeMode) {
                        "light" -> "Light"
                        "dark" -> "Dark"
                        else -> "System default"
                    },
                    icon = Icons.Default.Palette,
                    value = themeMode,
                    options = listOf(
                        "light" to "Light",
                        "dark" to "Dark",
                        "system" to "System default"
                    ),
                    onValueChange = { viewModel.setThemeMode(it) },
                    showDialog = showThemeDialog,
                    onShowDialogChange = { showThemeDialog = it }
                )
                SwitchPreference(
                    title = "Dynamic Color",
                    summary = "Use system wallpaper colors (Android 12+)",
                    icon = Icons.Default.ColorLens,
                    checked = dynamicColorEnabled,
                    onCheckedChange = { viewModel.setDynamicColorEnabled(it) }
                )
            }

            item {
                PreferenceCategory("Arena Chat")
                SwitchPreference(
                    title = "Chat Notifications",
                    summary = "Notify me of new messages in live match chats",
                    icon = Icons.Default.Notifications,
                    checked = chatNotifications,
                    onCheckedChange = { viewModel.setChatNotifications(it) }
                )
                SwitchPreference(
                    title = "Enter to Send",
                    summary = "Enter key will send the message",
                    icon = Icons.Default.Keyboard,
                    checked = enterToSend,
                    onCheckedChange = { viewModel.setEnterToSend(it) }
                )
            }

            item {
                PreferenceCategory("Justice Table Analytics")
                ListPreference(
                    title = "Default Data View",
                    summary = if (defaultDataView == "grid") "Grid Layout" else "List Layout",
                    icon = Icons.Default.TableChart,
                    value = defaultDataView,
                    options = listOf(
                        "grid" to "Grid Layout",
                        "list" to "List Layout"
                    ),
                    onValueChange = { viewModel.setDefaultDataView(it) },
                    showDialog = showDataViewDialog,
                    onShowDialogChange = { showDataViewDialog = it }
                )
                ListPreference(
                    title = "Data Refresh Rate",
                    summary = when(dataRefreshRate) {
                        "live" -> "Live (Real-time)"
                        "30s" -> "30 seconds"
                        else -> "Manual refresh only"
                    },
                    icon = Icons.Default.Refresh,
                    value = dataRefreshRate,
                    options = listOf(
                        "live" to "Live (Real-time)",
                        "30s" to "30 seconds",
                        "manual" to "Manual refresh only"
                    ),
                    onValueChange = { viewModel.setDataRefreshRate(it) },
                    showDialog = showRefreshRateDialog,
                    onShowDialogChange = { showRefreshRateDialog = it }
                )
            }

            item {
                PreferenceCategory("Network & Infrastructure")
                ActionPreference(
                    title = "Custom Server Endpoint",
                    summary = customServerUrl,
                    icon = Icons.Default.Dns,
                    onClick = { 
                        serverUrlInput = customServerUrl
                        showServerDialog = true 
                    }
                )
                ActionPreference(
                    title = "Clear App Cache",
                    summary = "Free up space by removing cached media assets",
                    icon = Icons.Default.DeleteSweep,
                    onClick = { viewModel.clearCache() }
                )
            }

            item {
                PreferenceCategory("About")
                ActionPreference(
                    title = "Version",
                    summary = "2.4.0-stable (Release Build)",
                    icon = Icons.Default.Info,
                    onClick = { }
                )
            }
            
            item { Spacer(modifier = Modifier.height(32.dp)) }
        }

        if (showServerDialog) {
            AlertDialog(
                onDismissRequest = { showServerDialog = false },
                title = { Text("Custom Server Endpoint") },
                text = {
                    Column {
                        Text(
                            "Specify a custom API or WebSocket URL for private server routing.",
                            style = MaterialTheme.typography.bodyMedium,
                            modifier = Modifier.padding(bottom = 16.dp)
                        )
                        OutlinedTextField(
                            value = serverUrlInput,
                            onValueChange = { serverUrlInput = it },
                            label = { Text("Server URL") },
                            placeholder = { Text("https://your-server.com") },
                            singleLine = true,
                            modifier = Modifier.fillMaxWidth()
                        )
                    }
                },
                confirmButton = {
                    Button(
                        onClick = {
                            viewModel.setCustomServerUrl(serverUrlInput)
                            showServerDialog = false
                        }
                    ) {
                        Text("Apply")
                    }
                },
                dismissButton = {
                    TextButton(onClick = { showServerDialog = false }) {
                        Text("Cancel")
                    }
                }
            )
        }
    }
}
