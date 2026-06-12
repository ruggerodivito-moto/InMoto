package com.divito.inmoto

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.activity.viewModels
import androidx.compose.foundation.layout.padding
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Map
import androidx.compose.material.icons.filled.MoreHoriz
import androidx.compose.material3.Icon
import androidx.compose.material3.NavigationBar
import androidx.compose.material3.NavigationBarItem
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Modifier
import androidx.navigation.NavDestination.Companion.hierarchy
import androidx.navigation.NavGraph.Companion.findStartDestination
import androidx.navigation.compose.NavHost
import androidx.navigation.compose.composable
import androidx.navigation.compose.currentBackStackEntryAsState
import androidx.navigation.compose.rememberNavController
import com.divito.inmoto.ui.Routes
import com.divito.inmoto.ui.screens.ComposeTripScreen
import com.divito.inmoto.ui.screens.FavoritePlacesScreen
import com.divito.inmoto.ui.screens.GuideScreen
import com.divito.inmoto.ui.screens.HomeBrowseScreen
import com.divito.inmoto.ui.screens.MoreScreen
import com.divito.inmoto.ui.screens.NavigatorScreen
import com.divito.inmoto.ui.screens.RoadbookImportScreen
import com.divito.inmoto.ui.screens.RoadtripScreen
import com.divito.inmoto.ui.screens.RouteDetailScreen
import com.divito.inmoto.ui.screens.SettingsScreen
import com.divito.inmoto.ui.screens.StageDetailScreen
import com.divito.inmoto.ui.screens.TripPlanDetailScreen
import com.divito.inmoto.ui.theme.InMotoTheme

class MainActivity : ComponentActivity() {
    private val vm: AppViewModel by viewModels()

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()
        setContent {
            InMotoTheme {
                InMotoApp(vm)
            }
        }
    }
}

private data class Tab(val route: String, val label: String, val icon: @Composable () -> Unit)

@Composable
fun InMotoApp(vm: AppViewModel) {
    val navController = rememberNavController()
    val tabs = listOf(
        Tab(Routes.ROADTRIP, "Roadtrip") { Icon(Icons.Filled.Map, contentDescription = null) },
        Tab(Routes.MORE, "Altro") { Icon(Icons.Filled.MoreHoriz, contentDescription = null) },
    )

    val backStack by navController.currentBackStackEntryAsState()
    val currentRoute = backStack?.destination?.route
    val showBottomBar = currentRoute == Routes.ROADTRIP || currentRoute == Routes.MORE

    Scaffold(
        bottomBar = {
            if (showBottomBar) {
                NavigationBar {
                    tabs.forEach { tab ->
                        val selected = backStack?.destination?.hierarchy?.any { it.route == tab.route } == true
                        NavigationBarItem(
                            selected = selected,
                            onClick = {
                                navController.navigate(tab.route) {
                                    popUpTo(navController.graph.findStartDestination().id) { saveState = true }
                                    launchSingleTop = true
                                    restoreState = true
                                }
                            },
                            icon = tab.icon,
                            label = { Text(tab.label) },
                        )
                    }
                }
            }
        }
    ) { padding ->
        NavHost(
            navController = navController,
            startDestination = Routes.ROADTRIP,
            modifier = Modifier.padding(padding),
        ) {
            composable(Routes.ROADTRIP) { RoadtripScreen(vm, navController) }
            composable(Routes.MORE) { MoreScreen(vm, navController) }
            composable(Routes.HOME_BROWSE) { HomeBrowseScreen(vm, navController) }
            composable(Routes.FAVORITES) { FavoritePlacesScreen(vm, navController) }
            composable(Routes.SETTINGS) { SettingsScreen(vm, navController) }
            composable(Routes.GUIDE) { GuideScreen(navController) }
            composable(Routes.ROADBOOK_IMPORT) { RoadbookImportScreen(vm, navController) }
            composable(Routes.COMPOSE_TRIP) { ComposeTripScreen(vm, navController) }
            composable(Routes.ROUTE_DETAIL) { entry ->
                RouteDetailScreen(vm, navController, entry.arguments?.getString("id").orEmpty())
            }
            composable(Routes.TRIP_DETAIL) { entry ->
                TripPlanDetailScreen(vm, navController, entry.arguments?.getString("id").orEmpty())
            }
            composable(Routes.STAGE_DETAIL) { entry ->
                StageDetailScreen(
                    vm, navController,
                    entry.arguments?.getString("tripId").orEmpty(),
                    entry.arguments?.getString("itemId").orEmpty(),
                )
            }
            composable(Routes.NAVIGATOR) { entry ->
                NavigatorScreen(vm, navController, entry.arguments?.getString("routeId").orEmpty())
            }
        }
    }
}
