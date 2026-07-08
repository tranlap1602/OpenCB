package com.example.opencb_app

import android.Manifest
import android.content.ActivityNotFoundException
import android.content.BroadcastReceiver
import android.content.ClipData
import android.content.ClipboardManager
import android.content.ContentValues
import android.content.Context
import android.content.res.Configuration
import android.graphics.drawable.ColorDrawable
import android.graphics.Color
import android.graphics.Bitmap
import android.graphics.Canvas
import android.content.Intent
import android.app.Activity
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.net.Uri
import android.net.wifi.WifiManager
import android.os.Build
import android.os.Bundle
import android.os.Environment
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.os.PowerManager
import android.provider.OpenableColumns
import android.provider.MediaStore
import android.provider.Settings
import android.util.Log
import android.view.View
import android.widget.RemoteViews
import android.widget.Toast
import io.flutter.app.FlutterApplication
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.FlutterEngineCache
import io.flutter.embedding.engine.dart.DartExecutor
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugins.GeneratedPluginRegistrant
import java.io.File
import java.io.FileOutputStream
import java.io.InputStream
import java.io.OutputStream
import java.util.UUID

private const val openCbLogTag = "OpenCB"

object OpenCbNotificationBridge {
    var platformChannel: MethodChannel? = null
    var clipboardSendPromptEnabled = false
    private val mainHandler = Handler(Looper.getMainLooper())
    private val pendingClipboardTexts = mutableListOf<String>()

    fun sendFileOfferAction(context: Context, intent: Intent?) {
        val action = intent?.getStringExtra("opencb_notification_action") ?: return
        val transferId = intent.getStringExtra("opencb_transfer_id") ?: return
        val notificationId = intent.getIntExtra("opencb_notification_id", -1)
        if (notificationId >= 0) {
            val manager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            manager.cancel(notificationId)
        }
        platformChannel?.invokeMethod(
            "fileOfferNotificationAction",
            mapOf("transferId" to transferId, "action" to action),
        )
    }

    fun sendBackgroundAction(context: Context, intent: Intent?) {
        val action = intent?.getStringExtra("opencb_background_action") ?: return
        val payload = mutableMapOf<String, Any>("action" to action)
        if (action == "sendClipboard") {
            try {
                val clipboard =
                    context.applicationContext.getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
                val clip = clipboard.primaryClip
                if (clip != null && clip.itemCount > 0) {
                    val text = clip.getItemAt(0).coerceToText(context)?.toString()
                    if (!text.isNullOrBlank()) {
                        payload["text"] = text
                    }
                }
            } catch (error: Exception) {
                Log.w(openCbLogTag, "Unable to read clipboard for background action.", error)
            }
        }
        mainHandler.post {
            platformChannel?.invokeMethod(
                "backgroundNotificationAction",
                payload,
            )
        }
    }

    fun sendClipboardFromUserAction(context: Context): Boolean {
        val text = try {
            val clipboard =
                context.applicationContext.getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
            val clip = clipboard.primaryClip
            if (clip != null && clip.itemCount > 0) {
                clip.getItemAt(0).coerceToText(context)?.toString()
            } else {
                null
            }
        } catch (error: Exception) {
            Log.w(openCbLogTag, "Unable to read clipboard from notification action.", error)
            null
        }
        if (text.isNullOrBlank()) return false
        mainHandler.post {
            platformChannel?.invokeMethod(
                "backgroundNotificationAction",
                mapOf("action" to "sendClipboard", "text" to text),
            )
        }
        return true
    }

    fun sendAndroidClipboardText(text: String) {
        if (text.isBlank()) return
        synchronized(pendingClipboardTexts) {
            if (pendingClipboardTexts.lastOrNull() != text) {
                pendingClipboardTexts.add(text)
            }
        }
        flushPendingClipboardTexts()
    }

    fun consumePendingClipboardTexts(): List<String> {
        synchronized(pendingClipboardTexts) {
            val texts = pendingClipboardTexts.toList()
            pendingClipboardTexts.clear()
            return texts
        }
    }

    fun flushPendingClipboardTexts() {
        mainHandler.post {
            val channel = platformChannel ?: return@post
            val texts = synchronized(pendingClipboardTexts) {
                pendingClipboardTexts.toList()
            }
            for (pendingText in texts) {
                channel.invokeMethod(
                    "androidClipboardText",
                    mapOf("text" to pendingText, "source" to "Clipboard Android"),
                    object : MethodChannel.Result {
                        override fun success(result: Any?) {
                            synchronized(pendingClipboardTexts) {
                                pendingClipboardTexts.remove(pendingText)
                            }
                        }

                        override fun error(
                            errorCode: String,
                            errorMessage: String?,
                            errorDetails: Any?,
                        ) {
                            Log.w(openCbLogTag, "Flutter rejected pending clipboard text: $errorCode")
                        }

                        override fun notImplemented() {
                            Log.w(openCbLogTag, "Flutter clipboard handler is not ready.")
                        }
                    },
                )
            }
        }
    }
}

object OpenCbSharedFileBridge {
    var platformChannel: MethodChannel? = null
    private val mainHandler = Handler(Looper.getMainLooper())
    private val pendingFiles = mutableListOf<Map<String, Any>>()

    @Synchronized
    fun push(files: List<Map<String, Any>>) {
        if (files.isEmpty()) return
        pendingFiles.addAll(files)
        val snapshot = files.toList()
        mainHandler.post {
            platformChannel?.invokeMethod("sharedFiles", snapshot)
        }
    }

