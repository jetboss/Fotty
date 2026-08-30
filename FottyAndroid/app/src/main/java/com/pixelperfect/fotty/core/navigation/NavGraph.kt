package com.pixelperfect.fotty.core.navigation

import androidx.compose.runtime.Composable
import androidx.navigation.NavHostController
import androidx.navigation.compose.NavHost
import androidx.navigation.compose.composable
import com.pixelperfect.fotty.features.splash.SplashScreen
import com.pixelperfect.fotty.features.onboarding.OnboardingScreen
import com.pixelperfect.fotty.core.ui.FeatureShell
import androidx.hilt.navigation.compose.hiltViewModel
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.foundation.layout.*
import androidx.compose.material3.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.dp
import androidx.compose.foundation.background

import com.pixelperfect.fotty.core.storage.AuthPreferenceStore
import com.pixelperfect.fotty.features.arena.ui.MatchDetailScreen
import com.pixelperfect.fotty.features.arena.ui.ArenaHubScreen
import com.pixelperfect.fotty.features.clips.ui.ClipsScreen
import com.pixelperfect.fotty.features.settings.ui.SettingsScreen

import androidx.compose.animation.*
import androidx.compose.animation.core.tween

@Composable
fun NavGraph(
    navController: NavHostController,
    authStore: AuthPreferenceStore,
    isPipMode: Boolean = false
) {
    NavHost(
        navController = navController,
        startDestination = Route.Home.path,
        enterTransition = { fadeIn(animationSpec = tween(300)) },
        exitTransition = { fadeOut(animationSpec = tween(300)) }
    ) {
        composable(
            route = Route.Home.path,
            enterTransition = { slideIntoContainer(AnimatedContentTransitionScope.SlideDirection.Left, animationSpec = tween(300)) },
            exitTransition = { slideOutOfContainer(AnimatedContentTransitionScope.SlideDirection.Left, animationSpec = tween(300)) },
            popEnterTransition = { slideIntoContainer(AnimatedContentTransitionScope.SlideDirection.Right, animationSpec = tween(300)) },
            popExitTransition = { slideOutOfContainer(AnimatedContentTransitionScope.SlideDirection.Right, animationSpec = tween(300)) }
        ) { 
            com.pixelperfect.fotty.features.home.ui.HomeScreen(
                onMatchClick = { match ->
                    val now = System.currentTimeMillis()
                    val isSoon = match.timestamp > 0 && (match.timestamp - now) < 60 * 60 * 1000
                    if (match.status == com.pixelperfect.fotty.data.models.MatchStatus.LIVE || isSoon) {
                        navController.navigate(Route.Player.create(match.id, match.homeTeam.name, match.awayTeam.name, match.category))
                    } else {
                        navController.navigate(Route.MatchDetail.create(match.id))
                    }
                },
                onNewsClick = { newsItem ->
                    navController.navigate(Route.NewsDetail.create(newsItem.url ?: "", newsItem.title))
                },
                onExploreClick = { navController.navigate(Route.Explore.path) }
            )
        }

        composable(
            route = Route.Live.path,
            enterTransition = { fadeIn(tween(300)) },
            exitTransition = { fadeOut(tween(300)) }
        ) { 
            com.pixelperfect.fotty.features.live.ui.LiveMatchesScreen(
                onMatchClick = { match ->
                    navController.navigate(Route.Player.create(match.id, match.homeTeam.name, match.awayTeam.name, match.category))
                }
            )
        }

        composable(Route.Arena.path) { 
            val insightsViewModel: com.pixelperfect.fotty.features.arena.viewmodel.InsightsViewModel = hiltViewModel()
            com.pixelperfect.fotty.features.arena.ui.ArenaHubScreen(
                viewModel = insightsViewModel,
                onWatch = { fixture ->
                    navController.navigate(Route.Player.create(
                        fixtureId = fixture.fixture.id.toString(),
                        home = fixture.teams.home.name,
                        away = fixture.teams.away.name,
                        category = "football"
                    ))
                }
            )
        }

        composable(Route.Clips.path) { 
            com.pixelperfect.fotty.features.clips.ui.ClipsScreen()
        }

        composable(Route.JusticeTable.path) { 
            com.pixelperfect.fotty.features.analytics.ui.JusticeTableScreen(
                state = com.pixelperfect.fotty.features.analytics.ui.JusticeUiState.Success(
                    rows = listOf(
                        com.pixelperfect.fotty.features.analytics.ui.AnalyticsRow("Expected Goals (xG)", "2.45", "+0.12"),
                        com.pixelperfect.fotty.features.analytics.ui.AnalyticsRow("Expected Assists (xA)", "1.89", "-0.05"),
                        com.pixelperfect.fotty.features.analytics.ui.AnalyticsRow("Deep Completions", "14", "+2"),
                        com.pixelperfect.fotty.features.analytics.ui.AnalyticsRow("Justice Score", "88%", "+5%"),
                        com.pixelperfect.fotty.features.analytics.ui.AnalyticsRow("Luck Variance", "-1.2", "-0.4")
                    )
                ),
                onBackClick = { navController.popBackStack() }
            )
        }

        composable(Route.Explore.path) { 
            com.pixelperfect.fotty.features.explore.ui.ExploreScreen()
        }

        composable(Route.Settings.path) { 
            com.pixelperfect.fotty.features.settings.ui.SettingsScreen()
        }
        
        composable(
            route = Route.MatchDetail.path,
            enterTransition = { scaleIn(initialScale = 0.9f) + fadeIn() },
            exitTransition = { scaleOut(targetScale = 0.9f) + fadeOut() }
        ) { backStackEntry ->
            val fixtureId = backStackEntry.arguments?.getString("fixtureId") ?: ""
            MatchDetailScreen(
                fixtureId = fixtureId,
                onBack = { navController.popBackStack() },
                authStore = authStore
            )
        }

        composable(
            route = Route.Player.path,
            enterTransition = { slideIntoContainer(AnimatedContentTransitionScope.SlideDirection.Up, animationSpec = tween(400)) },
            exitTransition = { slideOutOfContainer(AnimatedContentTransitionScope.SlideDirection.Down, animationSpec = tween(400)) }
        ) { backStackEntry ->
            val fixtureId = backStackEntry.arguments?.getString("fixtureId") ?: ""
            val home = backStackEntry.arguments?.getString("home") ?: ""
            val away = backStackEntry.arguments?.getString("away") ?: ""
            val category = backStackEntry.arguments?.getString("category") ?: "football"
            
            val playerViewModel: com.pixelperfect.fotty.features.player.viewmodel.PlayerViewModel = hiltViewModel()
            
            LaunchedEffect(fixtureId) {
                playerViewModel.resolveLiveStream(matchId = fixtureId, homeTeam = home, awayTeam = away)
            }
            
            com.pixelperfect.fotty.features.player.ui.VideoPlayerScreen(
                playerState = playerViewModel.playerState,
                intelligenceState = playerViewModel.intelligenceState,
                streamSource = playerViewModel.selectedSource,
                sources = playerViewModel.sources,
                currentSourceIndex = playerViewModel.selectedSourceIndex,
                homeTeam = home,
                awayTeam = away,
                category = category,
                diagnostics = playerViewModel.diagnostics,
                onSelectSource = { playerViewModel.selectSource(it) },
                onRequestNextSource = { playerViewModel.tryNextSource(it) },
                onToggleIntelligence = { playerViewModel.toggleIntelligence() },
                onBack = { navController.popBackStack() },
                globalP2PSources = playerViewModel.globalP2PSources,
                isFetchingGlobalP2P = playerViewModel.isFetchingGlobalP2P,
                onSelectGlobalSource = { playerViewModel.selectGlobalSource(it) },
                isPipMode = isPipMode
            )
        }

        composable(
            route = Route.NewsDetail.path,
            enterTransition = { slideIntoContainer(AnimatedContentTransitionScope.SlideDirection.Up, animationSpec = tween(400)) },
            exitTransition = { slideOutOfContainer(AnimatedContentTransitionScope.SlideDirection.Down, animationSpec = tween(400)) }
        ) { backStackEntry ->
            val url = java.net.URLDecoder.decode(backStackEntry.arguments?.getString("url") ?: "", "UTF-8")
            val title = java.net.URLDecoder.decode(backStackEntry.arguments?.getString("title") ?: "", "UTF-8")
            
            com.pixelperfect.fotty.features.home.ui.NewsDetailScreen(
                url = url,
                title = title,
                onBack = { navController.popBackStack() }
            )
        }
    }
}

