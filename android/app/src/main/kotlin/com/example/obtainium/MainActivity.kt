package dev.imranr.obtainium

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.Result
import androidx.annotation.NonNull
import com.topjohnwu.superuser.Shell

class MainActivity: FlutterActivity() {
    private val installersChannel = "installers"

    private fun installWithRoot(apkFilePath: String, result: Result) {
        Shell.sh("pm install -r -t " + apkFilePath).submit { out ->
            val builder = StringBuilder()
            for (data in out.getOut()) {
                builder.append(data)
            }
            result.success(if (builder.toString().endsWith("Success")) 0 else 1)
        }
    }

    private fun installWithShizuku(apkFilePath: String, result: Result) {
        val a = 1
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
}
