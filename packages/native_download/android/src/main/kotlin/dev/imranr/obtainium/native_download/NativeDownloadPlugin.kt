package dev.imranr.obtainium.native_download

import android.os.Handler
import android.os.Looper
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.BufferedInputStream
import java.io.BufferedOutputStream
import java.io.File
import java.io.FileOutputStream
import java.io.RandomAccessFile
import java.net.HttpURLConnection
import java.net.URI
import java.net.URL
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.Executors
import java.util.concurrent.Future
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.atomic.AtomicLong

class NativeDownloadPlugin : FlutterPlugin, MethodChannel.MethodCallHandler {
    private lateinit var channel: MethodChannel
    private val executor = Executors.newCachedThreadPool()
    private val cancelled = ConcurrentHashMap<String, AtomicBoolean>()
    private val connections = ConcurrentHashMap<String, HttpURLConnection>()
    private val mainHandler = Handler(Looper.getMainLooper())

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel = MethodChannel(binding.binaryMessenger, CHANNEL)
        channel.setMethodCallHandler(this)
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
        cancelled.values.forEach { it.set(true) }
        connections.values.forEach { it.disconnect() }
        cancelled.clear()
        connections.clear()
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "download" -> start(call.arguments as? Map<*, *>, result)
            "cancel" -> {
                call.argument<String>("requestId")?.let { id ->
                    cancelled[id]?.set(true)
                    connections.filterKeys { it == id || it.startsWith("$id:") }
                        .values.forEach { it.disconnect() }
                }
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }

    private fun start(arguments: Map<*, *>?, result: MethodChannel.Result) {
        val id = arguments?.get("requestId") as? String
        val url = arguments?.get("url") as? String
        val outputPath = arguments?.get("outputPath") as? String
        if (id.isNullOrEmpty() || url.isNullOrEmpty() || outputPath.isNullOrEmpty()) {
            result.error("BAD_ARGS", "Missing download arguments", null)
            return
        }
        val stop = AtomicBoolean(false)
        cancelled[id] = stop
        executor.execute {
            try {
                val headers = (arguments["headers"] as? Map<*, *>)
                    ?.mapNotNull { (key, value) ->
                        if (key is String && value is String) key to value else null
                    }?.toMap().orEmpty()
                val rangeStart = (arguments["rangeStart"] as? Number)?.toLong() ?: 0L
                val totalLength = (arguments["totalLength"] as? Number)?.toLong()
                val rangeSupported = arguments["rangeSupported"] as? Boolean ?: false
                val completed = if (rangeStart == 0L && rangeSupported &&
                    totalLength != null && totalLength >= PARALLEL_MIN_SIZE
                ) {
                    parallelDownload(id, url, outputPath, headers, totalLength, stop)
                } else false
                if (!completed) download(id, url, outputPath, headers, rangeStart, totalLength, stop)
                mainHandler.post { result.success(outputPath) }
            } catch (_: InterruptedException) {
                mainHandler.post { result.error("CANCELLED", "Download cancelled", null) }
            } catch (error: Exception) {
                mainHandler.post {
                    result.error("DOWNLOAD_FAILED", error.message ?: error.javaClass.simpleName, null)
                }
            } finally {
                cancelled.remove(id)
            }
        }
    }

    private fun parallelDownload(
        id: String,
        url: String,
        outputPath: String,
        headers: Map<String, String>,
        total: Long,
        stop: AtomicBoolean,
    ): Boolean {
        val file = File(outputPath)
        file.parentFile?.mkdirs()
        RandomAccessFile(file, "rw").use { it.setLength(total) }
        val chunk = (total + PARALLEL_DOWNLOADS - 1) / PARALLEL_DOWNLOADS
        val received = AtomicLong(0)
        val futures = ArrayList<Future<Boolean>>()
        try {
            for (index in 0 until PARALLEL_DOWNLOADS) {
                val start = index * chunk
                val end = minOf(total - 1, start + chunk - 1)
                if (start <= end) futures += executor.submit<Boolean> {
                    downloadRange(id, url, outputPath, headers, start, end, total, stop, received)
                }
            }
            val success = futures.all { it.get() }
            if (!success) file.delete()
            return success
        } catch (_: Exception) {
            stop.set(true)
            futures.forEach { it.cancel(true) }
            file.delete()
            stop.set(false)
            return false
        }
    }

