package dev.imranr.obtainium

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch

class MainActivity : FlutterActivity() {
    private var fallbackHandler: PrivilegeInstallFallbackHandler? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        fallbackHandler = PrivilegeInstallFallbackHandler(applicationContext)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "dev.imranr.obtainium/privilege_install_fallback",
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
    }
}
