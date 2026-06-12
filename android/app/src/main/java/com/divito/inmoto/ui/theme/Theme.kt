package com.divito.inmoto.ui.theme

import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.Color

private val Blu = Color(0xFF1C3A5E)
private val BluChiaro = Color(0xFF3E6BA8)
private val Giallo = Color(0xFFFFD24A)

private val LightColors = lightColorScheme(
    primary = Blu,
    onPrimary = Color.White,
    secondary = BluChiaro,
    tertiary = Giallo,
)

private val DarkColors = darkColorScheme(
    primary = BluChiaro,
    onPrimary = Color.White,
    secondary = Blu,
    tertiary = Giallo,
)

@Composable
fun InMotoTheme(
    darkTheme: Boolean = isSystemInDarkTheme(),
    content: @Composable () -> Unit
) {
    MaterialTheme(
        colorScheme = if (darkTheme) DarkColors else LightColors,
        typography = Typography,
        content = content
    )
}