    @Synchronized
    fun consume(): List<Map<String, Any>> {
        val files = pendingFiles.toList()
        pendingFiles.clear()
        return files
    }
}

class OpenCbApplication : FlutterApplication() {
    companion object {
        const val engineId = "opencb_background_engine"
    }

    lateinit var flutterEngine: FlutterEngine
        private set

    override fun onCreate() {
        super.onCreate()
        flutterEngine = FlutterEngine(this)
        GeneratedPluginRegistrant.registerWith(flutterEngine)
        flutterEngine.dartExecutor.executeDartEntrypoint(
            DartExecutor.DartEntrypoint.createDefault()
        )
        FlutterEngineCache.getInstance().put(engineId, flutterEngine)
    }
}

class OpenCbNotificationActionReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent?) {
        if (intent?.hasExtra("opencb_background_action") == true) {
            OpenCbNotificationBridge.sendBackgroundAction(context, intent)
            return
        }
        OpenCbNotificationBridge.sendFileOfferAction(context, intent)
    }
}

private fun Context.appIconBitmap(sizeDp: Int): Bitmap? {
    return try {
        val sizePx = (sizeDp * resources.displayMetrics.density).toInt().coerceAtLeast(1)
        val drawable = applicationInfo.loadIcon(packageManager)
        val bitmap = Bitmap.createBitmap(sizePx, sizePx, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(bitmap)
        drawable.setBounds(0, 0, canvas.width, canvas.height)
        drawable.draw(canvas)
        bitmap
    } catch (_: Exception) {
        null
    }
}

class OpenCbClipboardSendActivity : Activity() {
    private var attempts = 0
    private var finished = false
    private val handler = Handler(Looper.getMainLooper())

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        overridePendingTransition(0, 0)
    }

    override fun onResume() {
        super.onResume()
        scheduleClipboardSend(160)
    }

    override fun onWindowFocusChanged(hasFocus: Boolean) {
        super.onWindowFocusChanged(hasFocus)
        if (hasFocus) scheduleClipboardSend(80)
    }

    private fun scheduleClipboardSend(delayMs: Long) {
        if (finished) return
        handler.postDelayed({ tryClipboardSend() }, delayMs)
    }

    private fun tryClipboardSend() {
        if (finished) return
        attempts += 1
        val sent = OpenCbNotificationBridge.sendClipboardFromUserAction(this)
        if (sent) {
            finishWithToast("Đang gửi clipboard")
            return
        }
        if (attempts < 5) {
            scheduleClipboardSend(180)
            return
        }
        finishWithToast("Không đọc được clipboard")
    }

    private fun finishWithToast(message: String) {
        if (finished) return
        finished = true
        Toast.makeText(this, message, Toast.LENGTH_SHORT).show()
        finish()
        overridePendingTransition(0, 0)
    }
}

class OpenCbBackgroundService : Service() {
    companion object {
        private const val notificationId = 4818
        private const val clipboardPromptNotificationId = 4821
        private const val channelId = "opencb_background_v5"
        var isRunning = false
            private set

        fun start(context: Context): Boolean {
            return try {
                val intent = Intent(context, OpenCbBackgroundService::class.java)
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    context.startForegroundService(intent)
                } else {
                    @Suppress("DEPRECATION")
                    context.startService(intent)
                }
                true
            } catch (error: Exception) {
                Log.w(openCbLogTag, "Unable to start background service.", error)
                false
            }
        }

