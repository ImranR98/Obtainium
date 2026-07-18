package dev.imranr.obtainium

import android.app.Activity
import android.app.ActivityOptions
import android.app.Notification
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.ClipData
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.ApplicationInfo
import android.content.pm.PackageManager
import android.content.res.Configuration
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Paint
import android.graphics.Typeface
import android.graphics.drawable.Drawable
import android.graphics.fonts.SystemFonts
import android.net.Uri
import android.net.wifi.WifiManager
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.os.PowerManager
import android.os.SystemClock
import android.provider.DocumentsContract
import android.system.Os
import android.text.format.DateFormat
import android.util.DisplayMetrics
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream
import java.io.File
import java.io.PrintWriter
import java.io.StringWriter
import java.util.UUID
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors
import kotlin.math.abs
import kotlin.math.roundToInt
import kotlin.system.exitProcess

private const val CHANNEL = "dev.imranr.obtainium/installer"
private const val EXTERNAL_INSTALL_CHANNEL = "dev.imranr.obtainium/external_install"
private const val DEVICE_APPS_CHANNEL = "dev.imranr.obtainium/device_apps"
private const val POWER_CHANNEL = "dev.imranr.obtainium/power"
private const val STORAGE_CHANNEL = "dev.imranr.obtainium/storage"
private const val SHARE_CHANNEL = "dev.imranr.obtainium/share"
private const val NOTIFICATIONS_CHANNEL = "dev.imranr.obtainium/notifications"
private const val DIAGNOSTICS_CHANNEL = "dev.imranr.obtainium/diagnostics"
private const val DOWNLOAD_WAKE_LOCK_TAG = "ObtainX:DownloadWakeLock"
private const val DOWNLOAD_WIFI_LOCK_TAG = "ObtainX:DownloadWifiLock"
private const val NATIVE_CRASH_LOG_FILE = "obtainx-native-crashes.log"
private const val MAX_NATIVE_CRASH_LOG_BYTES = 256 * 1024L
private const val REQUEST_PROMOTED_ONGOING_EXTRA = "android.requestPromotedOngoing"
private const val SESSION_API_PACKAGE_INSTALLED_ACTION =
    "com.android_package_installer.content.SESSION_API_PACKAGE_INSTALLED"
private const val APK_MIME = "application/vnd.android.package-archive"
private const val RELEASE_DIR = "releases"
private const val INSTALL_TIMEOUT_MS = 120_000L
private const val INSTALL_BROADCAST_BATCH_CONTINUE_DELAY_MS = 200L
private const val MAX_SYSTEM_DISPLAY_SCALE = 1.2f
private const val OPEN_PERSISTED_DOCUMENT_TREE_REQUEST_CODE = 5107
/// Ignore focus regain if it arrived within this window of the FIRST focus loss (transition bounce).
/// Only the first loss is recorded; subsequent oscillations during TPI teardown are ignored.
private const val FOCUS_REGAIN_CANCEL_MIN_MS = 200L
/// After ObtainX regains window focus (TPI entered onPause), wait this long before completing
/// the install session.
///
/// Why this is needed: popular TPIs such as InstallerX use android:launchMode="singleInstance"
/// and guard onNewIntent against re-use while a session is active:
///   if (session != null && intent.flags.hasFlag(FLAG_ACTIVITY_NEW_TASK)) { return }  // drop
/// The `session` field is never nulled out — it stays non-null through onPause/onStop/onDestroy.
/// A new intent is only accepted by a FRESH instance, which Android creates once the current
/// activity is fully destroyed (onDestroy complete). onWindowFocusChanged(true) fires in ObtainX
/// roughly when the TPI enters onPause; onStop + onDestroy typically take another 150–400ms.
/// 500ms gives a comfortable margin before the next install intent is fired.
private const val FOCUS_REGAIN_SETTLE_MS = 500L
/// If the ACTION_PACKAGE_REPLACED broadcast confirms install success but focus never returns
/// (some TPIs / OEM builds do not reliably deliver onWindowFocusChanged back to ObtainX),
/// complete the session after this fallback rather than waiting the full 120s timeout.
private const val BROADCAST_CONFIRMED_INTERACTIVE_FALLBACK_MS = 5_000L

private fun Context.withCappedDisplayScale(): Context {
    val currentDensityDpi = resources.configuration.densityDpi
    val maximumDensityDpi =
        (DisplayMetrics.DENSITY_DEVICE_STABLE * MAX_SYSTEM_DISPLAY_SCALE).roundToInt()
    if (currentDensityDpi <= maximumDensityDpi) return this

    return createConfigurationContext(
        Configuration().apply {
            densityDpi = maximumDensityDpi
        },
    )
}

class MainActivity : FlutterActivity() {
    override fun attachBaseContext(newBase: Context) {
        super.attachBaseContext(newBase.withCappedDisplayScale())
    }

