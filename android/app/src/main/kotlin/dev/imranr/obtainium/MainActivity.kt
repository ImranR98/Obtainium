package dev.imranr.obtainium

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.Result
import androidx.annotation.NonNull
import android.content.pm.PackageManager
import android.os.Bundle
import rikka.shizuku.Shizuku
import rikka.shizuku.Shizuku.OnBinderDeadListener
import rikka.shizuku.Shizuku.OnBinderReceivedListener
import rikka.shizuku.Shizuku.OnRequestPermissionResultListener
import com.topjohnwu.superuser.Shell

class MainActivity: FlutterActivity() {
    private val installersChannel = "installers"
    private val SHIZUKU_PERMISSION_REQUEST_CODE = 839  // random num
    private var shizukuBinderAlive = false
    private var shizukuPermissionGranted = false

    private val shizukuBinderReceivedListener = OnBinderReceivedListener {
        if(!Shizuku.isPreV11()) {  // pre 11 unsupported
            shizukuBinderAlive = true
        }
    }

    private val shizukuBinderDeadListener = OnBinderDeadListener { shizukuBinderAlive = false }

    private val shizukuRequestPermissionResultListener = OnRequestPermissionResultListener {
            requestCode: Int, grantResult: Int ->
        if(requestCode == SHIZUKU_PERMISSION_REQUEST_CODE) {
            shizukuPermissionGranted = grantResult == PackageManager.PERMISSION_GRANTED
        }
    }

    private fun shizukuCheckPermission() {
        if(Shizuku.isPreV11()) {
            shizukuPermissionGranted = false
        } else if (Shizuku.checkSelfPermission() == PackageManager.PERMISSION_GRANTED) {
            shizukuPermissionGranted = true
        } else if (Shizuku.shouldShowRequestPermissionRationale()) {  // Deny and don't ask again
            shizukuPermissionGranted = false
        } else {
            Shizuku.requestPermission(SHIZUKU_PERMISSION_REQUEST_CODE)
        }
    }

    private fun installWithShizuku(apkFilePath: String, result: Result) {
        shizukuCheckPermission()
        result.success(0)
    }

    private fun installWithRoot(apkFilePath: String, result: Result) {
        Shell.sh("pm install -r -t " + apkFilePath).submit { out ->
            val builder = StringBuilder()
            for (data in out.getOut()) {
                builder.append(data)
            }
            result.success(if (builder.toString().endsWith("Success")) 0 else 1)
        }
    }

    override fun configureFlutterEngine(@NonNull flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, installersChannel).setMethodCallHandler {
            call, result ->
            var apkFilePath: String? = call.argument("apkFilePath")
            if (call.method == "installWithShizuku") {
                installWithShizuku(apkFilePath.toString(), result)
            } else if (call.method == "installWithRoot") {
                installWithRoot(apkFilePath.toString(), result)
            }
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        Shizuku.addBinderReceivedListener(shizukuBinderReceivedListener)
        Shizuku.addBinderDeadListener(shizukuBinderDeadListener)
        Shizuku.addRequestPermissionResultListener(shizukuRequestPermissionResultListener)
    }

    override fun onDestroy() {
        super.onDestroy()
        Shizuku.removeBinderReceivedListener(shizukuBinderReceivedListener)
        Shizuku.removeBinderDeadListener(shizukuBinderDeadListener)
        Shizuku.removeRequestPermissionResultListener(shizukuRequestPermissionResultListener)
    }
}