    private fun downloadRange(
        id: String, url: String, outputPath: String, headers: Map<String, String>,
        start: Long, end: Long, total: Long, stop: AtomicBoolean, received: AtomicLong,
    ): Boolean {
        val connection = openConnection(url, headers, "bytes=$start-$end")
        val connectionId = "$id:$start"
        connections[connectionId] = connection
        return try {
            if (connection.responseCode != HttpURLConnection.HTTP_PARTIAL) return false
            RandomAccessFile(outputPath, "rw").use { file ->
                BufferedInputStream(connection.inputStream, BUFFER_SIZE).use { input ->
                    val buffer = ByteArray(BUFFER_SIZE)
                    var position = start
                    while (position <= end) {
                        if (stop.get()) return false
                        val count = input.read(buffer, 0, minOf(BUFFER_SIZE.toLong(), end - position + 1).toInt())
                        if (count < 0) break
                        file.seek(position)
                        file.write(buffer, 0, count)
                        position += count
                        received.addAndGet(count.toLong())
                    }
                    position > end
                }
            }
        } finally {
            connections.remove(connectionId)
            connection.disconnect()
        }
    }

    private fun download(
        id: String, url: String, outputPath: String, headers: Map<String, String>,
        rangeStart: Long, totalLength: Long?, stop: AtomicBoolean,
    ) {
        val connection = openConnection(url, headers, if (rangeStart > 0) "bytes=$rangeStart-" else null)
        connections[id] = connection
        try {
            val status = connection.responseCode
            val append = rangeStart > 0 && status == HttpURLConnection.HTTP_PARTIAL
            if (status !in 200..299) throw IllegalStateException("HTTP $status")
            val file = File(outputPath)
            file.parentFile?.mkdirs()
            if (rangeStart > 0 && !append) file.writeBytes(ByteArray(0))
            val expected = totalLength ?: connection.contentLengthLong.takeIf { it > 0 }?.let { if (append) it + rangeStart else it }
            var received = if (append) rangeStart else 0L
            var lastProgress = 0L
            BufferedInputStream(connection.inputStream, BUFFER_SIZE).use { input ->
                BufferedOutputStream(FileOutputStream(file, append), BUFFER_SIZE).use { output ->
                    val buffer = ByteArray(BUFFER_SIZE)
                    while (true) {
                        if (stop.get()) throw InterruptedException()
                        val count = input.read(buffer)
                        if (count < 0) break
                        output.write(buffer, 0, count)
                        received += count
                        val now = System.currentTimeMillis()
                        if (now - lastProgress >= 500) {
                            val progressReceived = received
                            mainHandler.post {
                                channel.invokeMethod("downloadProgress", mapOf("requestId" to id, "received" to progressReceived, "total" to expected))
                            }
                            lastProgress = now
                        }
                    }
                    output.flush()
                }
            }
        } finally {
            connections.remove(id)
            connection.disconnect()
        }
    }

    private fun openConnection(initialUrl: String, headers: Map<String, String>, range: String?): HttpURLConnection {
        var currentUrl = URI(initialUrl)
        var currentHeaders = headers.toMutableMap()
        repeat(10) {
            val connection = (currentUrl.toURL().openConnection() as HttpURLConnection).apply {
                instanceFollowRedirects = false
                useCaches = false
                connectTimeout = 30_000
                readTimeout = 30_000
                requestMethod = "GET"
                currentHeaders.forEach { (key, value) -> setRequestProperty(key, value) }
                setRequestProperty("Accept-Encoding", "identity")
                if (range != null) setRequestProperty("Range", range)
            }
            val status = connection.responseCode
            if (status !in 300..399) return connection
            val location = connection.getHeaderField("Location")
            connection.disconnect()
            if (location.isNullOrBlank()) throw IllegalStateException("Redirect without Location")
            val nextUrl = currentUrl.resolve(location)
            if (nextUrl.scheme != currentUrl.scheme || nextUrl.host != currentUrl.host) {
                currentHeaders = currentHeaders.filterKeys {
                    !it.equals("Authorization", true) && !it.equals("Cookie", true) && !it.equals("Proxy-Authorization", true)
                }.toMutableMap()
            }
            currentUrl = nextUrl
        }
        throw IllegalStateException("Too many redirects")
    }

    companion object {
        private const val CHANNEL = "dev.imranr.obtainium/native_download"
        private const val BUFFER_SIZE = 256 * 1024
        private const val PARALLEL_DOWNLOADS = 4
        private const val PARALLEL_MIN_SIZE = 8L * 1024 * 1024
    }
}
