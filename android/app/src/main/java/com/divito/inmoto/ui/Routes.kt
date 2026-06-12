package com.divito.inmoto.ui

/** Rotte di navigazione. Quelle con argomenti usano i placeholder Navigation Compose. */
object Routes {
    const val ROADTRIP = "roadtrip"
    const val MORE = "more"
    const val HOME_BROWSE = "home_browse"
    const val FAVORITES = "favorites"
    const val SETTINGS = "settings"
    const val GUIDE = "guide"
    const val ROADBOOK_IMPORT = "roadbook_import"
    const val COMPOSE_TRIP = "compose_trip"

    const val ROUTE_DETAIL = "route_detail/{id}"
    fun routeDetail(id: String) = "route_detail/$id"

    const val TRIP_DETAIL = "trip_detail/{id}"
    fun tripDetail(id: String) = "trip_detail/$id"

    const val STAGE_DETAIL = "stage_detail/{tripId}/{itemId}"
    fun stageDetail(tripId: String, itemId: String) = "stage_detail/$tripId/$itemId"

    const val NAVIGATOR = "navigator/{routeId}"
    fun navigator(routeId: String) = "navigator/$routeId"
}
