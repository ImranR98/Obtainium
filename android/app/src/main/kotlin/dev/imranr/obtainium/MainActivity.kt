package dev.imranr.obtainium

import android.app.Activity
import android.content.BroadcastReceiver
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.net.Uri
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.widget.Toast
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

/**
 * The native surface is intentionally tiny: the capabilities below 
 * have no Flutter-plugin equivalent. Everything else (intent dispatch, 
 * foreground tracking, install verification, batching) lives in Dart.
 */
class MainActivity : FlutterActivity() {
    private companion object {
        const val EXTERNAL_INSTALL_CHANNEL = "dev.imranr.obtainium/external_install"
        const val APK_MIME = "application/vnd.android.package-archive"

        /** Request code for tracked external-installer launches. */
        const val THIRD_PARTY_INSTALL_REQUEST_CODE = 5108

        /** Hard ceiling for a tracked external install (5 minutes). */
        const val INSTALL_TIMEOUT_MS = 300_000L

        /**
         * After the installer's activity is gone (or focus returns) and no
         * package-change broadcast arrived, keep waiting this long before
         * treating the install as cancelled.
         */
        const val CANCEL_GRACE_MS = 30_000L

        /**
         * Extra set by installers that support [Intent.EXTRA_RETURN_RESULT] on
         * failure; holds a PackageManager INSTALL_FAILED_* code. The constant
         * is hidden, so the raw key is used.
         */
        const val EXTRA_INSTALL_RESULT = "android.intent.extra.INSTALL_RESULT"
    }

    private var pendingShareIntent: Intent? = null

    private val installHandler = Handler(Looper.getMainLooper())
    private var installWatcher: InstallWatcher? = null

