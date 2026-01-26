package dev.imranr.obtainium

import android.content.Intent
import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val CHANNEL = "dev.imranr.obtainium/intent"
    private var pendingPackageName: String? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        handleIntent(intent)
        setupMethodChannel()
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        handleIntent(intent)
    }

    private fun setupMethodChannel() {
        flutterEngine?.dartExecutor?.binaryMessenger?.let { messenger ->
            MethodChannel(messenger, CHANNEL).setMethodCallHandler { call, result ->
                when (call.method) {
                    "getPendingPackageName" -> {
                        val packageName = pendingPackageName
                        pendingPackageName = null
                        result.success(packageName)
                    }
                    else -> result.notImplemented()
                }
            }
        }
    }

    private fun handleIntent(intent: Intent?) {
        intent?.let {
            if (it.action == "android.intent.action.SHOW_APP_INFO") {
                val packageName = it.getStringExtra("android.intent.extra.PACKAGE_NAME")
                packageName?.let {
                    pendingPackageName = packageName
                    flutterEngine?.dartExecutor?.binaryMessenger?.let { messenger ->
                        MethodChannel(messenger, CHANNEL).invokeMethod("showAppInfo", packageName)
                    }
                    pendingPackageName = null
                }
            }
        }
    }
}