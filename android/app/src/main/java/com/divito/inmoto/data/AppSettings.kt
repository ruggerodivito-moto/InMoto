package com.divito.inmoto.data

import android.content.Context

/** Config server AMT Scanner (URL + API key), equivalente di AppSettings iOS. */
class AppSettings(context: Context) {
    private val prefs = context.getSharedPreferences("inmoto_settings", Context.MODE_PRIVATE)

    var serverURL: String
        get() = prefs.getString(KEY_URL, "") ?: ""
        set(v) = prefs.edit().putString(KEY_URL, v.trim().trimEnd('/')).apply()

    var apiKey: String
        get() = prefs.getString(KEY_KEY, "") ?: ""
        set(v) = prefs.edit().putString(KEY_KEY, v.trim()).apply()

    val isConfigured: Boolean get() = serverURL.isNotEmpty() && apiKey.isNotEmpty()

    fun apiURL(path: String): String = serverURL + path

    companion object {
        private const val KEY_URL = "server_url"
        private const val KEY_KEY = "api_key"
    }
}
