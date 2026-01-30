package dev.imranr.obtainium

import android.content.Intent
import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.ConcurrentLinkedQueue

class MainActivity : FlutterActivity() {
    private val CHANNEL = "dev.imranr.obtainium/intent"
    private val pendingPackages = ConcurrentLinkedQueue<String>()

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
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

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "getPendingPackageName" -> {
                        // Return next pending package name or null if none.
                        val pkg = pendingPackages.poll()
                        result.success(pkg)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun handleIntent(intent: Intent?) {
        intent?.let {
            if (it.action == "android.intent.action.SHOW_APP_INFO") {
                val packageName = it.getStringExtra("android.intent.extra.PACKAGE_NAME")
                packageName?.let {
                    // Queue it so Dart can pick it up when ready.
                    pendingPackages.add(packageName)
                }
            }
        }
    }
}