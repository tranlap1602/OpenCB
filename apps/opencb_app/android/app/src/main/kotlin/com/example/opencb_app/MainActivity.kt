package com.example.opencb_app

import android.content.ActivityNotFoundException
import android.content.Context
import android.content.res.Configuration
import android.graphics.drawable.ColorDrawable
import android.graphics.Color
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.PowerManager
import android.provider.Settings
import android.view.View
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        configureEdgeToEdgeSystemBars()
    }

    override fun onPostResume() {
        super.onPostResume()
        configureEdgeToEdgeSystemBars()
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "opencb/platform")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "getDeviceName" -> {
                        result.success(resolveDeviceName())
                    }
                    "setSystemBars" -> {
                        val navigationBarColor = call.argument<Number>("navigationBarColor")?.toInt()
                        val lightSystemBars = call.argument<Boolean>("lightSystemBars") ?: !isNightMode()
                        if (navigationBarColor != null) {
                            configureEdgeToEdgeSystemBars(
                                navigationBarColor = navigationBarColor,
                                lightSystemBars = lightSystemBars,
                            )
                        } else {
                            configureEdgeToEdgeSystemBars(lightSystemBars = lightSystemBars)
                        }
                        result.success(true)
                    }
                    "requestIgnoreBatteryOptimizations" -> {
                        result.success(requestIgnoreBatteryOptimizations())
                    }
                    "isIgnoringBatteryOptimizations" -> {
                        result.success(isIgnoringBatteryOptimizations())
                    }
                    "openUrl" -> {
                        val url = call.argument<String>("url")
                        if (url.isNullOrBlank()) {
                            result.success(false)
                            return@setMethodCallHandler
                        }

                        try {
                            val intent = Intent(Intent.ACTION_VIEW, Uri.parse(url))
                            startActivity(intent)
                            result.success(true)
                        } catch (_: ActivityNotFoundException) {
                            result.success(false)
                        } catch (_: Exception) {
                            result.success(false)
                        }
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun configureEdgeToEdgeSystemBars(
        navigationBarColor: Int = defaultNavigationBarColor(),
        lightSystemBars: Boolean = !isNightMode(),
    ) {
        window.statusBarColor = Color.TRANSPARENT
        window.navigationBarColor = navigationBarColor
        window.setBackgroundDrawable(ColorDrawable(navigationBarColor))
        window.decorView.setBackgroundColor(navigationBarColor)

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            window.isStatusBarContrastEnforced = false
            window.isNavigationBarContrastEnforced = false
        }

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            window.setDecorFitsSystemWindows(true)
            val lightAppearance =
                android.view.WindowInsetsController.APPEARANCE_LIGHT_STATUS_BARS or
                    android.view.WindowInsetsController.APPEARANCE_LIGHT_NAVIGATION_BARS
            window.insetsController?.setSystemBarsAppearance(
                if (lightSystemBars) lightAppearance else 0,
                lightAppearance,
            )
            return
        }

        var flags = View.SYSTEM_UI_FLAG_LAYOUT_STABLE
        if (lightSystemBars && Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            flags = flags or View.SYSTEM_UI_FLAG_LIGHT_STATUS_BAR
        }
        if (lightSystemBars && Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            flags = flags or View.SYSTEM_UI_FLAG_LIGHT_NAVIGATION_BAR
        }
        window.decorView.systemUiVisibility = flags
    }

    private fun defaultNavigationBarColor(): Int {
        return Color.rgb(251, 254, 252)
    }

    private fun isNightMode(): Boolean {
        return resources.configuration.uiMode and Configuration.UI_MODE_NIGHT_MASK ==
            Configuration.UI_MODE_NIGHT_YES
    }

    private fun resolveDeviceName(): String {
        val configuredName = Settings.Global
            .getString(contentResolver, "device_name")
            ?.trim()
        if (!configuredName.isNullOrBlank()) {
            return configuredName
        }

        val manufacturer = Build.MANUFACTURER.trim()
        val model = Build.MODEL.trim()
        if (model.isBlank()) return "Android"
        if (manufacturer.isBlank() || model.startsWith(manufacturer, ignoreCase = true)) {
            return model
        }
        return "$manufacturer $model"
    }

    private fun isIgnoringBatteryOptimizations(): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) return true
        val powerManager = getSystemService(Context.POWER_SERVICE) as PowerManager
        return powerManager.isIgnoringBatteryOptimizations(packageName)
    }

    private fun requestIgnoreBatteryOptimizations(): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) return true
        if (isIgnoringBatteryOptimizations()) return true

        return try {
            val intent = Intent(Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS).apply {
                data = Uri.parse("package:$packageName")
            }
            startActivity(intent)
            true
        } catch (_: Exception) {
            try {
                startActivity(Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS))
                true
            } catch (_: Exception) {
                false
            }
        }
    }
}
