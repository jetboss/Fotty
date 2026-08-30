package com.pixelperfect.fotty.core.ui

import androidx.compose.foundation.layout.*
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.unit.dp
import androidx.navigation.compose.currentBackStackEntryAsState
import androidx.navigation.compose.rememberNavController
import com.pixelperfect.fotty.core.navigation.NavGraph
import com.pixelperfect.fotty.core.navigation.Route
import com.pixelperfect.fotty.core.storage.AuthPreferenceStore

import com.pixelperfect.fotty.ui.components.KineticNavDock

import androidx.compose.material3.windowsizeclass.WindowWidthSizeClass
import androidx.compose.material3.windowsizeclass.ExperimentalMaterial3WindowSizeClassApi
import androidx.compose.material3.windowsizeclass.calculateWindowSizeClass
import android.app.Activity
import androidx.compose.ui.platform.LocalContext

@OptIn(ExperimentalMaterial3WindowSizeClassApi::class)
@Composable
fun MainScreen(
    authStore: AuthPreferenceStore,
    isPipMode: Boolean = false
) {
    val navController = rememberNavController()
    val navBackStackEntry by navController.currentBackStackEntryAsState()
    val currentRoute = navBackStackEntry?.destination?.route.orEmpty()
    
    val context = LocalContext.current
    val windowSizeClass = if (context is Activity) {
        calculateWindowSizeClass(context)
    } else {
        null
    }
    val useNavRail = windowSizeClass?.widthSizeClass != null && windowSizeClass.widthSizeClass != WindowWidthSizeClass.Compact

    val navigationItems = listOf(
        NavigationItem("Home", Route.Home.path, Icons.Default.Home),
        NavigationItem("Live", Route.Live.path, Icons.Default.LiveTv),
        NavigationItem("Arena", Route.Arena.path, Icons.Default.Forum),
        NavigationItem("Explore", Route.Explore.path, Icons.Default.Explore),
        NavigationItem("Settings", Route.Settings.path, Icons.Default.Settings)
    )

    val showNav = !isPipMode && currentRoute in navigationItems.map { it.route }

    Row(modifier = Modifier.fillMaxSize()) {
        if (showNav && useNavRail) {
            NavigationRail(
                containerColor = MaterialTheme.colorScheme.surface,
                header = {
                    Icon(
                        imageVector = Icons.Default.SportsFootball,
                        contentDescription = "Fotty",
                        modifier = Modifier.padding(vertical = 12.dp),
                        tint = MaterialTheme.colorScheme.primary
                    )
                }
            ) {
                Spacer(modifier = Modifier.weight(1f))
                navigationItems.forEach { item ->
                    val isSelected = currentRoute == item.route
                    NavigationRailItem(
                        selected = isSelected,
                        onClick = {
                            if (!isSelected) {
                                navController.navigate(item.route) {
                                    popUpTo(navController.graph.startDestinationId) { saveState = true }
                                    launchSingleTop = true
                                    restoreState = true
                                }
                            }
                        },
                        icon = { Icon(item.icon, contentDescription = item.label) },
                        label = { Text(item.label) }
                    )
                }
                Spacer(modifier = Modifier.weight(1f))
            }
        }

        Scaffold(
            modifier = Modifier.fillMaxWidth(),
            bottomBar = {
                if (showNav && !useNavRail) {
                    NavigationBar(
                        containerColor = MaterialTheme.colorScheme.surface
                    ) {
                        navigationItems.forEach { item ->
                            val isSelected = currentRoute == item.route
                            NavigationBarItem(
                                selected = isSelected,
                                onClick = {
                                    if (!isSelected) {
                                        navController.navigate(item.route) {
                                            popUpTo(navController.graph.startDestinationId) { saveState = true }
                                            launchSingleTop = true
                                            restoreState = true
                                        }
                                    }
                                },
                                icon = { Icon(item.icon, contentDescription = item.label) },
                                label = { Text(item.label) }
                            )
                        }
                    }
                }
            }
        ) { innerPadding ->
            Box(modifier = Modifier.fillMaxSize().padding(innerPadding)) {
                NavGraph(
                    navController = navController,
                    authStore = authStore,
                    isPipMode = isPipMode
                )
            }
        }
    }
}

private data class NavigationItem(
    val label: String,
    val route: String,
    val icon: ImageVector
)




