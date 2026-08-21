package dev.imranr.obtainium

import android.os.Handler
import android.os.Looper
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.BufferedInputStream
import java.io.BufferedOutputStream
import java.io.File
import java.io.FileOutputStream
import java.net.HttpURLConnection
import java.net.URL
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicBoolean

/** Native downloader shared by the foreground and WorkManager Flutter engines. */
object NativeDownloadChannel {
    private const val CHANNEL = "dev.imranr.obtainium/native_download"
    private val executor = Executors.newCachedThreadPool()
    private val cancelled = ConcurrentHashMap<String, AtomicBoolean>()
    private val connections = ConcurrentHashMap<String, HttpURLConnection>()
    private val mainHandler = Handler(Looper.getMainLooper())

    @JvmStatic
    fun register(engine: FlutterEngine) {
        MethodChannel(engine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "download" -> start(call.arguments as? Map<*, *>, result, engine)
                "cancel" -> {
                    (call.argument<String>("requestId"))?.let { requestId ->
                        cancelled[requestId]?.set(true)
                        connections[requestId]?.disconnect()
                    }
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun start(
        arguments: Map<*, *>?,
        result: MethodChannel.Result,
        engine: FlutterEngine,
    ) {
        val requestId = arguments?.get("requestId") as? String
        val url = arguments?.get("url") as? String
        val outputPath = arguments?.get("outputPath") as? String
        if (requestId.isNullOrEmpty() || url.isNullOrEmpty() || outputPath.isNullOrEmpty()) {
            result.error("BAD_ARGS", "Missing native download arguments", null)
            return
        }
        val stop = AtomicBoolean(false)
        cancelled[requestId] = stop
        executor.execute {
            try {
                val headers = (arguments["headers"] as? Map<*, *>)
                    ?.mapNotNull { (key, value) ->
                        if (key is String && value is String) key to value else null
                    }?.toMap().orEmpty()
                val rangeStart = (arguments["rangeStart"] as? Number)?.toLong() ?: 0L
                val totalLength = (arguments["totalLength"] as? Number)?.toLong()
                download(
                    requestId, url, outputPath, headers, rangeStart, totalLength, stop,
                    MethodChannel(engine.dartExecutor.binaryMessenger, CHANNEL),
                )
                mainHandler.post { result.success(outputPath) }
            } catch (_: InterruptedException) {
                mainHandler.post { result.error("CANCELLED", "Download cancelled", null) }
            } catch (error: Exception) {
                mainHandler.post {
                    result.error("DOWNLOAD_FAILED", error.message ?: error.javaClass.simpleName, null)
                }
            } finally {
                cancelled.remove(requestId)
            }
        }
    }

    private fun download(
        requestId: String,
        url: String,
        outputPath: String,
        headers: Map<String, String>,
        rangeStart: Long,
        totalLength: Long?,
        stop: AtomicBoolean,
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
        connections[requestId] = connection
        try {
            val status = connection.responseCode
            val append = rangeStart > 0 && status == HttpURLConnection.HTTP_PARTIAL
            if (status !in 200..299) throw IllegalStateException("HTTP $status")
            val file = File(outputPath)
            file.parentFile?.mkdirs()
            if (rangeStart > 0 && !append) file.writeBytes(ByteArray(0))
            val expected = totalLength ?: connection.contentLengthLong.takeIf { it > 0 }?.let {
                if (append) it + rangeStart else it
            }
            var received = if (append) rangeStart else 0L
            var lastProgress = 0L
            BufferedInputStream(connection.inputStream, 256 * 1024).use { input ->
                BufferedOutputStream(FileOutputStream(file, append), 256 * 1024).use { output ->
                    val buffer = ByteArray(256 * 1024)
                    while (true) {
                        if (stop.get()) throw InterruptedException()
                        val count = input.read(buffer)
                        if (count < 0) break
                        output.write(buffer, 0, count)
                        received += count
                        val now = System.currentTimeMillis()
                        if (now - lastProgress >= 500) {
                            mainHandler.post {
                                channel.invokeMethod("downloadProgress", mapOf(
                                    "requestId" to requestId,
                                    "received" to received,
                                    "total" to expected,
                                ))
                            }
                            lastProgress = now
                        }
                    }
                    output.flush()
                }
            }
        } finally {
            connections.remove(requestId)
            connection.disconnect()
        }
    }
}
