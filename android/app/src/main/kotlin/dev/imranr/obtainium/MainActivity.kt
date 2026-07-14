package dev.imranr.obtainium

import android.content.Intent
import android.net.Uri
import android.os.Bundle
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
    }

    private var pendingShareIntent: Intent? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        intent?.let {
            setIntent(markTrustedIfPrivileged(transformShareIntent(it)))
        }
        super.onCreate(savedInstanceState)
    }

    override fun onNewIntent(intent: Intent) {
        val newIntent = markTrustedIfPrivileged(transformShareIntent(intent))
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
                else -> result.notImplemented()
            }
        }
        pendingShareIntent?.let {
            super.onNewIntent(it)
            pendingShareIntent = null
        }
    }

    /**
     * One entry per app able to handle an APK install intent. Apps that expose
     * several install-capable activities are collapsed to a single entry (the
     * first match, preferring ACTION_VIEW), so the picker shows each app once.
     */
    private fun listInstallTargets(): List<Map<String, String>> {
        val seenPackages = HashSet<String>()
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
                if (!seenPackages.add(pkg)) continue
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

    /**
     * Marks obtainium:// intents from privileged callers (ADB shell, system)
     * with confirmedBy=system so the Dart side can distinguish trusted
     * launches from browser-based phishing links.  A null referrer means
     * the activity was launched by the ActivityManager directly (e.g.
     * `adb shell am start`) — regular apps and browsers always set a
     * non-null referrer.
     */
    private fun markTrustedIfPrivileged(intent: Intent): Intent {
        val uri = intent.data ?: return intent
        if (uri.scheme != "obtainium") return intent
        if (referrer != null) return intent

        val builder = uri.buildUpon()
        builder.appendQueryParameter("confirmedBy", "system")
        intent.data = builder.build()
        return intent
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
