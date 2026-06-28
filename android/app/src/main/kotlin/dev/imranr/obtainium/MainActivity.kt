package dev.imranr.obtainium

import android.content.Intent
import android.net.Uri
import android.os.Bundle
import android.widget.Toast
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import java.io.File

/**
 * The native surface is intentionally tiny: the capabilities below
 * have no Flutter-plugin equivalent. Everything else (intent dispatch,
 * foreground tracking, install verification, batching) lives in Dart.
 */
class MainActivity : FlutterActivity() {
    private companion object {
        const val EXTERNAL_INSTALL_CHANNEL = "dev.imranr.obtainium/external_install"
        const val PRIVILEGE_INSTALL_FALLBACK_CHANNEL =
            "dev.imranr.obtainium/privilege_install_fallback"
        const val APK_MIME = "application/vnd.android.package-archive"
    }

    private var fallbackHandler: PrivilegeInstallFallbackHandler? = null
    private var pendingShareIntent: Intent? = null

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
        fallbackHandler = PrivilegeInstallFallbackHandler(applicationContext)
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
                else -> result.notImplemented()
            }
        }
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            PRIVILEGE_INSTALL_FALLBACK_CHANNEL,
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "installViaShizuku" -> {
                    val apkUri = call.argument<String>("apkUri")
                    val fakeInstallSource = call.argument<String>("fakeInstallSource") ?: ""
                    if (apkUri == null) {
                        result.error("error", "Missing apkUri", null)
                        return@setMethodCallHandler
                    }
                    CoroutineScope(Dispatchers.Main).launch {
                        try {
                            val code = fallbackHandler!!.installViaShizuku(
                                apkUri,
                                fakeInstallSource,
                            )
                            result.success(code)
                        } catch (e: Exception) {
                            result.error("error", e.message, null)
                        }
                    }
                }
                "checkShizukuPermission" -> {
                    CoroutineScope(Dispatchers.Main).launch {
                        try {
                            val code = fallbackHandler!!.checkShizukuPermissionCode()
                            result.success(code)
                        } catch (e: Exception) {
                            result.error("error", e.message, null)
                        }
                    }
                }
                "getShizukuBackendKind" -> {
                    try {
                        result.success(fallbackHandler!!.getShizukuBackendKind())
                    } catch (e: Exception) {
                        result.error("error", e.message, null)
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
            val match = sharedText?.let { """https?://[^\s]+""".toRegex().find(it) }
            if (match != null) {
                val url = match.value.trimEnd('.', ',', ';', '!', '?', ')')
                intent.apply {
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
