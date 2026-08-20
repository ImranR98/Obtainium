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
import java.io.BufferedInputStream
import java.io.BufferedOutputStream
import java.io.FileOutputStream
import java.net.HttpURLConnection
import java.net.URL
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicBoolean

/**
 * The native surface is intentionally tiny: the capabilities below
 * have no Flutter-plugin equivalent. Everything else (intent dispatch,
 * foreground tracking, install verification, batching) lives in Dart.
 */
class MainActivity : FlutterActivity() {
    private companion object {
        const val EXTERNAL_INSTALL_CHANNEL = "dev.imranr.obtainium/external_install"
        const val DOWNLOAD_CHANNEL = "dev.imranr.obtainium/native_download"
        const val APK_MIME = "application/vnd.android.package-archive"
    }

    private var pendingShareIntent: Intent? = null
    private val downloadExecutor = Executors.newCachedThreadPool()
    private val cancelledDownloads = ConcurrentHashMap<String, AtomicBoolean>()
    private val activeDownloadConnections = ConcurrentHashMap<String, HttpURLConnection>()

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
                else -> result.notImplemented()
            }
        }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, DOWNLOAD_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "download" -> startNativeDownload(call.arguments as Map<*, *>, result, flutterEngine)
                    "cancel" -> {
                        call.argument<String>("requestId")?.let {
                            cancelledDownloads[it]?.set(true)
                            activeDownloadConnections[it]?.disconnect()
                        }
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
        pendingShareIntent?.let {
            super.onNewIntent(it)
            pendingShareIntent = null
        }
    }

    private fun startNativeDownload(
        arguments: Map<*, *>,
        result: MethodChannel.Result,
        engine: FlutterEngine,
    ) {
        val requestId = arguments["requestId"] as? String
        val url = arguments["url"] as? String
        val outputPath = arguments["outputPath"] as? String
        if (requestId.isNullOrEmpty() || url.isNullOrEmpty() || outputPath.isNullOrEmpty()) {
            result.error("BAD_ARGS", "Missing native download arguments", null)
            return
        }
        val cancelled = AtomicBoolean(false)
        cancelledDownloads[requestId] = cancelled
        downloadExecutor.execute {
            try {
                val headers = (arguments["headers"] as? Map<*, *>)
                    ?.mapNotNull { (key, value) ->
                        if (key is String && value is String) key to value else null
                    }?.toMap().orEmpty()
                val rangeStart = (arguments["rangeStart"] as? Number)?.toLong() ?: 0L
                val totalLength = (arguments["totalLength"] as? Number)?.toLong()
                downloadWithHttpUrlConnection(
                    requestId, url, outputPath, headers, rangeStart, totalLength,
                    cancelled, MethodChannel(engine.dartExecutor.binaryMessenger, DOWNLOAD_CHANNEL),
                )
                result.success(outputPath)
            } catch (e: InterruptedException) {
                result.error("CANCELLED", "Download cancelled", null)
            } catch (e: Exception) {
                result.error("DOWNLOAD_FAILED", e.message ?: e.javaClass.simpleName, null)
            } finally {
                cancelledDownloads.remove(requestId)
            }
        }
    }

    private fun downloadWithHttpUrlConnection(
        requestId: String,
        url: String,
        outputPath: String,
        headers: Map<String, String>,
        rangeStart: Long,
        totalLength: Long?,
        cancelled: AtomicBoolean,
        channel: MethodChannel,
    ) {
        val connection = (URL(url).openConnection() as HttpURLConnection).apply {
            instanceFollowRedirects = true
            useCaches = false
            connectTimeout = 30_000
            readTimeout = 30_000
            requestMethod = "GET"
            headers.forEach { (key, value) -> setRequestProperty(key, value) }
            setRequestProperty("Accept-Encoding", "identity")
            if (rangeStart > 0) setRequestProperty("Range", "bytes=$rangeStart-")
        }
        activeDownloadConnections[requestId] = connection
        try {
            val status = connection.responseCode
            val appending = rangeStart > 0 && status == HttpURLConnection.HTTP_PARTIAL
            if (status !in 200..299) throw IllegalStateException("HTTP $status")
            if (rangeStart > 0 && !appending) File(outputPath).writeBytes(ByteArray(0))
            val file = File(outputPath)
            file.parentFile?.mkdirs()
            val expected = totalLength ?: connection.contentLengthLong.takeIf { it > 0 }?.let {
                if (appending) it + rangeStart else it
            }
            var received = if (appending) rangeStart else 0L
            var lastProgress = 0L
            BufferedInputStream(connection.inputStream, 256 * 1024).use { input ->
                BufferedOutputStream(FileOutputStream(file, appending), 256 * 1024).use { output ->
                    val buffer = ByteArray(256 * 1024)
                    while (true) {
                        if (cancelled.get()) throw InterruptedException()
                        val count = input.read(buffer)
                        if (count < 0) break
                        output.write(buffer, 0, count)
                        received += count
                        val now = System.currentTimeMillis()
                        if (now - lastProgress >= 500) {
                            channel.invokeMethod("downloadProgress", mapOf(
                                "requestId" to requestId,
                                "received" to received,
                                "total" to expected,
                            ))
                            lastProgress = now
                        }
                    }
                    output.flush()
                }
            }
        } finally {
            activeDownloadConnections.remove(requestId)
            connection.disconnect()
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