        fun stop(context: Context): Boolean {
            return try {
                context.stopService(Intent(context, OpenCbBackgroundService::class.java))
                true
            } catch (error: Exception) {
                Log.w(openCbLogTag, "Unable to stop background service.", error)
                false
            }
        }
    }

    private var multicastLock: WifiManager.MulticastLock? = null
    private var clipboardManager: ClipboardManager? = null
    private var lastNativeClipboardText: String? = null
    private val clipboardListener = ClipboardManager.OnPrimaryClipChangedListener {
        emitPrimaryClipboardText()
    }

    override fun onCreate() {
        super.onCreate()
        isRunning = true
        ensureChannel()
        startForeground(notificationId, buildNotification())
        acquireMulticastLock()
        startClipboardListener()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        ensureChannel()
        startForeground(notificationId, buildNotification())
        return START_STICKY
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onDestroy() {
        isRunning = false
        stopClipboardListener()
        releaseMulticastLock()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
            stopForeground(STOP_FOREGROUND_REMOVE)
        } else {
            @Suppress("DEPRECATION")
            stopForeground(true)
        }
        super.onDestroy()
    }

    private fun acquireMulticastLock() {
        try {
            val wifiManager =
                applicationContext.getSystemService(Context.WIFI_SERVICE) as WifiManager
            multicastLock = wifiManager.createMulticastLock("opencb_lan_discovery").apply {
                setReferenceCounted(false)
                acquire()
            }
        } catch (error: Exception) {
            Log.w(openCbLogTag, "Unable to acquire multicast lock.", error)
            multicastLock = null
        }
    }

    private fun releaseMulticastLock() {
        try {
            multicastLock?.takeIf { it.isHeld }?.release()
        } catch (error: Exception) {
            Log.w(openCbLogTag, "Unable to release multicast lock.", error)
        } finally {
            multicastLock = null
        }
    }

    private fun startClipboardListener() {
        try {
            clipboardManager =
                applicationContext.getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
            clipboardManager?.addPrimaryClipChangedListener(clipboardListener)
            emitPrimaryClipboardText()
        } catch (error: Exception) {
            Log.w(openCbLogTag, "Unable to start clipboard listener.", error)
            clipboardManager = null
        }
    }

    private fun stopClipboardListener() {
        try {
            clipboardManager?.removePrimaryClipChangedListener(clipboardListener)
        } catch (error: Exception) {
            Log.w(openCbLogTag, "Unable to stop clipboard listener.", error)
        } finally {
            clipboardManager = null
        }
    }

    private fun emitPrimaryClipboardText() {
        try {
            val clip = clipboardManager?.primaryClip ?: return
            if (clip.itemCount <= 0) return
            val text = clip.getItemAt(0).coerceToText(this)?.toString()?.trim()
            if (text.isNullOrEmpty() || text == lastNativeClipboardText) return
            lastNativeClipboardText = text
            if (OpenCbNotificationBridge.clipboardSendPromptEnabled) {
                showClipboardSendPrompt(text)
            }
            OpenCbNotificationBridge.sendAndroidClipboardText(text)
        } catch (error: Exception) {
            Log.w(openCbLogTag, "Unable to emit clipboard text from background service.", error)
        }
    }

    private fun showClipboardSendPrompt(text: String) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU &&
            checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) !=
                android.content.pm.PackageManager.PERMISSION_GRANTED
        ) {
            return
        }
        ensureChannel()
        val preview = text.replace(Regex("\\s+"), " ").let {
            if (it.length > 72) it.take(72) + "..." else it
        }
        val launchIntent = packageManager.getLaunchIntentForPackage(packageName)
            ?: Intent(this, MainActivity::class.java)
        launchIntent.flags = Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP
        val contentIntent = PendingIntent.getActivity(
            this,
            clipboardPromptNotificationId,
            launchIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            android.app.Notification.Builder(this, channelId)
        } else {
            @Suppress("DEPRECATION")
            android.app.Notification.Builder(this)
        }
        val notification = builder
            .setSmallIcon(R.drawable.ic_stat_opencb)
            .setLargeIcon(appIconBitmap(36))
            .setContentTitle("Clipboard mới")
            .setContentText(preview)
            .setContentIntent(contentIntent)
            .addAction(
                android.app.Notification.Action.Builder(
                    applicationInfo.icon,
                    "Gửi clipboard",
                    backgroundActionIntent("sendClipboard"),
                ).build()
            )
            .setAutoCancel(true)
            .setShowWhen(false)
            .setDefaults(0)
            .setSound(null)
            .setVibrate(null)
            .setPriority(android.app.Notification.PRIORITY_LOW)
            .setVisibility(android.app.Notification.VISIBILITY_PRIVATE)
            .build()
        (getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager)
            .notify(clipboardPromptNotificationId, notification)
    }

    private fun ensureChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        cleanupLegacyBackgroundChannels(manager)
        val channel = NotificationChannel(
            channelId,
            "OpenCB chạy nền",
            NotificationManager.IMPORTANCE_MIN,
        ).apply {
            description = "Giữ OpenCB online và cung cấp nút gửi clipboard"
            setShowBadge(false)
            enableVibration(false)
            setSound(null, null)
            lockscreenVisibility = android.app.Notification.VISIBILITY_SECRET
        }
        manager.createNotificationChannel(channel)
    }

    private fun cleanupLegacyBackgroundChannels(manager: NotificationManager) {
        val legacyIds = listOf(
            "opencb_background_v2",
            "opencb_background_v3",
            "opencb_background_v4",
        )
        for (id in legacyIds) {
            try {
                manager.deleteNotificationChannel(id)
            } catch (_: Exception) {
            }
        }
    }

    private fun buildNotification(): android.app.Notification {
        val launchIntent = packageManager.getLaunchIntentForPackage(packageName)
            ?: Intent(this, MainActivity::class.java)
        launchIntent.flags = Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP
        val pendingIntent = PendingIntent.getActivity(
            this,
            4818,
            launchIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            android.app.Notification.Builder(this, channelId)
        } else {
            @Suppress("DEPRECATION")
            android.app.Notification.Builder(this)
        }
        val compactView = RemoteViews(packageName, R.layout.opencb_background_notification).apply {
            setTextViewText(R.id.opencb_background_title, "OpenCB")
            setTextViewText(R.id.opencb_background_action, "Gửi clipboard")
            setOnClickPendingIntent(
                R.id.opencb_background_action,
                backgroundActionIntent("sendClipboard"),
            )
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
            builder
                .setCustomContentView(compactView)
                .setCustomBigContentView(compactView)
                .setCustomHeadsUpContentView(compactView)
                .setStyle(android.app.Notification.DecoratedCustomViewStyle())
        }
        val notification = builder
            .setSmallIcon(R.drawable.ic_stat_opencb)
            .setContentTitle("OpenCB đang chạy nền")
            .setContentText("Sync LAN sẵn sàng")
            .setContentIntent(pendingIntent)
            .setCategory(android.app.Notification.CATEGORY_SERVICE)
            .setLocalOnly(true)
            .setOnlyAlertOnce(true)
            .setOngoing(true)
            .setShowWhen(false)
            .setDefaults(0)
            .setSound(null)
            .setVibrate(null)
            .setPriority(android.app.Notification.PRIORITY_MIN)
            .setVisibility(android.app.Notification.VISIBILITY_SECRET)
            .build()
        notification.flags =
            notification.flags or
                android.app.Notification.FLAG_ONGOING_EVENT or
                android.app.Notification.FLAG_NO_CLEAR
        return notification
    }

    private fun backgroundActionIntent(action: String): PendingIntent {
        val intent = if (action == "sendClipboard") {
            Intent(this, OpenCbClipboardSendActivity::class.java).apply {
                flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_NO_ANIMATION
                putExtra("opencb_background_action", action)
            }
        } else {
            Intent(this, OpenCbNotificationActionReceiver::class.java).apply {
                putExtra("opencb_background_action", action)
            }
        }
        val requestCode = 481800 + action.hashCode().let { if (it < 0) -it else it } % 10000
        val flags = PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        return if (action == "sendClipboard") {
            PendingIntent.getActivity(this, requestCode, intent, flags)
        } else {
            PendingIntent.getBroadcast(this, requestCode, intent, flags)
        }
    }
}

