package dev.imranr.obtainium

import android.os.Handler
import android.os.Looper
import io.flutter.embedding.engine.FlutterEngine
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

/** Native downloader shared by the foreground and WorkManager Flutter engines. */
object NativeDownloadChannel {
    private const val CHANNEL = "dev.imranr.obtainium/native_download"
    private const val PARALLEL_DOWNLOADS = 4
    private const val PARALLEL_DOWNLOAD_MIN_SIZE = 8L * 1024 * 1024
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
                        connections.filterKeys { it == requestId || it.startsWith("$requestId:") }
                            .values.forEach { it.disconnect() }
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
                val rangeSupported = arguments["rangeSupported"] as? Boolean ?: false
                val channel = MethodChannel(engine.dartExecutor.binaryMessenger, CHANNEL)
                if (rangeStart == 0L && totalLength != null &&
                    totalLength >= PARALLEL_DOWNLOAD_MIN_SIZE &&
                    rangeSupported &&
                    tryParallelDownload(requestId, url, outputPath, headers, totalLength, stop, channel)
                ) {
                    // Completed by the parallel range workers.
                } else {
                    download(requestId, url, outputPath, headers, rangeStart, totalLength, stop, channel)
                }
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

    private fun tryParallelDownload(
        requestId: String,
        url: String,
        outputPath: String,
        headers: Map<String, String>,
        totalLength: Long,
        stop: AtomicBoolean,
        channel: MethodChannel,
    ): Boolean {
        val file = File(outputPath)
        file.parentFile?.mkdirs()
        RandomAccessFile(file, "rw").use { it.setLength(totalLength) }
        val chunkSize = (totalLength + PARALLEL_DOWNLOADS - 1) / PARALLEL_DOWNLOADS
        val futures = ArrayList<Future<Boolean>>(PARALLEL_DOWNLOADS)
        val received = AtomicLong(0L)
        val lastProgress = AtomicLong(0L)
        try {
            for (index in 0 until PARALLEL_DOWNLOADS) {
                val start = index * chunkSize
                val end = minOf(totalLength - 1, start + chunkSize - 1)
                if (start > end) continue
                futures += executor.submit<Boolean> {
                    downloadRange(
                        requestId,
                        url,
                        outputPath,
                        headers,
                        start,
                        end,
                        totalLength,
                        stop,
                        channel,
                        received,
                        lastProgress,
                    )
                }
            }
            val completed = futures.all { it.get() }
            if (!completed) {
                val externallyCancelled = stop.get()
                file.delete()
                if (!externallyCancelled) stop.set(false)
            }
            return completed
        } catch (_: Exception) {
            val externallyCancelled = stop.get()
            stop.set(true)
            futures.forEach { it.cancel(true) }
            file.delete()
            if (!externallyCancelled) stop.set(false)
            return false
        } finally {
            if (stop.get()) file.delete()
        }
    }

    private fun downloadRange(
        requestId: String,
        url: String,
        outputPath: String,
        headers: Map<String, String>,
        start: Long,
        end: Long,
        totalLength: Long,
        stop: AtomicBoolean,
        channel: MethodChannel,
        received: AtomicLong,
        lastProgress: AtomicLong,
    ): Boolean {
        val connection = openConnection(url, headers, "bytes=$start-$end")
        val connectionId = "$requestId:$start"
        connections[connectionId] = connection
        return try {
            if (connection.responseCode != HttpURLConnection.HTTP_PARTIAL) return false
            RandomAccessFile(outputPath, "rw").use { file ->
                BufferedInputStream(connection.inputStream, 256 * 1024).use { input ->
                    val buffer = ByteArray(256 * 1024)
                    var position = start
                    while (position <= end) {
                        if (stop.get()) return false
                        val count = input.read(buffer, 0, minOf(buffer.size.toLong(), end - position + 1).toInt())
                        if (count < 0) break
                        file.seek(position)
                        file.write(buffer, 0, count)
                        position += count
                        val receivedNow = received.addAndGet(count.toLong())
                        val now = System.currentTimeMillis()
                        val previousProgress = lastProgress.get()
                        if (now - previousProgress >= 1000 &&
                            lastProgress.compareAndSet(previousProgress, now)
                        ) {
                            mainHandler.post {
                                channel.invokeMethod("downloadProgress", mapOf(
                                    "requestId" to requestId,
                                    "received" to receivedNow,
                                    "total" to totalLength,
                                ))
                            }
                        }
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
        requestId: String,
        url: String,
        outputPath: String,
        headers: Map<String, String>,
        rangeStart: Long,
        totalLength: Long?,
        stop: AtomicBoolean,
        channel: MethodChannel,
    ) {
        val connection = openConnection(url, headers, null)
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

    private fun openConnection(
        initialUrl: String,
        headers: Map<String, String>,
        range: String?,
    ): HttpURLConnection {
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
                    !it.equals("Authorization", ignoreCase = true) &&
                        !it.equals("Cookie", ignoreCase = true) &&
                        !it.equals("Proxy-Authorization", ignoreCase = true)
                }.toMutableMap()
            }
            currentUrl = nextUrl
        }
        throw IllegalStateException("Too many redirects")
    }
}