    /**
     * Tracks one external-installer handoff and resolves the pending
     * [MethodChannel.Result] on the first conclusive signal:
     *  - the installer's own result (RESULT_OK/RESULT_FIRST_USER),
     *  - a PACKAGE_ADDED/PACKAGE_REPLACED broadcast for the expected package,
     *  - the cancel grace after the installer activity is gone,
     *  - the hard timeout.
     */
    private inner class InstallWatcher(
        private val methodResult: MethodChannel.Result,
        private val expectedPackageName: String,
    ) {
        var responded = false
        var focusLost = false
        private var graceScheduled = false

        val receiver = object : BroadcastReceiver() {
            override fun onReceive(context: Context?, intent: Intent?) {
                val changedPackage = intent?.data?.schemeSpecificPart ?: return
                if (changedPackage != expectedPackageName) return
                complete(installed = true, errorCode = null)
            }
        }

        private val graceRunnable = Runnable {
            complete(installed = false, errorCode = null)
        }

        fun scheduleCancelGrace() {
            if (responded || graceScheduled) return
            graceScheduled = true
            installHandler.postDelayed(graceRunnable, CANCEL_GRACE_MS)
        }

        /** Drops a pending grace: the user went back to the installer. */
        fun cancelGrace() {
            if (!graceScheduled) return
            graceScheduled = false
            installHandler.removeCallbacks(graceRunnable)
        }

        fun complete(installed: Boolean, errorCode: Int?) {
            if (responded) return
            responded = true
            if (installWatcher === this) {
                installWatcher = null
            }
            installHandler.removeCallbacksAndMessages(null)
            try {
                unregisterReceiver(receiver)
            } catch (_: Exception) {
            }
            methodResult.success(
                mapOf(
                    "installed" to installed,
                    "errorCode" to errorCode,
                ),
            )
        }

        fun completeError(code: String, message: String?) {
            if (responded) return
            responded = true
            if (installWatcher === this) {
                installWatcher = null
            }
            installHandler.removeCallbacksAndMessages(null)
            try {
                unregisterReceiver(receiver)
            } catch (_: Exception) {
            }
            methodResult.error(code, message, null)
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        intent?.let {
            setIntent(transformShareIntent(it))
        }
        super.onCreate(savedInstanceState)
    }

    override fun onNewIntent(intent: Intent) {
        val newIntent = transformShareIntent(intent)
        setIntent(newIntent)
        try {
            super.onNewIntent(newIntent)
        } catch (_: Exception) {
            pendingShareIntent = newIntent
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
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
                        } catch (e: Exception) {
                            result.error("URI_FAILED", e.message, null)
                        }
                    }
                }
                "launchInstallIntent" -> {
                    val uri = call.argument<String>("uri")
                    val type = call.argument<String>("type") ?: APK_MIME
                    val targetPackage = call.argument<String>("package")
                    val targetActivity = call.argument<String>("activity")
                    val expectedPackageName = call.argument<String>("expectedPackageName")
                    if (uri.isNullOrEmpty() || expectedPackageName.isNullOrEmpty()) {
                        result.error(
                            "BAD_ARGS",
                            "Missing uri or expectedPackageName",
                            null,
                        )
                    } else {
                        launchInstallIntent(
                            uri,
                            type,
                            targetPackage,
                            targetActivity,
                            expectedPackageName,
                            result,
                        )
                    }
                }
                else -> result.notImplemented()
            }
        }
        pendingShareIntent?.let {
            super.onNewIntent(it)
            pendingShareIntent = null
        }
    }

    /**
     * Launches the chosen installer and resolves [methodResult] once the
     * install outcome is known. [Intent.EXTRA_RETURN_RESULT] asks installers
     * that support it to report their own result; FLAG_ACTIVITY_NEW_TASK is
     * intentionally omitted because it makes Android deliver a synthetic
     * immediate RESULT_CANCELED for startActivityForResult instead of the
     * installer's real result.
     */
    @Suppress("DEPRECATION")
    private fun launchInstallIntent(
        uri: String,
        type: String,
        targetPackage: String?,
        targetActivity: String?,
        expectedPackageName: String,
        methodResult: MethodChannel.Result,
    ) {
        // Only one tracked handoff at a time; settle a stale one first.
        installWatcher?.complete(installed = false, errorCode = null)

        val intent = Intent(Intent.ACTION_VIEW).apply {
            setDataAndType(Uri.parse(uri), type)
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            putExtra(Intent.EXTRA_RETURN_RESULT, true)
            if (!targetPackage.isNullOrEmpty() && !targetActivity.isNullOrEmpty()) {
                component = ComponentName(targetPackage, targetActivity)
            }
        }
        val watcher = InstallWatcher(methodResult, expectedPackageName)
        installWatcher = watcher
        registerReceiver(
            watcher.receiver,
            IntentFilter().apply {
                addAction(Intent.ACTION_PACKAGE_ADDED)
                addAction(Intent.ACTION_PACKAGE_REPLACED)
                addDataScheme("package")
            },
        )
        installHandler.postDelayed(
            { watcher.complete(installed = false, errorCode = null) },
            INSTALL_TIMEOUT_MS,
        )
        try {
            startActivityForResult(intent, THIRD_PARTY_INSTALL_REQUEST_CODE)
        } catch (e: Exception) {
            watcher.completeError("INSTALL_ERROR", e.message)
        }
    }

    @Suppress("DEPRECATION")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        if (requestCode == THIRD_PARTY_INSTALL_REQUEST_CODE) {
            val watcher = installWatcher
            if (watcher != null && !watcher.responded) {
                when (resultCode) {
                    Activity.RESULT_OK -> watcher.complete(
                        installed = true,
                        errorCode = null,
                    )
                    Activity.RESULT_FIRST_USER -> watcher.complete(
                        installed = false,
                        errorCode = data?.getIntExtra(EXTRA_INSTALL_RESULT, -1),
                    )
                    // RESULT_CANCELED is also what installers that do not
                    // implement EXTRA_RETURN_RESULT produce on finish, and
                    // singleInstance installers (e.g. InstallerX-Revived)
                    // return it immediately. Only treat it as "the installer
                    // is gone" once it actually took focus; otherwise wait for
                    // the package broadcast or the hard timeout.
                    else -> if (watcher.focusLost) watcher.scheduleCancelGrace()
                }
            }
            return
        }
        super.onActivityResult(requestCode, resultCode, data)
    }

    override fun onWindowFocusChanged(hasFocus: Boolean) {
        super.onWindowFocusChanged(hasFocus)
        val watcher = installWatcher ?: return
        if (watcher.responded) return
        if (!hasFocus) {
            watcher.focusLost = true
            // The user went back to the installer; a pending grace no longer
            // means the install is finished.
            watcher.cancelGrace()
        } else if (watcher.focusLost) {
            // The installer is no longer in front; give a package-change
            // broadcast a short grace before treating the install as cancelled.
            watcher.scheduleCancelGrace()
        }
    }

    override fun onDestroy() {
        installWatcher?.complete(installed = false, errorCode = null)
        super.onDestroy()
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
                targets.add(mapOf("package" to pkg, "activity" to activity))
            }
        }
        return targets
    }

    /** Exposes a downloaded file through the app's FileProvider as a content:// URI. */
    private fun contentUriForFile(path: String): String {
        val uri = FileProvider.getUriForFile(this, packageName, File(path))
        return uri.toString()
    }

    private fun transformShareIntent(intent: Intent): Intent {
        if (intent.action == Intent.ACTION_SEND && intent.type?.startsWith("text/") == true) {
            val sharedText = intent.getStringExtra(Intent.EXTRA_TEXT)
            val match = sharedText?.let { """https?://[^\s]+""".toRegex().find(it) } // Extract URL from shared text
            if (match != null) {
                val url = match.value.trimEnd('.', ',', ';', '!', '?', ')') // Trim potential trailing punctuation
                intent.apply { // "Redirect" the intent
                    action = Intent.ACTION_VIEW
                    data = Uri.parse("obtainium://add/${Uri.encode(url)}")
                }
            } else {
                Toast.makeText(this, "No URL found in shared text", Toast.LENGTH_SHORT).show()
            }
        }
        return intent
    }
}
