package dev.imranr.obtainium.native_download

import android.os.Handler
import android.os.Looper
import android.content.Context
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
import java.security.KeyStore
import java.security.SecureRandom
import java.security.cert.CertificateFactory
import javax.net.ssl.HostnameVerifier
import javax.net.ssl.HttpsURLConnection
import javax.net.ssl.SSLContext
import javax.net.ssl.SSLSocketFactory
import javax.net.ssl.TrustManager
import javax.net.ssl.TrustManagerFactory
import javax.net.ssl.X509TrustManager
import java.security.cert.X509Certificate
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.Executors
import java.util.concurrent.Future
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.atomic.AtomicLong

class NativeDownloadPlugin : FlutterPlugin, MethodChannel.MethodCallHandler {
    private lateinit var channel: MethodChannel
    private lateinit var applicationContext: Context
    private val executor = Executors.newCachedThreadPool()
    private val cancelled = ConcurrentHashMap<String, AtomicBoolean>()
    private val connections = ConcurrentHashMap<String, HttpURLConnection>()
    private val mainHandler = Handler(Looper.getMainLooper())

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        applicationContext = binding.applicationContext
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

    private class ProgressReporter(
        private val requestId: String,
        private val channel: MethodChannel,
        private val handler: Handler,
    ) {
        private val latestReceived = AtomicLong(0)
        private val lastPosted = AtomicLong(0)
        private val postPending = AtomicBoolean(false)

        fun report(received: Long, total: Long?) {
            latestReceived.set(received)
            val now = System.currentTimeMillis()
            if (now - lastPosted.get() < PROGRESS_INTERVAL_MS ||
                !postPending.compareAndSet(false, true)
            ) return
            handler.post {
                postPending.set(false)
                lastPosted.set(System.currentTimeMillis())
                channel.invokeMethod(
                    "downloadProgress",
                    mapOf(
                        "requestId" to requestId,
                        "received" to latestReceived.get(),
                        "total" to total,
                    ),
                )
            }
        }

        fun complete(total: Long) {
            latestReceived.set(total)
            handler.post {
                postPending.set(false)
                lastPosted.set(System.currentTimeMillis())
                channel.invokeMethod(
                    "downloadProgress",
                    mapOf("requestId" to requestId, "received" to total, "total" to total),
                )
            }
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
                val pinning = arguments["enableCertificatePinning"] as? Boolean ?: false
                val allowInsecure = arguments["allowInsecure"] as? Boolean ?: false
                val completed = if (rangeStart == 0L && rangeSupported &&
                    totalLength != null && totalLength >= PARALLEL_MIN_SIZE
                ) {
                    parallelDownload(
                        id,
                        url,
                        outputPath,
                        headers,
                        totalLength,
                        pinning,
                        allowInsecure,
                        stop,
                        channel,
                    )
                } else false
                if (!completed) download(id, url, outputPath, headers, rangeStart, totalLength, pinning, allowInsecure, stop)
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
        pinning: Boolean,
        allowInsecure: Boolean,
        stop: AtomicBoolean,
        channel: MethodChannel,
    ): Boolean {
        val file = File(outputPath)
        file.parentFile?.mkdirs()
        RandomAccessFile(file, "rw").use { it.setLength(total) }
        val chunk = (total + PARALLEL_DOWNLOADS - 1) / PARALLEL_DOWNLOADS
        val received = AtomicLong(0)
        val progress = ProgressReporter(id, channel, mainHandler)
        val futures = ArrayList<Future<Boolean>>()
        try {
            for (index in 0 until PARALLEL_DOWNLOADS) {
                val start = index * chunk
                val end = minOf(total - 1, start + chunk - 1)
                if (start <= end) futures += executor.submit<Boolean> {
                    downloadRange(
                        id,
                        url,
                        outputPath,
                        headers,
                        start,
                        end,
                        total,
                        pinning,
                        allowInsecure,
                        stop,
                        received,
                        progress,
                    )
                }
            }
            val success = futures.all { it.get() }
            if (!success) {
                file.delete()
            } else {
                progress.complete(total)
            }
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
        start: Long, end: Long, total: Long, pinning: Boolean, allowInsecure: Boolean,
        stop: AtomicBoolean, received: AtomicLong, progress: ProgressReporter,
    ): Boolean {
        val connection = openConnection(url, headers, "bytes=$start-$end", pinning, allowInsecure)
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
                        progress.report(received.addAndGet(count.toLong()), total)
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
        rangeStart: Long, totalLength: Long?, pinning: Boolean, allowInsecure: Boolean,
        stop: AtomicBoolean,
    ) {
        val connection = openConnection(url, headers, if (rangeStart > 0) "bytes=$rangeStart-" else null, pinning, allowInsecure)
        connections[id] = connection
        val progress = ProgressReporter(id, channel, mainHandler)
        try {
            val status = connection.responseCode
            val append = rangeStart > 0 && status == HttpURLConnection.HTTP_PARTIAL
            if (status !in 200..299) throw IllegalStateException("HTTP $status")
            val file = File(outputPath)
            file.parentFile?.mkdirs()
            if (rangeStart > 0 && !append) file.writeBytes(ByteArray(0))
            val expected = totalLength ?: connection.contentLengthLong.takeIf { it > 0 }?.let { if (append) it + rangeStart else it }
            var received = if (append) rangeStart else 0L
            BufferedInputStream(connection.inputStream, BUFFER_SIZE).use { input ->
                BufferedOutputStream(FileOutputStream(file, append), BUFFER_SIZE).use { output ->
                    val buffer = ByteArray(BUFFER_SIZE)
                    while (true) {
                        if (stop.get()) throw InterruptedException()
                        val count = input.read(buffer)
                        if (count < 0) break
                        output.write(buffer, 0, count)
                        received += count
                        progress.report(received, expected)
                    }
                    output.flush()
                }
            }
        } finally {
            connections.remove(id)
            connection.disconnect()
        }
    }

    private fun openConnection(
        initialUrl: String,
        headers: Map<String, String>,
        range: String?,
        pinning: Boolean,
        allowInsecure: Boolean,
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
            configureTls(connection, currentUrl.host, pinning, allowInsecure)
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

    private fun configureTls(
        connection: HttpURLConnection,
        host: String,
        pinning: Boolean,
        allowInsecure: Boolean,
    ) {
        if (connection !is HttpsURLConnection) return
        val certificates = pinnedCertificatesFor(host)
        if (pinning && certificates != null) {
            connection.sslSocketFactory = pinnedSocketFactory(certificates)
            return
        }
        if (allowInsecure) {
            connection.sslSocketFactory = insecureSocketFactory()
            connection.hostnameVerifier = HostnameVerifier { _, _ -> true }
            return
        }
        if (isRuStoreHost(host)) {
            connection.sslSocketFactory = ruStoreSocketFactory()
        }
    }

    private fun isRuStoreHost(host: String): Boolean {
        val rootHost = host.split('.').takeLast(2).joinToString(".")
        return host == "rustore.ru" || rootHost == "rustore.ru"
    }

    private fun pinnedCertificatesFor(host: String): List<String>? {
        val rootHost = host.split('.').takeLast(2).joinToString(".")
        return when {
            host == "github.com" || rootHost == "github.com" -> listOf(
                "sectigo-pub-serv-auth-r46.crt", "sectigo-pub-serv-auth-e46.crt",
                "isrg-root-x1.crt", "isrg-root-x2.crt", "isrg-root-ye.crt", "isrg-root-yr.crt",
            )
            host == "codeberg.org" || rootHost == "codeberg.org" -> listOf(
                "isrg-root-x1.crt", "isrg-root-x2.crt", "isrg-root-ye.crt", "isrg-root-yr.crt",
            )
            host == "gitlab.com" || rootHost == "gitlab.com" -> listOf(
                "sectigo-pub-serv-auth-r46.crt", "sectigo-pub-serv-auth-e46.crt",
            )
            host == "rustore.ru" || rootHost == "rustore.ru" -> listOf(
                "harica-tls-root-2021-rsa.crt", "harica-tls-root-2021-ecc.crt",
                "russian-mintsifry-root.crt",
            )
            else -> null
        }
    }

    private fun pinnedSocketFactory(certificates: List<String>): SSLSocketFactory {
        val certificateFactory = CertificateFactory.getInstance("X.509")
        val keyStore = KeyStore.getInstance(KeyStore.getDefaultType()).apply { load(null, null) }
        certificates.forEachIndexed { index, name ->
            applicationContext.assets.open("flutter_assets/assets/ca-certs/$name").use {
                keyStore.setCertificateEntry("native-download-$index", certificateFactory.generateCertificate(it))
            }
        }
        val trustFactory = TrustManagerFactory.getInstance(TrustManagerFactory.getDefaultAlgorithm())
        trustFactory.init(keyStore)
        return SSLContext.getInstance("TLS").apply {
            init(null, trustFactory.trustManagers, SecureRandom())
        }.socketFactory
    }

    /** Uses Android system CAs plus RuStore's additional government CA. */
    private fun ruStoreSocketFactory(): SSLSocketFactory {
        val certificateFactory = CertificateFactory.getInstance("X.509")
        val extraKeyStore = KeyStore.getInstance(KeyStore.getDefaultType()).apply { load(null, null) }
        applicationContext.assets.open("flutter_assets/assets/ca-certs/russian-mintsifry-root.crt").use {
            extraKeyStore.setCertificateEntry(
                "native-download-rustore",
                certificateFactory.generateCertificate(it),
            )
        }
        val defaultFactory = TrustManagerFactory.getInstance(
            TrustManagerFactory.getDefaultAlgorithm(),
        ).apply { init(null as KeyStore?) }
        val extraFactory = TrustManagerFactory.getInstance(
            TrustManagerFactory.getDefaultAlgorithm(),
        ).apply { init(extraKeyStore) }
        val systemTrust = defaultFactory.trustManagers.filterIsInstance<X509TrustManager>().single()
        val extraTrust = extraFactory.trustManagers.filterIsInstance<X509TrustManager>().single()
        val combinedTrust = object : X509TrustManager {
            override fun checkClientTrusted(chain: Array<X509Certificate>, authType: String) {
                systemTrust.checkClientTrusted(chain, authType)
            }

            override fun checkServerTrusted(chain: Array<X509Certificate>, authType: String) {
                try {
                    systemTrust.checkServerTrusted(chain, authType)
                } catch (_: Exception) {
                    extraTrust.checkServerTrusted(chain, authType)
                }
            }

            override fun getAcceptedIssuers(): Array<X509Certificate> =
                (systemTrust.acceptedIssuers.asList() + extraTrust.acceptedIssuers.asList())
                    .toTypedArray()
        }
        return SSLContext.getInstance("TLS").apply {
            init(null, arrayOf<TrustManager>(combinedTrust), SecureRandom())
        }.socketFactory
    }

    private fun insecureSocketFactory(): SSLSocketFactory {
        val trustAll = arrayOf<TrustManager>(object : X509TrustManager {
            override fun getAcceptedIssuers(): Array<java.security.cert.X509Certificate> = emptyArray()
            override fun checkClientTrusted(chain: Array<java.security.cert.X509Certificate>, authType: String) = Unit
            override fun checkServerTrusted(chain: Array<java.security.cert.X509Certificate>, authType: String) = Unit
        })
        return SSLContext.getInstance("TLS").apply {
            init(null, trustAll, SecureRandom())
        }.socketFactory
    }

    companion object {
        private const val CHANNEL = "dev.imranr.obtainium/native_download"
        private const val BUFFER_SIZE = 256 * 1024
        private const val PARALLEL_DOWNLOADS = 4
        private const val PARALLEL_MIN_SIZE = 8L * 1024 * 1024
        private const val PROGRESS_INTERVAL_MS = 1000L
    }
}