    companion object {
        private var notificationsMethodChannel: MethodChannel? = null
        private val downloadCancelLock = Any()
        private val pendingDownloadCancelAppIds = linkedSetOf<String>()
        private var downloadCancelHandlerReady = false

        @Volatile
        private var nativeCrashHandlerInstalled = false

        private fun installNativeCrashHandler(context: Context) {
            if (nativeCrashHandlerInstalled) return
            val appContext = context.applicationContext
            val previousHandler = Thread.getDefaultUncaughtExceptionHandler()
            Thread.setDefaultUncaughtExceptionHandler { thread, throwable ->
                writeNativeCrashLog(
                    appContext,
                    "Uncaught native exception on ${thread.name}",
                    throwable,
                )
                if (previousHandler != null) {
                    previousHandler.uncaughtException(thread, throwable)
                } else {
                    exitProcess(2)
                }
            }
            nativeCrashHandlerInstalled = true
        }

        private fun consumeNativeCrashLog(context: Context): String? {
            val crashLog = File(context.filesDir, NATIVE_CRASH_LOG_FILE)
            if (!crashLog.exists()) return null
            val text = runCatching { crashLog.readText() }.getOrNull()
            runCatching { crashLog.delete() }
            return text?.ifBlank { null }
        }

        private fun writeNativeCrashLog(
            context: Context,
            message: String,
            throwable: Throwable,
        ) {
            runCatching {
                val crashLog = File(context.filesDir, NATIVE_CRASH_LOG_FILE)
                if (crashLog.exists() && crashLog.length() > MAX_NATIVE_CRASH_LOG_BYTES) {
                    crashLog.delete()
                }
                crashLog.appendText(
                    buildString {
                        append(System.currentTimeMillis())
                        append(" | ")
                        append(message)
                        append('\n')
                        append(stackTraceText(throwable))
                        append('\n')
                    },
                )
            }
        }

        private fun stackTraceText(throwable: Throwable): String {
            val stringWriter = StringWriter()
            throwable.printStackTrace(PrintWriter(stringWriter))
            return stringWriter.toString()
        }

        fun cancelDownloadFromNotification(appId: String) {
            var channelToNotify: MethodChannel? = null
            synchronized(downloadCancelLock) {
                if (downloadCancelHandlerReady) {
                    channelToNotify = notificationsMethodChannel
                }
                if (channelToNotify == null) {
                    pendingDownloadCancelAppIds.add(appId)
                }
            }
            channelToNotify?.invokeMethod("cancelDownload", appId)
        }

        private fun consumePendingDownloadCancels(): List<String> {
            synchronized(downloadCancelLock) {
                downloadCancelHandlerReady = true
                val pendingAppIds = pendingDownloadCancelAppIds.toList()
                pendingDownloadCancelAppIds.clear()
                return pendingAppIds
            }
        }

        private fun resetNotificationChannel(channel: MethodChannel?) {
            synchronized(downloadCancelLock) {
                notificationsMethodChannel = channel
                if (channel == null) {
                    downloadCancelHandlerReady = false
                }
            }
        }
    }

    private class InstallWatcher(
        val methodResult: MethodChannel.Result,
        val handler: Handler,
        val receiver: BroadcastReceiver,
        val releaseCacheFiles: List<File>,
        var responded: Boolean = false,
        var focusLost: Boolean = false,
        var focusLostAtUptimeMs: Long = 0L,
        /// Set when PACKAGE_ADDED/REPLACED matches expected package. We do not complete the session
        /// immediately: doing so would let Dart start the next batch install while InstallerX (or
        /// similar) is still tearing down, causing later intents to be dropped.
        /// Interactive mode (focusLost=true): completes via [onWindowFocusChanged] + FOCUS_REGAIN_SETTLE_MS
        ///   delay, or via BROADCAST_CONFIRMED_INTERACTIVE_FALLBACK_MS if focus never returns.
        /// Background mode (focusLost=false): completes via [onResume] or INSTALL_BROADCAST_BATCH_CONTINUE_DELAY_MS.
        var packageInstallBroadcastReceived: Boolean = false,
    )

    private sealed class InstallSessionOutcome {
        data class Success(val installSucceeded: Boolean) : InstallSessionOutcome()
        data class Error(val code: String, val message: String?) : InstallSessionOutcome()
    }

    private var installWatcher: InstallWatcher? = null
    private var installerChannel: MethodChannel? = null
    private val downloadKeepAwakeLock = Any()
    private var downloadKeepAwakeCount = 0
    private var downloadWakeLock: PowerManager.WakeLock? = null
    private var downloadWifiLock: WifiManager.WifiLock? = null
    private var downloadForegroundServiceCount = 0
    private var openPersistedDocumentTreeResult: MethodChannel.Result? = null
    private var shareChannel: MethodChannel? = null
    private var initialSharedTextConsumed = false
    private var pendingSharedText: String? = null

    // Off-main-thread executor for the device-apps queries. Enumerating
    // installed apps and rendering their icons is done here so the platform
    // main thread stays responsive; results are posted back on the main looper
    // (a MethodChannel.Result must be answered on the platform thread).
    private val deviceAppsExecutor: ExecutorService = Executors.newSingleThreadExecutor()
    private val mainHandler = Handler(Looper.getMainLooper())

    override fun onCreate(savedInstanceState: Bundle?) {
        installNativeCrashHandler(this)
        super.onCreate(savedInstanceState)
    }

    private fun completeThirdPartyInstallSession(watcher: InstallWatcher, outcome: InstallSessionOutcome) {
        if (watcher.responded) return
        watcher.responded = true
        if (installWatcher === watcher) {
            installWatcher = null
        }
        watcher.handler.removeCallbacksAndMessages(null)
        try { unregisterReceiver(watcher.receiver) } catch (_: Exception) { }
        for (cacheFile in watcher.releaseCacheFiles) {
            try { cacheFile.delete() } catch (_: Exception) { }
        }
        when (outcome) {
            is InstallSessionOutcome.Success -> watcher.methodResult.success(outcome.installSucceeded)
            is InstallSessionOutcome.Error -> watcher.methodResult.error(outcome.code, outcome.message, null)
        }
    }

    override fun onResume() {
        super.onResume()
        val watcher = installWatcher ?: return
        if (watcher.responded || !watcher.packageInstallBroadcastReceived) return
        if (watcher.focusLost) {
            // Interactive mode: onWindowFocusChanged already posted a FOCUS_REGAIN_SETTLE_MS
            // delayed completion. Completing here would fire before that delay expires,
            // bypassing the TPI teardown buffer and sending the next batch intent too soon.
            return
        }
        // Background mode (focus never lost): complete immediately.
        completeThirdPartyInstallSession(watcher, InstallSessionOutcome.Success(true))
    }

