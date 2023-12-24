package dev.imranr.obtainium

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
import androidx.annotation.NonNull
import com.topjohnwu.superuser.Shell
import dev.imranr.obtainium.util.IIntentSenderAdaptor
import dev.imranr.obtainium.util.IntentSenderUtils
import dev.imranr.obtainium.util.PackageInstallerUtils
import dev.imranr.obtainium.util.ShizukuSystemServerApi
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.Result
import java.io.IOException
import java.util.concurrent.CountDownLatch
import rikka.shizuku.Shizuku
import rikka.shizuku.Shizuku.OnRequestPermissionResultListener
import rikka.shizuku.ShizukuBinderWrapper

class MainActivity: FlutterActivity() {
    private var installersChannel: MethodChannel? = null
    private val SHIZUKU_PERMISSION_REQUEST_CODE = (10..200).random()

    private fun shizukuCheckPermission(result: Result) {
        try {
            if (Shizuku.isPreV11()) {  // Unsupported
                result.success(-1)
            } else if (Shizuku.checkSelfPermission() == PackageManager.PERMISSION_GRANTED) {
                result.success(1)
            } else if (Shizuku.shouldShowRequestPermissionRationale()) {  // Deny and don't ask again
                result.success(0)
            } else {
                Shizuku.requestPermission(SHIZUKU_PERMISSION_REQUEST_CODE)
                result.success(-2)
            }
        } catch (_: Exception) {  // If shizuku not running
            result.success(-1)
        }
    }

    private val shizukuRequestPermissionResultListener = OnRequestPermissionResultListener {
            requestCode: Int, grantResult: Int ->
        if (requestCode == SHIZUKU_PERMISSION_REQUEST_CODE) {
            val res = if (grantResult == PackageManager.PERMISSION_GRANTED) 1 else 0
            installersChannel!!.invokeMethod("resPermShizuku", mapOf("res" to res))
        }
    }

    private fun shizukuInstallApk(apkFileUri: String, result: Result) {
        val uri = Uri.parse(apkFileUri)
        var res = false
        var session: PackageInstaller.Session? = null
        try {
            val iPackageInstaller: IPackageInstaller =
                ShizukuSystemServerApi.PackageManager_getPackageInstaller()
            val isRoot = Shizuku.getUid() == 0
            // The reason for use "com.android.shell" as installer package under adb
            // is that getMySessions will check installer package's owner
            val installerPackageName = if (isRoot) packageName else "com.android.shell"
            var installerAttributionTag: String? = null
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                installerAttributionTag = attributionTag
            }
            val userId = if (isRoot) Process.myUserHandle().hashCode() else 0
            val packageInstaller = PackageInstallerUtils.createPackageInstaller(
                iPackageInstaller, installerPackageName, installerAttributionTag, userId)
            val params =
                PackageInstaller.SessionParams(PackageInstaller.SessionParams.MODE_FULL_INSTALL)
            var installFlags: Int = PackageInstallerUtils.getInstallFlags(params)
            installFlags = installFlags or 0x00000004  // PackageManager.INSTALL_ALLOW_TEST
            PackageInstallerUtils.setInstallFlags(params, installFlags)
            val sessionId = packageInstaller.createSession(params)
            val iSession = IPackageInstallerSession.Stub.asInterface(
                ShizukuBinderWrapper(iPackageInstaller.openSession(sessionId).asBinder()))
            session = PackageInstallerUtils.createSession(iSession)
            val inputStream = contentResolver.openInputStream(uri)
            val openedSession = session.openWrite("apk.apk", 0, -1)
            val buffer = ByteArray(8192)
            var length: Int
            try {
                while (inputStream!!.read(buffer).also { length = it } > 0) {
                    openedSession.write(buffer, 0, length)
                    openedSession.flush()
                    session.fsync(openedSession)
                }
            } finally {
                try {
                    inputStream!!.close()
                    openedSession.close()
                } catch (e: IOException) {
                    e.printStackTrace()
                }
            }
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
            res = results[0]!!.getIntExtra(
                PackageInstaller.EXTRA_STATUS, PackageInstaller.STATUS_FAILURE) == 0
        } catch (_: Exception) {
            res = false
        } finally {
            if (session != null) {
                try {
                    session.close()
                } catch (_: Exception) {
                    res = false
                }
            }
        }
        result.success(res)
    }

    private fun rootCheckPermission(result: Result) {
        Shell.getShell(Shell.GetShellCallback(
            fun(shell: Shell) {
                result.success(shell.isRoot)
            }
        ))
    }

    private fun rootInstallApk(apkFilePath: String, result: Result) {
        Shell.sh("pm install -R -t " + apkFilePath).submit { out ->
            val builder = StringBuilder()
            for (data in out.getOut()) { builder.append(data) }
            result.success(builder.toString().endsWith("Success"))
        }
    }

    override fun configureFlutterEngine(@NonNull flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        Shizuku.addRequestPermissionResultListener(shizukuRequestPermissionResultListener)
        installersChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger, "installers")
        installersChannel!!.setMethodCallHandler {
            call, result ->
            if (call.method == "checkPermissionShizuku") {
                shizukuCheckPermission(result)
            } else if (call.method == "checkPermissionRoot") {
                rootCheckPermission(result)
            } else if (call.method == "installWithShizuku") {
                val apkFileUri: String? = call.argument("apkFileUri")
                shizukuInstallApk(apkFileUri!!, result)
            } else if (call.method == "installWithRoot") {
                val apkFilePath: String? = call.argument("apkFilePath")
                rootInstallApk(apkFilePath!!, result)
            }
        }
    }

    override fun onDestroy() {
        super.onDestroy()
        Shizuku.removeRequestPermissionResultListener(shizukuRequestPermissionResultListener)
    }
}
