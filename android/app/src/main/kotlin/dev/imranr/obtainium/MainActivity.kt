package dev.imranr.obtainium

import android.content.Intent
import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.ConcurrentLinkedQueue

class MainActivity : FlutterActivity() {
    private val channel = "dev.imranr.obtainium/intent"
    private val pendingPackages = ConcurrentLinkedQueue<String>()

    // Whether Dart has signalled it's ready to receive pushed intents
    @Volatile
    private var dartIsReady = false

    // Save the latest messenger for invoking methods when Dart is ready
    private var lastBinaryMessenger: io.flutter.plugin.common.BinaryMessenger? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // Capture initial intent (cold start)
        handleIntent(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        handleIntent(intent)
    }

    // Register method channel when the FlutterEngine is configured (embedding v2 recommended pattern).
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        lastBinaryMessenger = flutterEngine.dartExecutor.binaryMessenger

        val channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channel)
        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "getPendingPackageName" -> {
                    // Return next pending package name or null if none.
                    val pkg = pendingPackages.poll()
                    result.success(pkg)
                }

                "readyForIntents" -> {
                    // Dart is ready to receive pushed intents. Drain queue by invoking showAppInfo.
                    dartIsReady = true
                    drainQueueToDart()
                    result.success(true)
                }

                else -> result.notImplemented()
            }
        }

        // If Dart later registers, we still have the messenger for invokes
        if (dartIsReady) {
            drainQueueToDart()
        }
    }

    private fun handleIntent(intent: Intent?) {
        intent?.let {
            if (it.action == "android.intent.action.SHOW_APP_INFO") {
                val packageName = it.getStringExtra("android.intent.extra.PACKAGE_NAME")
                packageName?.let {
                    if (dartIsReady && lastBinaryMessenger != null) {
                        // Deliver immediately to Dart
                        try {
                            MethodChannel(lastBinaryMessenger!!, channel)
                                .invokeMethod("showAppInfo", packageName)
                        } catch (_: Exception) {
                            // If invoke fails, fallback to queueing
                            pendingPackages.add(packageName)
                        }
                    } else {
                        // Queue it so Dart can pick it up when ready.
                        pendingPackages.add(packageName)
                    }
                }
            }
        }
    }

    private fun drainQueueToDart() {
        val messenger = lastBinaryMessenger ?: return
        val channel = MethodChannel(messenger, channel)
        var pkg = pendingPackages.poll()
        while (pkg != null) {
            try {
                channel.invokeMethod("showAppInfo", pkg)
            } catch (_: Exception) {
                // If invoke fails, requeue and stop draining to avoid busy loop
                pendingPackages.add(pkg)
                break
            }
            pkg = pendingPackages.poll()
        }
    }
}