class MainActivity : FlutterActivity() {
    private val notificationChannelId = "opencb_alerts_v2"
    private val silentNotificationChannelId = "opencb_silent_alerts_v1"
    private val notificationPermissionRequestCode = 4817
    private val androidFilePickerRequestCode = 4820
    private var nextNotificationId = 1000
    private var platformChannel: MethodChannel? = null
    private val publicDownloadStreams = mutableMapOf<String, OutputStream>()
    private val publicDownloadUris = mutableMapOf<String, Uri>()
    private val publicDownloadFiles = mutableMapOf<String, File>()
    private val contentInputStreams = mutableMapOf<String, InputStream>()
    private var pendingAndroidFilePickerResult: MethodChannel.Result? = null
    private var currentNavigationBarColor = defaultNavigationBarColor()
    private var currentStatusBarColor = defaultNavigationBarColor()
    private var currentLightSystemBars = true

    override fun provideFlutterEngine(context: Context): FlutterEngine? {
        return (application as OpenCbApplication).flutterEngine
    }

    override fun shouldDestroyEngineWithHost(): Boolean {
        return false
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        ensureNotificationChannel()
        configureEdgeToEdgeSystemBars()
    }

    override fun onPostResume() {
        super.onPostResume()
        configureEdgeToEdgeSystemBars(
            navigationBarColor = currentNavigationBarColor,
            statusBarColor = currentStatusBarColor,
            lightSystemBars = currentLightSystemBars,
        )
        if (OpenCbBackgroundService.isRunning && hasNotificationPermission()) {
            OpenCbBackgroundService.start(this)
        }
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == notificationPermissionRequestCode && hasNotificationPermission()) {
            OpenCbBackgroundService.start(this)
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        val channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "opencb/platform")
        platformChannel = channel
        OpenCbNotificationBridge.platformChannel = channel
        OpenCbNotificationBridge.flushPendingClipboardTexts()
        OpenCbSharedFileBridge.platformChannel = channel
        channel.setMethodCallHandler { call, result ->
                when (call.method) {
                    "getDeviceName" -> {
                        result.success(resolveDeviceName())
                    }
                    "setSystemBars" -> {
                        val navigationBarColor = call.argument<Number>("navigationBarColor")?.toInt()
                        val statusBarColor = call.argument<Number>("statusBarColor")?.toInt()
                        val lightSystemBars = call.argument<Boolean>("lightSystemBars") ?: !isNightMode()
                        if (navigationBarColor != null) {
                            configureEdgeToEdgeSystemBars(
                                navigationBarColor = navigationBarColor,
                                statusBarColor = statusBarColor ?: navigationBarColor,
                                lightSystemBars = lightSystemBars,
                            )
                        } else {
                            configureEdgeToEdgeSystemBars(
                                statusBarColor = statusBarColor ?: currentStatusBarColor,
                                lightSystemBars = lightSystemBars,
                            )
                        }
                        result.success(true)
                    }
                    "requestIgnoreBatteryOptimizations" -> {
                        result.success(requestIgnoreBatteryOptimizations())
                    }
                    "isIgnoringBatteryOptimizations" -> {
                        result.success(isIgnoringBatteryOptimizations())
                    }
                    "startBackgroundSyncService" -> {
                        result.success(OpenCbBackgroundService.start(this))
                    }
                    "stopBackgroundSyncService" -> {
                        result.success(OpenCbBackgroundService.stop(this))
                    }
                    "isBackgroundSyncServiceRunning" -> {
                        result.success(OpenCbBackgroundService.isRunning)
                    }
                    "openNotificationSettings" -> {
                        result.success(openNotificationSettings())
                    }
                    "openAppSettings" -> {
                        result.success(openAppSettings())
                    }
                    "requestNotificationPermission" -> {
                        result.success(requestNotificationPermission())
                    }
                    "setAndroidClipboardText" -> {
                        val text = call.argument<String>("text")
                        result.success(setAndroidClipboardText(text))
                    }
                    "setClipboardSendPromptEnabled" -> {
                        OpenCbNotificationBridge.clipboardSendPromptEnabled =
                            call.argument<Boolean>("enabled") ?: false
                        result.success(true)
                    }
                    "showOpenCbNotification" -> {
                        val title = call.argument<String>("title") ?: "OpenCB"
                        val body = call.argument<String>("body") ?: ""
                        val transferId = call.argument<String>("transferId")
                        val showFileOfferActions =
                            call.argument<Boolean>("showFileOfferActions") ?: false
                        val silent = call.argument<Boolean>("silent") ?: false
                        val autoCancelAfterMs =
                            call.argument<Number>("autoCancelAfterMs")?.toLong() ?: 0L
                        result.success(
                            showOpenCbNotification(
                                title,
                                body,
                                transferId,
                                showFileOfferActions,
                                silent,
                                autoCancelAfterMs,
                            )
                        )
                    }
                    "showToast" -> {
                        val message = call.argument<String>("message") ?: ""
                        if (message.isNotBlank()) {
                            runOnUiThread {
                                Toast.makeText(this, message, Toast.LENGTH_SHORT).show()
                            }
                        }
                        result.success(true)
                    }
                    "consumeSharedFiles" -> {
                        result.success(OpenCbSharedFileBridge.consume())
                    }
                    "consumeAndroidClipboardTexts" -> {
                        result.success(OpenCbNotificationBridge.consumePendingClipboardTexts())
                    }
                    "pickAndroidFiles" -> {
                        pickAndroidFiles(result)
                    }
                    "openContentInputStream" -> {
                        val uri = call.argument<String>("uri")
                        if (uri.isNullOrBlank()) {
                            result.error("invalid_uri", "URI is empty.", null)
                        } else {
                            result.success(openContentInputStream(uri))
                        }
                    }
                    "readContentInputChunk" -> {
                        val token = call.argument<String>("token")
                        val size = call.argument<Number>("size")?.toInt() ?: 524288
                        val stream = contentInputStreams[token]
                        if (token.isNullOrBlank() || stream == null) {
                            result.error("invalid_stream", "Input stream is not open.", null)
                        } else {
                            result.success(readContentInputChunk(stream, size))
                        }
                    }
                    "closeContentInputStream" -> {
                        val token = call.argument<String>("token")
                        if (!token.isNullOrBlank()) {
                            closeContentInputStream(token)
                        }
                        result.success(true)
                    }
                    "getOpenCbDownloadsDirectory" -> {
                        result.success("Download/OpenCB")
                    }
                    "openPublicDownloadFile" -> {
                        val fileName = call.argument<String>("name")
                        val relativePath = call.argument<String>("relativePath")
                        if (fileName.isNullOrBlank()) {
                            result.error("invalid_name", "File name is empty.", null)
                        } else {
                            result.success(openPublicDownloadFile(fileName, relativePath))
                        }
                    }
                    "writePublicDownloadChunk" -> {
                        val token = call.argument<String>("token")
                        val bytes = call.argument<ByteArray>("bytes")
                        val stream = publicDownloadStreams[token]
                        if (token.isNullOrBlank() || bytes == null || stream == null) {
                            result.error("invalid_transfer", "Download stream is not open.", null)
                        } else {
                            stream.write(bytes)
                            result.success(true)
                        }
                    }
                    "finishPublicDownloadFile" -> {
                        val token = call.argument<String>("token")
                        if (token.isNullOrBlank()) {
                            result.error("invalid_transfer", "Download token is empty.", null)
                        } else {
                            finishPublicDownloadFile(token)
                            result.success(true)
                        }
                    }
                    "cancelPublicDownloadFile" -> {
                        val token = call.argument<String>("token")
                        if (!token.isNullOrBlank()) {
                            cancelPublicDownloadFile(token)
                        }
                        result.success(true)
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
        handleSharedContent(intent, notifyFlutter = false)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        handleNotificationAction(intent)
        handleSharedContent(intent, notifyFlutter = true)
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != androidFilePickerRequestCode) return
        val pendingResult = pendingAndroidFilePickerResult ?: return
        pendingAndroidFilePickerResult = null
        if (resultCode != RESULT_OK || data == null) {
            pendingResult.success(emptyList<Map<String, Any>>())
            return
        }
        val files = sharedFileMapsFromIntent(data, persistPermission = true)
        pendingResult.success(files)
    }

    override fun onDestroy() {
        for (stream in contentInputStreams.values) {
            try {
                stream.close()
            } catch (_: Exception) {
            }
        }
        contentInputStreams.clear()
        super.onDestroy()
    }

    private fun configureEdgeToEdgeSystemBars(
        navigationBarColor: Int = defaultNavigationBarColor(),
        statusBarColor: Int = defaultNavigationBarColor(),
        lightSystemBars: Boolean = !isNightMode(),
    ) {
        currentNavigationBarColor = navigationBarColor
        currentStatusBarColor = statusBarColor
        currentLightSystemBars = lightSystemBars
        window.statusBarColor = statusBarColor
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

    private fun ensureNotificationChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        cleanupLegacyBackgroundChannels(manager)
        val channel = NotificationChannel(
            notificationChannelId,
            "OpenCB",
            NotificationManager.IMPORTANCE_HIGH,
        ).apply {
            description = "Thông báo nhận file và sync LAN"
            enableVibration(true)
            setShowBadge(false)
            lockscreenVisibility = android.app.Notification.VISIBILITY_PUBLIC
        }
        manager.createNotificationChannel(channel)
        val silentChannel = NotificationChannel(
            silentNotificationChannelId,
            "OpenCB thông báo tạm thời",
            NotificationManager.IMPORTANCE_HIGH,
        ).apply {
            description = "Thông báo kết quả ngắn, tự ẩn sau khi hiển thị"
            enableVibration(false)
            setSound(null, null)
            setShowBadge(false)
            lockscreenVisibility = android.app.Notification.VISIBILITY_PUBLIC
        }
        manager.createNotificationChannel(silentChannel)
    }

    private fun cleanupLegacyBackgroundChannels(manager: NotificationManager) {
        val legacyIds = listOf(
            "opencb_background_v2",
            "opencb_background_v3",
            "opencb_background_v4",
        )
        for (id in legacyIds) {
            try {
                manager.deleteNotificationChannel(id)
            } catch (_: Exception) {
            }
        }
    }

    private fun requestNotificationPermission(): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) return true
        if (hasNotificationPermission()) {
            return true
        }
        requestPermissions(
            arrayOf(Manifest.permission.POST_NOTIFICATIONS),
            notificationPermissionRequestCode,
        )
        return false
    }

    private fun hasNotificationPermission(): Boolean {
        return Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU ||
            checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) ==
                android.content.pm.PackageManager.PERMISSION_GRANTED
    }

    private fun setAndroidClipboardText(text: String?): Boolean {
        if (text.isNullOrEmpty()) return false
        return try {
            val clipboard =
                applicationContext.getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
            clipboard.setPrimaryClip(ClipData.newPlainText("OpenCB", text))
            true
        } catch (_: Exception) {
            false
        }
    }

    private fun openNotificationSettings(): Boolean {
        return try {
            val intent = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS).apply {
                    putExtra(Settings.EXTRA_APP_PACKAGE, packageName)
                }
            } else {
                Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS).apply {
                    data = Uri.parse("package:$packageName")
                }
            }
            startActivity(intent)
            true
        } catch (_: Exception) {
            try {
                startActivity(
                    Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS).apply {
                        data = Uri.parse("package:$packageName")
                    }
                )
                true
            } catch (_: Exception) {
                false
            }
        }
    }

    private fun openAppSettings(): Boolean {
        return try {
            startActivity(
                Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS).apply {
                    data = Uri.parse("package:$packageName")
                }
            )
            true
        } catch (_: Exception) {
            false
        }
    }

    private fun showOpenCbNotification(
        title: String,
        body: String,
        transferId: String?,
        showFileOfferActions: Boolean,
        silent: Boolean,
        autoCancelAfterMs: Long,
    ): Boolean {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU &&
            checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) !=
                android.content.pm.PackageManager.PERMISSION_GRANTED
        ) {
            requestNotificationPermission()
            return false
        }
        ensureNotificationChannel()
        val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        val notificationId = nextNotificationId++
        val launchIntent = packageManager.getLaunchIntentForPackage(packageName)
            ?: Intent(this, MainActivity::class.java)
        launchIntent.flags = Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP
        if (!transferId.isNullOrBlank()) {
            launchIntent.putExtra("opencb_notification_action", "open")
            launchIntent.putExtra("opencb_transfer_id", transferId)
            launchIntent.putExtra("opencb_notification_id", notificationId)
        }
        val pendingIntent = PendingIntent.getActivity(
            this,
            notificationId,
            launchIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        val channelId = if (silent) silentNotificationChannelId else notificationChannelId
        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            android.app.Notification.Builder(this, channelId)
        } else {
            @Suppress("DEPRECATION")
            android.app.Notification.Builder(this)
        }
        builder
            .setSmallIcon(R.drawable.ic_stat_opencb)
            .setContentTitle(title)
            .setContentIntent(pendingIntent)
            .setAutoCancel(true)
            .setNumber(0)
            .setPriority(android.app.Notification.PRIORITY_HIGH)
            .setVisibility(android.app.Notification.VISIBILITY_PUBLIC)
            .setOnlyAlertOnce(true)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            builder.setBadgeIconType(android.app.Notification.BADGE_ICON_NONE)
        }
        if (!showFileOfferActions) {
            builder.setLargeIcon(appIconBitmap(40))
        }
        if (silent) {
            builder
                .setDefaults(0)
                .setSound(null)
                .setVibrate(null)
        } else {
            builder.setDefaults(android.app.Notification.DEFAULT_ALL)
        }
        if (body.isNotBlank()) {
            builder
                .setContentText(body)
                .setStyle(android.app.Notification.BigTextStyle().bigText(body))
        }
        if (showFileOfferActions && !transferId.isNullOrBlank()) {
            builder.addAction(
                android.app.Notification.Action.Builder(
                    R.drawable.ic_stat_opencb,
                    "Từ chối",
                    fileOfferActionIntent(transferId, notificationId, "reject"),
                ).build()
            )
            builder.addAction(
                android.app.Notification.Action.Builder(
                    R.drawable.ic_stat_opencb,
                    "Nhận",
                    fileOfferActionIntent(transferId, notificationId, "accept"),
                ).build()
            )
        }
        manager.notify(notificationId, builder.build())
        if (autoCancelAfterMs > 0) {
            Handler(Looper.getMainLooper()).postDelayed({
                manager.cancel(notificationId)
            }, autoCancelAfterMs)
        }
        return true
    }

    private fun fileOfferActionIntent(
        transferId: String,
        notificationId: Int,
        decision: String,
    ): PendingIntent {
        val intent = Intent(this, OpenCbNotificationActionReceiver::class.java).apply {
            putExtra("opencb_notification_action", decision)
            putExtra("opencb_transfer_id", transferId)
            putExtra("opencb_notification_id", notificationId)
        }
        val requestCode = notificationId + if (decision == "accept") 100000 else 200000
        return PendingIntent.getBroadcast(
            this,
            requestCode,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
    }

    private fun handleNotificationAction(intent: Intent?) {
        OpenCbNotificationBridge.sendFileOfferAction(this, intent)
    }

    private fun handleSharedContent(intent: Intent?, notifyFlutter: Boolean) {
        if (intent == null) return
        if (intent.action != Intent.ACTION_SEND && intent.action != Intent.ACTION_SEND_MULTIPLE) {
            return
        }
        val files = sharedFileMapsFromIntent(intent, persistPermission = true)
        if (files.isEmpty()) return
        OpenCbSharedFileBridge.push(files)
    }

    private fun sharedFileMapsFromIntent(
        intent: Intent,
        persistPermission: Boolean,
    ): List<Map<String, Any>> {
        val sharedUris = extractUrisFromIntent(intent)
        if (sharedUris.isEmpty()) return emptyList()
        val files = mutableListOf<Map<String, Any>>()
        for (uri in sharedUris) {
            try {
                if (persistPermission) {
                    try {
                        contentResolver.takePersistableUriPermission(
                            uri,
                            Intent.FLAG_GRANT_READ_URI_PERMISSION,
                        )
                    } catch (_: Exception) {
                    }
                }
                val file = fileMapFromUri(uri)
                val size = file["size"] as? Long ?: 0L
                if (size >= 0L) files.add(file)
            } catch (_: Exception) {
            }
        }
        return files
    }

    private fun extractUrisFromIntent(intent: Intent): List<Uri> {
        val uris = mutableListOf<Uri>()
        if (intent.action == Intent.ACTION_SEND || intent.action == Intent.ACTION_SEND_MULTIPLE) {
            intent.getParcelableExtra<Uri>(Intent.EXTRA_STREAM)?.let { uris.add(it) }
            val streamValues = intent.getParcelableArrayListExtra<Uri>(Intent.EXTRA_STREAM)
            if (streamValues != null) uris.addAll(streamValues)
        }
        val clipData = intent.clipData
        if (clipData != null) {
            for (index in 0 until clipData.itemCount) {
                clipData.getItemAt(index).uri?.let { uris.add(it) }
            }
        }
        intent.data?.let { uris.add(it) }
        return uris.distinctBy { it.toString() }
    }

    private fun fileMapFromUri(uri: Uri): Map<String, Any> {
        val name = resolveSharedFileName(uri)
        val size = resolveSharedFileSize(uri)
        return mapOf(
            "uri" to uri.toString(),
            "name" to sanitizeFileName(name),
            "size" to size,
        )
    }

    private fun pickAndroidFiles(result: MethodChannel.Result) {
        if (pendingAndroidFilePickerResult != null) {
            result.error("picker_active", "A file picker is already active.", null)
            return
        }
        pendingAndroidFilePickerResult = result
        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
            addCategory(Intent.CATEGORY_OPENABLE)
            type = "*/*"
            putExtra(Intent.EXTRA_ALLOW_MULTIPLE, true)
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            addFlags(Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION)
        }
        try {
            startActivityForResult(intent, androidFilePickerRequestCode)
        } catch (error: Exception) {
            pendingAndroidFilePickerResult = null
            result.error("picker_failed", error.message, null)
        }
    }

    private fun resolveSharedFileName(uri: Uri): String {
        if (uri.scheme == "content") {
            contentResolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)
                ?.use { cursor ->
                    if (cursor.moveToFirst()) {
                        val index = cursor.getColumnIndex(OpenableColumns.DISPLAY_NAME)
                        if (index >= 0) {
                            val name = cursor.getString(index)
                            if (!name.isNullOrBlank()) return name
                        }
                    }
                }
        }
        val lastSegment = uri.lastPathSegment?.substringAfterLast('/')?.trim()
        return if (lastSegment.isNullOrBlank()) {
            "shared-${System.currentTimeMillis()}"
        } else {
            lastSegment
        }
    }

    private fun resolveSharedFileSize(uri: Uri): Long {
        if (uri.scheme == "content") {
            contentResolver.query(uri, arrayOf(OpenableColumns.SIZE), null, null, null)
                ?.use { cursor ->
                    if (cursor.moveToFirst()) {
                        val index = cursor.getColumnIndex(OpenableColumns.SIZE)
                        if (index >= 0 && !cursor.isNull(index)) {
                            return cursor.getLong(index)
                        }
                    }
                }
        }
        if (uri.scheme == "file") {
            val path = uri.path
            if (!path.isNullOrBlank()) return File(path).length()
        }
        return -1L
    }

    private fun openContentInputStream(rawUri: String): String {
        val uri = Uri.parse(rawUri)
        val stream = contentResolver.openInputStream(uri)
            ?: throw IllegalStateException("Can not open content stream.")
        val token = UUID.randomUUID().toString()
        contentInputStreams[token] = stream
        return token
    }

    private fun readContentInputChunk(stream: InputStream, rawSize: Int): ByteArray {
        val size = rawSize.coerceIn(64 * 1024, 4 * 1024 * 1024)
        val buffer = ByteArray(size)
        val read = stream.read(buffer)
        if (read <= 0) return ByteArray(0)
        return if (read == buffer.size) buffer else buffer.copyOf(read)
    }

    private fun closeContentInputStream(token: String) {
        try {
            contentInputStreams.remove(token)?.close()
        } catch (_: Exception) {
        }
    }

    private fun openPublicDownloadFile(rawName: String, rawRelativePath: String?): Map<String, String> {
        val token = UUID.randomUUID().toString()
        val safeRelativePath = sanitizeRelativePath(rawRelativePath ?: rawName)
        val relativeParts = safeRelativePath.split("/").filter { it.isNotBlank() }
        val fileName = sanitizeFileName(relativeParts.lastOrNull() ?: rawName)
        val subDirectory = relativeParts.dropLast(1).joinToString("/")
        val displayDirectory = if (subDirectory.isBlank()) {
            "Download/OpenCB"
        } else {
            "Download/OpenCB/$subDirectory"
        }
        val uniqueName = uniquePublicDownloadName(fileName, subDirectory)
        val displayPath = "$displayDirectory/$uniqueName"

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            val values = ContentValues().apply {
                put(MediaStore.MediaColumns.DISPLAY_NAME, uniqueName)
                put(MediaStore.MediaColumns.MIME_TYPE, "application/octet-stream")
                put(
                    MediaStore.MediaColumns.RELATIVE_PATH,
                    if (subDirectory.isBlank()) {
                        "${Environment.DIRECTORY_DOWNLOADS}/OpenCB"
                    } else {
                        "${Environment.DIRECTORY_DOWNLOADS}/OpenCB/$subDirectory"
                    },
                )
                put(MediaStore.MediaColumns.IS_PENDING, 1)
            }
            val collection = MediaStore.Downloads.getContentUri(MediaStore.VOLUME_EXTERNAL_PRIMARY)
            val uri = contentResolver.insert(collection, values)
                ?: throw IllegalStateException("Can not create public download item.")
            val stream = contentResolver.openOutputStream(uri)
                ?: throw IllegalStateException("Can not open public download stream.")
            publicDownloadStreams[token] = stream
            publicDownloadUris[token] = uri
            return mapOf("token" to token, "path" to displayPath)
        }

        @Suppress("DEPRECATION")
        val directory = File(
            Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DOWNLOADS),
            "OpenCB",
        )
        if (!directory.exists()) directory.mkdirs()
        val targetDirectory = if (subDirectory.isBlank()) directory else File(directory, subDirectory)
        if (!targetDirectory.exists()) targetDirectory.mkdirs()
        val file = uniqueLegacyDownloadFile(targetDirectory, uniqueName)
        publicDownloadStreams[token] = FileOutputStream(file)
        publicDownloadFiles[token] = file
        return mapOf("token" to token, "path" to "$displayDirectory/${file.name}")
    }

    private fun finishPublicDownloadFile(token: String) {
        publicDownloadStreams.remove(token)?.close()
        val uri = publicDownloadUris.remove(token)
        publicDownloadFiles.remove(token)
        if (uri != null && Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            val values = ContentValues().apply {
                put(MediaStore.MediaColumns.IS_PENDING, 0)
            }
            contentResolver.update(uri, values, null, null)
        }
    }

    private fun cancelPublicDownloadFile(token: String) {
        try {
            publicDownloadStreams.remove(token)?.close()
        } catch (_: Exception) {
        }
        publicDownloadUris.remove(token)?.let { uri ->
            try {
                contentResolver.delete(uri, null, null)
            } catch (_: Exception) {
            }
        }
        publicDownloadFiles.remove(token)?.let { file ->
            try {
                file.delete()
            } catch (_: Exception) {
            }
        }
    }

    private fun sanitizeFileName(value: String): String {
        val invalidChars = "<>:\"/\\|?*"
        val sanitized = value
            .map { char -> if (char.code < 32 || invalidChars.contains(char)) '_' else char }
            .joinToString("")
            .trim()
        return sanitized.ifBlank { "file" }
    }

    private fun sanitizeRelativePath(value: String): String {
        val parts = value
            .replace('\\', '/')
            .split("/")
            .map { it.trim() }
            .filter { it.isNotBlank() && it != "." && it != ".." }
            .map { sanitizeFileName(it) }
        return if (parts.isEmpty()) sanitizeFileName(value) else parts.joinToString("/")
    }

    private fun uniquePublicDownloadName(fileName: String, subDirectory: String = ""): String {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) return fileName
        val existing = mutableSetOf<String>()
        val collection = MediaStore.Downloads.getContentUri(MediaStore.VOLUME_EXTERNAL_PRIMARY)
        val projection = arrayOf(MediaStore.MediaColumns.DISPLAY_NAME)
        val selection = "${MediaStore.MediaColumns.RELATIVE_PATH}=?"
        val relativePath = if (subDirectory.isBlank()) {
            "${Environment.DIRECTORY_DOWNLOADS}/OpenCB/"
        } else {
            "${Environment.DIRECTORY_DOWNLOADS}/OpenCB/$subDirectory/"
        }
        val selectionArgs = arrayOf(relativePath)
        contentResolver.query(collection, projection, selection, selectionArgs, null)?.use { cursor ->
            val nameIndex = cursor.getColumnIndex(MediaStore.MediaColumns.DISPLAY_NAME)
            while (cursor.moveToNext() && nameIndex >= 0) {
                existing.add(cursor.getString(nameIndex))
            }
        }
        if (!existing.contains(fileName)) return fileName
        val dotIndex = fileName.lastIndexOf('.')
        val stem = if (dotIndex <= 0) fileName else fileName.substring(0, dotIndex)
        val extension = if (dotIndex <= 0) "" else fileName.substring(dotIndex)
        for (index in 1 until 10000) {
            val candidate = "$stem ($index)$extension"
            if (!existing.contains(candidate)) return candidate
        }
        return "$stem-${System.currentTimeMillis()}$extension"
    }

    private fun uniqueLegacyDownloadFile(directory: File, fileName: String): File {
        var candidate = File(directory, fileName)
        if (!candidate.exists()) return candidate
        val dotIndex = fileName.lastIndexOf('.')
        val stem = if (dotIndex <= 0) fileName else fileName.substring(0, dotIndex)
        val extension = if (dotIndex <= 0) "" else fileName.substring(dotIndex)
        for (index in 1 until 10000) {
            candidate = File(directory, "$stem ($index)$extension")
            if (!candidate.exists()) return candidate
        }
        return File(directory, "$stem-${System.currentTimeMillis()}$extension")
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
