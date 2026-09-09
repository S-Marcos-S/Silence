package me.lucky.silence

import android.content.SharedPreferences
import android.os.Build
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.dynamicDarkColorScheme
import androidx.compose.material3.dynamicLightColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.graphics.Color
import androidx.navigation.compose.rememberNavController
import me.lucky.silence.ui.App

open class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        
        // Run migration to fix any incorrect defaults
        val prefs = Preferences(this)
        prefs.runMigrationIfNeeded()
        
        NotificationManager(this).createNotificationChannels()
        setContent {
            var isAmoled by remember { mutableStateOf(prefs.isAmoledTheme) }
            DisposableEffect(prefs) {
                val listener = SharedPreferences.OnSharedPreferenceChangeListener { _, key ->
                    if (key == Preferences.THEME_AMOLED) {
                        isAmoled = prefs.isAmoledTheme
                    }
                }
                prefs.prefs.registerOnSharedPreferenceChangeListener(listener)
                onDispose {
                    prefs.prefs.unregisterOnSharedPreferenceChangeListener(listener)
                }
            }

            val isSystemDark = isSystemInDarkTheme()
            val isAndroid12OrLater = Build.VERSION.SDK_INT >= Build.VERSION_CODES.S
            val baseColorScheme = when {
                isAndroid12OrLater && isSystemDark -> dynamicDarkColorScheme(this)
                isAndroid12OrLater -> dynamicLightColorScheme(this)
                isSystemDark -> darkColorScheme()
                else -> lightColorScheme()
            }
            val colorScheme = if (isSystemDark && isAmoled) {
                baseColorScheme.copy(
                    background = Color.Black,
                    surface = Color.Black,
                    surfaceDim = Color.Black,
                    surfaceBright = Color(0xFF1E1E1E),
                    surfaceContainerLowest = Color.Black,
                    surfaceContainerLow = Color(0xFF0C0C0C),
                    surfaceContainer = Color(0xFF121212),
                    surfaceContainerHigh = Color(0xFF181818),
                    surfaceContainerHighest = Color(0xFF1F1F1F),
                )
            } else {
                baseColorScheme
            }
            MaterialTheme(colorScheme = colorScheme) {
                App(ctx = this, navController = rememberNavController())
            }
        }
    }
}
