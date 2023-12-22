package dev.imranr.obtainium

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.Result
import androidx.annotation.NonNull
import android.content.Intent
import android.content.IntentSender
import android.content.pm.IPackageInstaller
import android.content.pm.IPackageInstallerSession
import android.content.pm.PackageInstaller
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.Process
import rikka.shizuku.Shizuku
import rikka.shizuku.Shizuku.OnBinderDeadListener
import rikka.shizuku.Shizuku.OnBinderReceivedListener
import rikka.shizuku.Shizuku.OnRequestPermissionResultListener
import rikka.shizuku.ShizukuBinderWrapper
import dev.imranr.obtainium.util.IIntentSenderAdaptor
import dev.imranr.obtainium.util.IntentSenderUtils
import dev.imranr.obtainium.util.PackageInstallerUtils
import dev.imranr.obtainium.util.ShizukuSystemServerApi
import java.io.IOException
import java.util.concurrent.CountDownLatch
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

    private fun shizukuInstallApk(uri: Uri) {
        val packageInstaller: PackageInstaller
        var session: PackageInstaller.Session? = null
        val cr = contentResolver
        val res = StringBuilder()
        val installerPackageName: String
        var installerAttributionTag: String? = null
        val userId: Int
        val isRoot: Boolean
        try {
            val _packageInstaller: IPackageInstaller =
                ShizukuSystemServerApi.PackageManager_getPackageInstaller()
            isRoot = Shizuku.getUid() == 0

            // the reason for use "com.android.shell" as installer package under adb is that getMySessions will check installer package's owner
            installerPackageName = if (isRoot) packageName else "com.android.shell"
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                installerAttributionTag = attributionTag
            }
            userId = if (isRoot) Process.myUserHandle().hashCode() else 0
            packageInstaller = PackageInstallerUtils.createPackageInstaller(
                _packageInstaller,
                installerPackageName,
                installerAttributionTag,
                userId
            )
            val sessionId: Int
            res.append("createSession: ")
            val params =
                PackageInstaller.SessionParams(PackageInstaller.SessionParams.MODE_FULL_INSTALL)
            var installFlags: Int = PackageInstallerUtils.getInstallFlags(params)
            installFlags =
                installFlags or (0x00000004 /*PackageManager.INSTALL_ALLOW_TEST*/ or 0x00000002) /*PackageManager.INSTALL_REPLACE_EXISTING*/
            PackageInstallerUtils.setInstallFlags(params, installFlags)
            sessionId = packageInstaller.createSession(params)
            res.append(sessionId).append('\n')
            res.append('\n').append("write: ")
            val _session = IPackageInstallerSession.Stub.asInterface(
                ShizukuBinderWrapper(
                    _packageInstaller.openSession(sessionId).asBinder()
                )
            )
            session = PackageInstallerUtils.createSession(_session)
            val name = "apk.apk"
            val `is` = cr.openInputStream(uri)
            val os = session.openWrite(name, 0, -1)
            val buf = ByteArray(8192)
            var len: Int
            try {
                while (`is`!!.read(buf).also { len = it } > 0) {
                    os.write(buf, 0, len)
                    os.flush()
                    session.fsync(os)
                }
            } finally {
                try {
                    `is`!!.close()
                } catch (e: IOException) {
                    e.printStackTrace()
                }
                try {
                    os.close()
                } catch (e: IOException) {
                    e.printStackTrace()
                }
            }
            res.append('\n').append("commit: ")
            val results = arrayOf<Intent?>(null)
            val countDownLatch = CountDownLatch(1)
            val intentSender: IntentSender =
                IntentSenderUtils.newInstance(object : IIntentSenderAdaptor() {
                    override fun send(intent: Intent?) {
                        results[0] = intent
                        countDownLatch.countDown()
                    }
                })
            session.commit(intentSender)
            countDownLatch.await()
            val result = results[0]
            val status =
                result!!.getIntExtra(PackageInstaller.EXTRA_STATUS, PackageInstaller.STATUS_FAILURE)
            val message = result.getStringExtra(PackageInstaller.EXTRA_STATUS_MESSAGE)
            res.append('\n').append("status: ").append(status).append(" (").append(message)
                .append(")")
        } catch (tr: Throwable) {
            tr.printStackTrace()
            res.append(tr)
        } finally {
            if (session != null) {
                try {
                    session.close()
                } catch (tr: Throwable) {
                    res.append(tr)
                }
            }
        }
    }

    private fun installWithShizuku(apkFilePath: String, result: Result) {
        shizukuCheckPermission()
        shizukuInstallApk(Uri.parse("file://$apkFilePath"))
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