    override fun onWindowFocusChanged(hasFocus: Boolean) {
        super.onWindowFocusChanged(hasFocus)
        val watcher = installWatcher ?: return
        if (!hasFocus) {
            // Only record the initial loss time; don't overwrite on subsequent oscillations
            // (e.g. during TPI teardown animations). The FOCUS_REGAIN_CANCEL_MIN_MS check
            // compares against this timestamp, and resetting it on every loss would make
            // the final focus-regain event fail the check and stall until the timeout.
            if (!watcher.focusLost) {
                watcher.focusLostAtUptimeMs = SystemClock.uptimeMillis()
            }
            watcher.focusLost = true
            return
        }
        // Regained focus — third-party installer overlay dismissed (or user cancelled without installing).
        if (!watcher.focusLost || watcher.responded) return
        if (SystemClock.uptimeMillis() - watcher.focusLostAtUptimeMs < FOCUS_REGAIN_CANCEL_MIN_MS) {
            return
        }
        // Delay session completion so the TPI activity finishes destroying before Dart
        // can fire the next install intent in batch mode. The broadcast may also arrive
        // within this window, converting a Success(false) into Success(true).
        watcher.handler.postDelayed({
            if (installWatcher !== watcher || watcher.responded) return@postDelayed
            completeThirdPartyInstallSession(
                watcher,
                InstallSessionOutcome.Success(watcher.packageInstallBroadcastReceived),
            )
        }, FOCUS_REGAIN_SETTLE_MS)
    }

    override fun onNewIntent(intent: Intent) {
        try {
            super.onNewIntent(intent)
        } catch (ex: IllegalStateException) {
            val duplicateInstallerReply =
                intent.action == SESSION_API_PACKAGE_INSTALLED_ACTION &&
                    ex.message == "Reply already submitted"
            // #3018/#3015: super.onNewIntent can throw if the Flutter engine
            // isn't attached yet. A shared-text intent is replayed via
            // deliverPendingSharedText() once configureFlutterEngine runs, so
            // swallow that case rather than crashing.
            val shareIntentBeforeEngineReady = intent.action == Intent.ACTION_SEND
            if (!duplicateInstallerReply && !shareIntentBeforeEngineReady) {
                throw ex
            }
        }
        setIntent(intent)
        val sharedText = getSharedTextFromIntent(intent) ?: return
        enqueueSharedText(sharedText)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        installerChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
        installerChannel?.setMethodCallHandler { call, result ->
            when (call.method) {
                "launchInstallIntent" -> {
                    try {
                        val pathArg = call.argument<String>("path")!!
                        val apkSourcePaths = pathArg.split(',')
                            .map { it.trim() }
                            .filter { it.isNotEmpty() }
                        val targetPackage = call.argument<String>("package")
                        val targetActivity = call.argument<String>("activity")
                        val expectedPkgName = call.argument<String>("expectedPackageName")
                        launchInstallIntent(apkSourcePaths, targetPackage, targetActivity, expectedPkgName, result)
                    } catch (ex: Exception) {
                        result.error("INSTALL_ERROR", ex.message, null)
                    }
                }
                else -> result.notImplemented()
            }
        }
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            EXTERNAL_INSTALL_CHANNEL,
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "listInstallTargets" -> result.success(listInstallTargets())
                "contentUriForFile" -> {
                    val path = call.argument<String>("path")
                    if (path.isNullOrEmpty()) {
                        result.error("BAD_ARGS", "Missing file path", null)
                    } else {
                        try {
                            result.success(contentUriForFile(path))
                        } catch (ex: Exception) {
                            result.error("URI_FAILED", ex.message, null)
                        }
                    }
                }
                else -> result.notImplemented()
            }
        }
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            DEVICE_APPS_CHANNEL,
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "getApplicationLabels" -> {
                    val packageNames = call.argument<List<String>>("packageNames")
                    if (packageNames == null) {
                        result.success(emptyMap<String, String>())
                        return@setMethodCallHandler
                    }
                    result.success(getApplicationLabels(packageNames))
                }
                "getInstalledAppsLight" -> {
                    // Compact one-pass enumeration: only the fields the bulk-add
                    // list needs, avoiding the heavy full-PackageInfo marshalling
                    // (with ApplicationInfo per app) that stuttered the UI thread.
                    deviceAppsExecutor.execute {
                        val apps = try {
                            getInstalledAppsLight()
                        } catch (_: Exception) {
                            emptyList<Map<String, Any?>>()
                        }
                        mainHandler.post { result.success(apps) }
                    }
                }
                "getAppIcon" -> {
                    val packageName = call.argument<String>("packageName")
                    if (packageName == null) {
                        result.success(null)
                        return@setMethodCallHandler
                    }
                    deviceAppsExecutor.execute {
                        val bytes = getAppIconBytes(packageName)
                        mainHandler.post { result.success(bytes) }
                    }
                }
                "getSystemFontFiles" -> {
                    // Every weight/style file of the device's default font
                    // family, so the app can register the whole family (real
                    // bold/medium) — not just the single regular file — and
                    // still follow a user-picked OEM font.
                    deviceAppsExecutor.execute {
                        val files = try {
                            getSystemFontFiles()
                        } catch (_: Exception) {
                            emptyList<String>()
                        }
                        mainHandler.post { result.success(files) }
                    }
                }
                "getSigningCertificates" -> {
                    val packageName = call.argument<String>("packageName")
                    result.success(
                        packageName?.let { getSigningCertificates(it) },
                    )
                }
                "uses24HourFormat" -> {
                    result.success(DateFormat.is24HourFormat(this))
                }
                else -> result.notImplemented()
            }
        }
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            POWER_CHANNEL,
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "acquireDownloadKeepAwake" -> {
                    result.success(acquireDownloadKeepAwake())
                }
                "releaseDownloadKeepAwake" -> {
                    releaseDownloadKeepAwake()
                    result.success(null)
                }
                "isDeviceInteractive" -> {
                    val powerManager = getSystemService(Context.POWER_SERVICE) as PowerManager
                    result.success(powerManager.isInteractive)
                }
                else -> result.notImplemented()
            }
        }
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            STORAGE_CHANNEL,
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "openPersistedDocumentTree" -> {
                    openPersistedDocumentTree(call.argument<String>("initialUri"), result)
                }
                "hasPersistedDocumentTreePermission" -> {
                    result.success(
                        hasPersistedDocumentTreePermission(call.argument<String>("uri")),
                    )
                }
                else -> result.notImplemented()
            }
        }
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            NOTIFICATIONS_CHANNEL,
        ).also { channel ->
            resetNotificationChannel(channel)
            channel.setMethodCallHandler { call, result ->
                when (call.method) {
                    "consumePendingDownloadCancels" -> {
                        result.success(consumePendingDownloadCancels())
                    }
                    "showDownloadProgressNotification" -> {
                        try {
                            result.success(showDownloadProgressNotification(call))
                        } catch (ex: Exception) {
                            result.error("NOTIFICATION_ERROR", ex.message, null)
                        }
                    }
                    "startDownloadForegroundService" -> {
                        try {
                            startDownloadForegroundService(call)
                            result.success(true)
                        } catch (ex: Exception) {
                            result.error("DOWNLOAD_SERVICE_ERROR", ex.message, null)
                        }
                    }
                    "stopDownloadForegroundService" -> {
                        try {
                            stopDownloadForegroundService()
                            result.success(true)
                        } catch (ex: Exception) {
                            result.error("DOWNLOAD_SERVICE_ERROR", ex.message, null)
                        }
                    }
                    else -> result.notImplemented()
                }
            }
        }
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            DIAGNOSTICS_CHANNEL,
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "consumeNativeCrashLog" -> {
                    result.success(consumeNativeCrashLog(this))
                }
                else -> result.notImplemented()
            }
        }
        shareChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            SHARE_CHANNEL,
        ).also { channel ->
            channel.setMethodCallHandler { call, result ->
                when (call.method) {
                    "getInitialSharedText" -> {
                        if (initialSharedTextConsumed) {
                            result.success(null)
                            return@setMethodCallHandler
                        }
                        initialSharedTextConsumed = true
                        val sharedText = pendingSharedText ?: getSharedTextFromIntent(intent)
                        pendingSharedText = null
                        result.success(sharedText)
                    }
                    else -> result.notImplemented()
                }
            }
        }
        deliverPendingSharedText()
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        resetNotificationChannel(null)
        super.cleanUpFlutterEngine(flutterEngine)
    }

    private fun enqueueSharedText(sharedText: String) {
        pendingSharedText = sharedText
        deliverPendingSharedText()
    }

    private fun deliverPendingSharedText() {
        val channel = shareChannel ?: return
        val sharedText = pendingSharedText ?: return
        channel.invokeMethod(
            "onSharedText",
            sharedText,
            object : MethodChannel.Result {
                override fun success(result: Any?) {
                    if (pendingSharedText == sharedText) {
                        pendingSharedText = null
                    }
                }

                override fun error(errorCode: String, errorMessage: String?, errorDetails: Any?) {
                }

                override fun notImplemented() {
                }
            },
        )
    }

    private fun getSharedTextFromIntent(intent: Intent?): String? {
        // Accept any text/* share (matches the manifest's text/* SEND filter and
        // upstream's broadened handling), not just text/plain.
        if (intent?.action != Intent.ACTION_SEND ||
            intent.type?.startsWith("text/") != true
        ) {
            return null
        }
        return intent.getCharSequenceExtra(Intent.EXTRA_TEXT)
            ?.toString()
            ?.trim()
            ?.takeIf { it.isNotEmpty() }
    }

    private fun hasPersistedDocumentTreePermission(uriString: String?): Boolean {
        if (uriString.isNullOrBlank()) {
            return false
        }
        val uri = Uri.parse(uriString)
        return contentResolver.persistedUriPermissions.any { persistedPermission ->
            persistedPermission.uri == uri &&
                persistedPermission.isReadPermission &&
                persistedPermission.isWritePermission
        }
    }

    private fun openPersistedDocumentTree(initialUri: String?, result: MethodChannel.Result) {
        if (openPersistedDocumentTreeResult != null) {
            result.error("PICKER_ACTIVE", "A document tree picker is already active.", null)
            return
        }

        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT_TREE).apply {
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            addFlags(Intent.FLAG_GRANT_WRITE_URI_PERMISSION)
            addFlags(Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION)
            addFlags(Intent.FLAG_GRANT_PREFIX_URI_PERMISSION)
            if (!initialUri.isNullOrBlank() && Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                putExtra(DocumentsContract.EXTRA_INITIAL_URI, Uri.parse(initialUri))
            }
        }

        openPersistedDocumentTreeResult = result
        try {
            startActivityForResult(intent, OPEN_PERSISTED_DOCUMENT_TREE_REQUEST_CODE)
        } catch (ex: Exception) {
            openPersistedDocumentTreeResult = null
            result.error("OPEN_TREE_FAILED", ex.message, null)
        }
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        if (requestCode != OPEN_PERSISTED_DOCUMENT_TREE_REQUEST_CODE) {
            super.onActivityResult(requestCode, resultCode, data)
            return
        }

        val pendingResult = openPersistedDocumentTreeResult ?: return
        openPersistedDocumentTreeResult = null

        if (resultCode != Activity.RESULT_OK) {
            pendingResult.success(null)
            return
        }

        val uri = data?.data
        if (uri == null) {
            pendingResult.success(null)
            return
        }

        val permissionFlags = Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION
        val grantedPermissionFlags = data.flags and permissionFlags
        if (grantedPermissionFlags != permissionFlags) {
            pendingResult.error(
                "PERSIST_TREE_PERMISSION_FAILED",
                "The selected folder did not grant read and write permissions.",
                null,
            )
            return
        }
        try {
            contentResolver.takePersistableUriPermission(
                uri,
                grantedPermissionFlags,
            )
            pendingResult.success(uri.toString())
        } catch (ex: Exception) {
            pendingResult.error("PERSIST_TREE_PERMISSION_FAILED", ex.message, null)
        }
    }

    @Suppress("DEPRECATION")
    private fun acquireDownloadKeepAwake(): Boolean = synchronized(downloadKeepAwakeLock) {
        var acquiredWakeLock: PowerManager.WakeLock? = null
        var acquiredWifiLock: WifiManager.WifiLock? = null
        try {
            if (downloadWakeLock?.isHeld != true) {
                val powerManager = getSystemService(Context.POWER_SERVICE) as PowerManager
                acquiredWakeLock = powerManager.newWakeLock(
                    PowerManager.PARTIAL_WAKE_LOCK,
                    DOWNLOAD_WAKE_LOCK_TAG,
                ).apply {
                    setReferenceCounted(false)
                    acquire()
                }
            }

            if (downloadWifiLock?.isHeld != true) {
                val wifiManager = applicationContext.getSystemService(Context.WIFI_SERVICE) as? WifiManager
                    ?: throw IllegalStateException("Wifi service unavailable")
                acquiredWifiLock = wifiManager.createWifiLock(
                    WifiManager.WIFI_MODE_FULL_HIGH_PERF,
                    DOWNLOAD_WIFI_LOCK_TAG,
                ).apply {
                    setReferenceCounted(false)
                    acquire()
                }
            }

            if (acquiredWakeLock != null) {
                downloadWakeLock = acquiredWakeLock
            }
            if (acquiredWifiLock != null) {
                downloadWifiLock = acquiredWifiLock
            }
            downloadKeepAwakeCount += 1
            true
        } catch (_: Exception) {
            try {
                if (acquiredWifiLock?.isHeld == true) {
                    acquiredWifiLock.release()
                }
            } catch (_: Exception) { }
            try {
                if (acquiredWakeLock?.isHeld == true) {
                    acquiredWakeLock.release()
                }
            } catch (_: Exception) { }
            false
        }
    }

    private fun releaseDownloadKeepAwake() {
        synchronized(downloadKeepAwakeLock) {
            if (downloadKeepAwakeCount > 0) {
                downloadKeepAwakeCount -= 1
            }
            if (downloadKeepAwakeCount > 0) return@synchronized

            try {
                if (downloadWifiLock?.isHeld == true) {
                    downloadWifiLock?.release()
                }
            } catch (_: Exception) { }
            downloadWifiLock = null

            try {
                if (downloadWakeLock?.isHeld == true) {
                    downloadWakeLock?.release()
                }
            } catch (_: Exception) { }
            downloadWakeLock = null
        }
    }

    private fun showDownloadProgressNotification(call: io.flutter.plugin.common.MethodCall): Boolean {
        val id = call.argument<Int>("id") ?: return false
        val title = call.argument<String>("title") ?: return false
        val message = call.argument<String>("message") ?: ""
        val channelCode = call.argument<String>("channelCode") ?: return false
        val progressPercent = call.argument<Int>("progressPercent") ?: 0
        val indeterminate = call.argument<Boolean>("indeterminate") ?: false
        val shortCriticalText = call.argument<String>("shortCriticalText")

        val launchIntent = packageManager.getLaunchIntentForPackage(packageName)
            ?: Intent(this, MainActivity::class.java)
        launchIntent.addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP)
        val contentIntent = PendingIntent.getActivity(
            this,
            id,
            launchIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
            activityLaunchOptions(),
        )
        val cancelAppId = call.argument<String>("appId")
        val cancelIntent = if (!indeterminate && !cancelAppId.isNullOrBlank()) {
            PendingIntent.getBroadcast(
                this,
                id,
                Intent(this, DownloadActionReceiver::class.java).apply {
                    action = DownloadActionReceiver.ACTION_CANCEL_DOWNLOAD
                    putExtra(DownloadActionReceiver.EXTRA_APP_ID, cancelAppId)
                },
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
            )
        } else {
            null
        }
        val builder = Notification.Builder(this, channelCode)
            .setSmallIcon(R.drawable.ic_notification)
            .setContentTitle(title)
            .setContentText(message)
            .setContentIntent(contentIntent)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setShowWhen(false)
            .setProgress(100, progressPercent.coerceIn(0, 100), indeterminate)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.BAKLAVA) {
            val progressStyle = Notification.ProgressStyle()
                .setProgressIndeterminate(indeterminate)
            if (!indeterminate) {
                progressStyle
                    .setStyledByProgress(true)
                    .setProgress(progressPercent.coerceIn(0, 100))
                    .setProgressSegments(listOf(Notification.ProgressStyle.Segment(100)))
            }
            builder
                .setStyle(progressStyle)
                .addExtras(android.os.Bundle().apply {
                    putBoolean(REQUEST_PROMOTED_ONGOING_EXTRA, true)
                })
        }
        if (cancelIntent != null) {
            builder.addAction(
                R.drawable.ic_notification,
                call.argument<String>("cancelLabel") ?: "Cancel",
                cancelIntent,
            )
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.BAKLAVA && !shortCriticalText.isNullOrBlank()) {
            builder.setShortCriticalText(shortCriticalText)
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.BAKLAVA) {
            try {
                builder.javaClass
                    .getMethod("setRequestPromotedOngoing", Boolean::class.javaPrimitiveType)
                    .invoke(builder, true)
            } catch (_: Exception) {
                // Present as ProgressStyle even on Android 16 builds that do not expose the promotion setter.
            }
        }
        val notificationManager = getSystemService(NotificationManager::class.java)
        notificationManager.notify(id, builder.build())
        return true
    }

    private fun startDownloadForegroundService(call: io.flutter.plugin.common.MethodCall) {
        val intent = Intent(this, DownloadForegroundService::class.java).apply {
            putExtra(
                DownloadForegroundService.EXTRA_NOTIFICATION_ID,
                call.argument<Int>("id") ?: 0,
            )
            putExtra(DownloadForegroundService.EXTRA_APP_ID, call.argument<String>("appId"))
            putExtra(DownloadForegroundService.EXTRA_TITLE, call.argument<String>("title"))
            putExtra(DownloadForegroundService.EXTRA_MESSAGE, call.argument<String>("message"))
            putExtra(DownloadForegroundService.EXTRA_CHANNEL_CODE, call.argument<String>("channelCode"))
            putExtra(DownloadForegroundService.EXTRA_CHANNEL_NAME, call.argument<String>("channelName"))
            putExtra(
                DownloadForegroundService.EXTRA_CHANNEL_DESCRIPTION,
                call.argument<String>("channelDescription"),
            )
            putExtra(DownloadForegroundService.EXTRA_CANCEL_LABEL, call.argument<String>("cancelLabel"))
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            startForegroundService(intent)
        } else {
            startService(intent)
        }
        downloadForegroundServiceCount += 1
    }

    private fun stopDownloadForegroundService() {
        if (downloadForegroundServiceCount > 0) {
            downloadForegroundServiceCount -= 1
        }
        if (downloadForegroundServiceCount > 0) {
            return
        }
        stopService(Intent(this, DownloadForegroundService::class.java))
    }

    private fun activityLaunchOptions(): android.os.Bundle? {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.BAKLAVA) {
            return null
        }
        return ActivityOptions.makeBasic()
            .setPendingIntentCreatorBackgroundActivityStartMode(
                ActivityOptions.MODE_BACKGROUND_ACTIVITY_START_ALLOW_IF_VISIBLE,
            )
            .toBundle()
    }

    @Suppress("DEPRECATION")
    /// One-pass compact enumeration of installed apps. Returns only the fields
    /// the bulk-add flow needs (package name, label, system flag, source dir),
    /// so the platform-channel reply is tiny — instead of marshalling a full
    /// PackageInfo + ApplicationInfo per app across the channel and decoding it
    /// on the Flutter UI isolate, which was the source of the bulk-scan hitch.
    private fun getInstalledAppsLight(): List<Map<String, Any?>> {
        val pm = packageManager
        @Suppress("DEPRECATION")
        val packages = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            pm.getInstalledPackages(PackageManager.PackageInfoFlags.of(0))
        } else {
            pm.getInstalledPackages(0)
        }
        val out = ArrayList<Map<String, Any?>>(packages.size)
        for (pkg in packages) {
            val appInfo = pkg.applicationInfo ?: continue
            val packageName = pkg.packageName ?: continue
            val isSystem =
                (appInfo.flags and ApplicationInfo.FLAG_SYSTEM) != 0 ||
                    (appInfo.flags and ApplicationInfo.FLAG_UPDATED_SYSTEM_APP) != 0
            val label = try {
                pm.getApplicationLabel(appInfo).toString()
            } catch (_: Exception) {
                packageName
            }
            out.add(
                mapOf(
                    "packageName" to packageName,
                    "label" to label,
                    "isSystem" to isSystem,
                    "sourceDir" to appInfo.sourceDir,
                ),
            )
        }
        return out
    }

    /// Renders an installed app's icon to PNG bytes. Drawing the drawable onto
    /// a canvas composites adaptive icons (API 26+ foreground/background layers)
    /// correctly into a full square bitmap; the Flutter side handles shaping and
    /// downscales on decode. Capped to [maxIconPx] to keep the payload small.
    private fun getAppIconBytes(packageName: String): ByteArray? {
        return try {
            val appInfo = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                packageManager.getApplicationInfo(
                    packageName,
                    PackageManager.ApplicationInfoFlags.of(0),
                )
            } else {
                @Suppress("DEPRECATION")
                packageManager.getApplicationInfo(packageName, 0)
            }
            val drawable = packageManager.getApplicationIcon(appInfo)
            val bitmap = drawableToBitmap(drawable)
            ByteArrayOutputStream().use { stream ->
                bitmap.compress(Bitmap.CompressFormat.PNG, 100, stream)
                stream.toByteArray()
            }
        } catch (_: Exception) {
            null
        }
    }

    private fun drawableToBitmap(drawable: Drawable): Bitmap {
        val maxIconPx = 192
        val intrinsicW = drawable.intrinsicWidth
        val intrinsicH = drawable.intrinsicHeight
        var width = if (intrinsicW > 0) intrinsicW else maxIconPx
        var height = if (intrinsicH > 0) intrinsicH else maxIconPx
        val largest = maxOf(width, height)
        if (largest > maxIconPx) {
            val scale = maxIconPx.toFloat() / largest
            width = (width * scale).roundToInt().coerceAtLeast(1)
            height = (height * scale).roundToInt().coerceAtLeast(1)
        }
        val bitmap = Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(bitmap)
        drawable.setBounds(0, 0, width, height)
        drawable.draw(canvas)
        return bitmap
    }

    /// Returns the file paths of every weight/style in the device's default
    /// font family. The regular file is found by matching Typeface.DEFAULT's
    /// metrics (the same heuristic the old android_system_font plugin used, so
    /// a user-selected OEM font is still honoured); its siblings are then
    /// gathered by shared family stem. Registering all of them under one Flutter
    /// family yields real bold/medium instead of the faux bold you get from a
    /// single regular file. On a modern device where the default is one variable
    /// font file, that single file is returned and Flutter derives weights from
    /// its weight axis.
    private fun getSystemFontFiles(): List<String> {
        val fallback = "/system/fonts/Roboto-Regular.ttf"
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) {
            return listOf(fallback).filter { File(it).exists() }
        }
        val blacklist = "/system/fonts/DroidSansMono.ttf"
        val defaultMetrics = Paint().apply {
            typeface = Typeface.DEFAULT
            textSize = 100f
        }.fontMetrics

        val fonts = SystemFonts.getAvailableFonts()
        var baseFile: File? = null
        for (font in fonts) {
            val file = font.file ?: continue
            if (file.absolutePath == blacklist) continue
            val metrics = Paint().apply {
                typeface = Typeface.createFromFile(file)
                textSize = 100f
            }.fontMetrics
            if (metricsMatch(defaultMetrics, metrics)) {
                baseFile = file
                break
            }
        }
        val base = baseFile ?: return listOf(fallback).filter { File(it).exists() }

        val stem = fontFamilyStem(base.name)
        val paths = LinkedHashSet<String>()
        paths.add(base.absolutePath)
        for (font in fonts) {
            val file = font.file ?: continue
            if (file.parent == base.parent && fontFamilyStem(file.name) == stem) {
                paths.add(file.absolutePath)
            }
        }
        return paths.toList()
    }

    private fun metricsMatch(m1: Paint.FontMetrics, m2: Paint.FontMetrics): Boolean {
        val threshold = 0.0001f
        return abs(m1.ascent - m2.ascent) < threshold &&
            abs(m1.descent - m2.descent) < threshold &&
            abs(m1.leading - m2.leading) < threshold &&
            abs(m1.bottom - m2.bottom) < threshold &&
            abs(m1.top - m2.top) < threshold
    }

    /// "Roboto-Regular.ttf" -> "Roboto"; "NotoSans-BoldItalic.otf" -> "NotoSans".
    /// Groups the weight/style files of one family without mixing in condensed
    /// or otherwise-named variants (e.g. "RobotoFlex").
    private fun fontFamilyStem(fileName: String): String =
        fileName.substringBeforeLast('.').substringBefore('-')

    private fun getApplicationLabels(packageNames: List<String>): Map<String, String> {
        val labelsByPackageName = mutableMapOf<String, String>()
        for (packageName in packageNames) {
            try {
                val applicationInfo = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                    packageManager.getApplicationInfo(
                        packageName,
                        PackageManager.ApplicationInfoFlags.of(0),
                    )
                } else {
                    packageManager.getApplicationInfo(packageName, 0)
                }
                labelsByPackageName[packageName] =
                    packageManager.getApplicationLabel(applicationInfo).toString()
            } catch (_: PackageManager.NameNotFoundException) {
                // App was uninstalled between package scan and label lookup.
            }
        }
        return labelsByPackageName
    }

    @Suppress("DEPRECATION")
    private fun getSigningCertificates(packageName: String): Map<String, Any>? {
        val packageInfo = try {
            when {
                Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU ->
                    packageManager.getPackageInfo(
                        packageName,
                        PackageManager.PackageInfoFlags.of(
                            PackageManager.GET_SIGNING_CERTIFICATES.toLong(),
                        ),
                    )
                Build.VERSION.SDK_INT >= Build.VERSION_CODES.P ->
                    packageManager.getPackageInfo(
                        packageName,
                        PackageManager.GET_SIGNING_CERTIFICATES,
                    )
                else ->
                    packageManager.getPackageInfo(
                        packageName,
                        PackageManager.GET_SIGNATURES,
                    )
            }
        } catch (_: PackageManager.NameNotFoundException) {
            return null
        }

        val hasMultipleSigners =
            Build.VERSION.SDK_INT >= Build.VERSION_CODES.P &&
                packageInfo.signingInfo?.hasMultipleSigners() == true
        val signatures = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            val signingInfo = packageInfo.signingInfo ?: return null
            if (hasMultipleSigners) {
                signingInfo.apkContentsSigners
            } else {
                signingInfo.signingCertificateHistory
            }
        } else {
            packageInfo.signatures
        }

        return mapOf(
            "hasMultipleSigners" to hasMultipleSigners,
            "signatures" to (signatures?.map { it.toByteArray() } ?: emptyList<ByteArray>()),
        )
    }

    /**
     * One entry per install-capable activity across all apps. Apps that expose
     * several install-capable activities return all of them so the user can
     * pick the specific intent they want.
     */
    private fun listInstallTargets(): List<Map<String, String>> {
        val targets = ArrayList<Map<String, String>>()
        val probe = Uri.parse("content://dev.imranr.obtainium.probe/sample.apk")
        val actions = listOf(Intent.ACTION_VIEW, Intent.ACTION_INSTALL_PACKAGE)
        for (action in actions) {
            @Suppress("DEPRECATION")
            val intent = Intent(action).setDataAndType(probe, APK_MIME)
            for (resolved in packageManager.queryIntentActivities(intent, 0)) {
                val info = resolved.activityInfo ?: continue
                val pkg = info.packageName ?: continue
                if (pkg == packageName) continue
                val activity = info.name ?: continue
                val activityLabel = runCatching {
                    when {
                        resolved.labelRes != 0 || resolved.nonLocalizedLabel != null ->
                            resolved.loadLabel(packageManager)
                        info.labelRes != 0 || info.nonLocalizedLabel != null ->
                            info.loadLabel(packageManager)
                        else -> null
                    }?.toString()?.trim()?.ifEmpty { null }
                }.getOrNull()
                targets.add(
                    buildMap {
                        put("package", pkg)
                        put("activity", activity)
                        if (activityLabel != null) {
                            put("activityLabel", activityLabel)
                        }
                    },
                )
            }
        }
        return targets
    }

    /** Exposes a downloaded file through the app's FileProvider as a content:// URI. */
    private fun contentUriForFile(path: String): String {
        val uri = FileProvider.getUriForFile(this, packageName, File(path))
        return uri.toString()
    }

    @Suppress("DEPRECATION")
    private fun launchInstallIntent(
        apkSourcePaths: List<String>,
        targetPackage: String?,
        targetActivity: String?,
        expectedPkgName: String?,
        methodResult: MethodChannel.Result
    ) {
        if (apkSourcePaths.isEmpty()) {
            methodResult.error("INSTALL_ERROR", "No APK paths", null)
            return
        }
        val sourceFiles = apkSourcePaths.map { path -> File(path) }
        for (source in sourceFiles) {
            if (!source.isFile) {
                methodResult.error("INSTALL_ERROR", "Not a readable file: ${source.path}", null)
                return
            }
        }
        val releaseFiles = sourceFiles.map { copyToReleaseCacheUnique(it) }
        val contentUris = releaseFiles.map { releaseFileToContentUri(it) }

        val installFlag = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
            Intent.FLAG_GRANT_READ_URI_PERMISSION
        } else {
            0
        }

        val primaryMime = if (releaseFiles.size == 1) {
            mimeTypeForInstallableFile(releaseFiles[0])
        } else {
            APK_MIME
        }
        // XAPK/APKM/ZIP bundles: use ACTION_VIEW so targets that only handle "open file"
        // (e.g. InstallerX from a file manager) receive the same intent shape.
        val intentAction =
            if (releaseFiles.size == 1 && primaryMime == "application/zip") {
                Intent.ACTION_VIEW
            } else {
                Intent.ACTION_INSTALL_PACKAGE
            }
        val intent = Intent(intentAction).apply {
            if (contentUris.size == 1) {
                setDataAndType(contentUris[0], primaryMime)
            } else {
                clipData = ClipData.newUri(contentResolver, "apk", contentUris[0]).apply {
                    for (idx in 1 until contentUris.size) {
                        addItem(ClipData.Item(contentUris[idx]))
                    }
                }
                setDataAndType(contentUris[0], primaryMime)
            }
            flags = installFlag or Intent.FLAG_ACTIVITY_NEW_TASK
            if (!targetPackage.isNullOrEmpty() && !targetActivity.isNullOrEmpty()) {
                component = ComponentName(targetPackage, targetActivity)
            }
        }

        if (expectedPkgName.isNullOrEmpty()) {
            try {
                startActivity(intent)
            } catch (_: Exception) {
                //
            } finally {
                for (releaseFile in releaseFiles) {
                    try { releaseFile.delete() } catch (_: Exception) { }
                }
            }
            methodResult.success(false)
            return
        }

        val handler = Handler(Looper.getMainLooper())

        val receiver = object : BroadcastReceiver() {
            override fun onReceive(context: Context, broadcastIntent: Intent) {
                // Use [installWatcher] only (one assignment before [registerReceiver]) so there is no
                // window where a captured ref and [installWatcher] disagree. Tie this callback to the
                // watcher instance via [InstallWatcher.receiver] so a stale registration after a new
                // install does not mutate the wrong session.
                val session = installWatcher ?: return
                if (session.receiver !== this) return
                val changedPkg = broadcastIntent.data?.schemeSpecificPart ?: return
                if (changedPkg != expectedPkgName || session.responded) return
                if (session.packageInstallBroadcastReceived) return
                session.packageInstallBroadcastReceived = true
                installerChannel?.invokeMethod(
                    "thirdPartyInstallPackageChanged",
                    mapOf("packageName" to changedPkg),
                )
                if (!session.focusLost) {
                    // Background mode: TPI never took focus, complete after short settle.
                    session.handler.postDelayed({
                        if (
                            installWatcher === session &&
                            !session.responded &&
                            session.packageInstallBroadcastReceived &&
                            !session.focusLost
                        ) {
                            completeThirdPartyInstallSession(
                                session,
                                InstallSessionOutcome.Success(true),
                            )
                        }
                    }, INSTALL_BROADCAST_BATCH_CONTINUE_DELAY_MS)
                } else {
                    // Interactive mode: install confirmed, waiting for focus to return.
                    // Schedule a fallback so we don't wait the full 120s if onWindowFocusChanged
                    // never fires (some TPIs don't return focus reliably).
                    session.handler.postDelayed({
                        if (installWatcher === session && !session.responded) {
                            completeThirdPartyInstallSession(
                                session,
                                InstallSessionOutcome.Success(true),
                            )
                        }
                    }, BROADCAST_CONFIRMED_INTERACTIVE_FALLBACK_MS)
                }
            }
        }

        val filter = IntentFilter().apply {
            addAction(Intent.ACTION_PACKAGE_ADDED)
            addAction(Intent.ACTION_PACKAGE_REPLACED)
            addDataScheme("package")
        }
        val sessionWatcher = InstallWatcher(
            methodResult,
            handler,
            receiver,
            releaseFiles,
        )
        installWatcher = sessionWatcher
        registerReceiver(receiver, filter)

        handler.postDelayed({
            if (installWatcher !== sessionWatcher || sessionWatcher.responded) return@postDelayed
            completeThirdPartyInstallSession(
                sessionWatcher,
                InstallSessionOutcome.Success(sessionWatcher.packageInstallBroadcastReceived),
            )
        }, INSTALL_TIMEOUT_MS)

        handler.post {
            try {
                startActivity(intent)
            } catch (ex: Exception) {
                if (installWatcher === sessionWatcher && !sessionWatcher.responded) {
                    completeThirdPartyInstallSession(
                        sessionWatcher,
                        InstallSessionOutcome.Error("INSTALL_ERROR", ex.message),
                    )
                } else {
                    // Guard failed: session already finished or replaced — still drop cache copies
                    // (success path keeps files until [completeThirdPartyInstallSession] runs).
                    for (releaseFile in releaseFiles) {
                        try { releaseFile.delete() } catch (_: Exception) { }
                    }
                }
            }
        }
    }

    private fun releaseFileToContentUri(releaseFile: File): Uri {
        val providerAuthority = findCacheProviderAuthority()
        val relativePath = releaseFile.path.drop(cacheDir.path.length)
        return Uri.Builder()
            .scheme("content")
            .authority(providerAuthority)
            .encodedPath(relativePath)
            .build()
    }

    private fun findCacheProviderAuthority(): String {
        val packageInfo = packageManager.getPackageInfo(packageName, PackageManager.GET_PROVIDERS)
        val providerInfo = packageInfo.providers?.find {
            it.name == CacheContentProvider::class.java.name
        } ?: throw IllegalStateException("CacheContentProvider not found in manifest")
        return providerInfo.authority
    }

    private fun copyToReleaseCacheUnique(sourceFile: File): File {
        val releasesDir = File(cacheDir, RELEASE_DIR).apply { mkdirs() }
        val uniquePrefix = UUID.randomUUID().toString()
        val releaseFile = File(releasesDir, "${uniquePrefix}_${sourceFile.name}")
        sourceFile.inputStream().use { input ->
            releaseFile.outputStream().use { output ->
                input.copyTo(output)
            }
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
            try {
                val cacheRoot = cacheDir.parentFile!!.parentFile!!
                generateSequence(releaseFile) { it.parentFile }
                    .takeWhile { it != cacheRoot }
                    .forEach { file ->
                        val mode = if (file.isDirectory) 0b001001001 else 0b100100100
                        val oldMode = Os.stat(file.path).st_mode and 0b111111111111
                        val newMode = oldMode or mode
                        if (newMode != oldMode) Os.chmod(file.path, newMode)
                    }
            } catch (_: Exception) { }
        }
        return releaseFile
    }
}
