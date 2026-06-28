package dev.imranr.obtainium

import android.content.Context
import android.content.Intent
import android.content.pm.IPackageInstaller
import android.content.pm.IPackageInstallerSession
import android.content.pm.IPackageManager
import android.content.pm.PackageInstaller
import android.content.pm.PackageInstallerHidden
import android.content.pm.PackageManager
import android.content.pm.PackageManagerHidden
import android.os.Build
import android.os.IBinder
import android.os.IInterface
import android.os.Process
import android.util.Log
import androidx.core.net.toUri
import dev.rikka.tools.refine.Refine
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.withContext
import org.lsposed.hiddenapibypass.HiddenApiBypass
import rikka.shizuku.Shizuku
import rikka.shizuku.ShizukuBinderWrapper
import rikka.shizuku.ShizukuProvider
import rikka.shizuku.SystemServiceHelper
import rikka.sui.Sui
import java.io.IOException
import kotlin.coroutines.resume
import kotlin.coroutines.suspendCoroutine

class PrivilegeInstallFallbackHandler(private val appContext: Context) {
    private var isBinderAvailable = false
    private val requestPermissionCode = (3000..4000).random()
    private val requestPermissionMutex by lazy { Mutex(locked = true) }
    private var permissionGranted = false
    private var isRoot = false
    private var initialized = false
    private var isSuiBackend = false

    private val binderReceivedListener =
        Shizuku.OnBinderReceivedListener { isBinderAvailable = true }
    private val binderDeadListener = Shizuku.OnBinderDeadListener { isBinderAvailable = false }
    private val requestPermissionResultListener =
        Shizuku.OnRequestPermissionResultListener { requestCode: Int, grantResult: Int ->
            if (requestCode == requestPermissionCode) {
                permissionGranted = grantResult == PackageManager.PERMISSION_GRANTED
                requestPermissionMutex.unlock()
            }
        }

    private fun ensureInitialized() {
        if (initialized) return
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            HiddenApiBypass.addHiddenApiExemptions("Landroid/content", "Landroid/os")
        }
        val isSui = Sui.init(appContext.packageName)
        isSuiBackend = isSui
        if (!isSui) {
            ShizukuProvider.enableMultiProcessSupport(false)
            ShizukuProvider.requestBinderForNonProviderProcess(appContext)
        }
        Shizuku.addBinderReceivedListenerSticky(binderReceivedListener)
        Shizuku.addBinderDeadListener(binderDeadListener)
        Shizuku.addRequestPermissionResultListener(requestPermissionResultListener)
        initialized = true
    }

    private fun wrapBinder(binder: IBinder) = ShizukuBinderWrapper(binder)

    private fun IInterface.asShizukuBinder() = wrapBinder(this.asBinder())

    private fun iPackageInstaller(): IPackageInstaller {
        val iPackageManager = IPackageManager.Stub.asInterface(
            wrapBinder(SystemServiceHelper.getSystemService("package")),
        )
        return IPackageInstaller.Stub.asInterface(
            iPackageManager.packageInstaller.asShizukuBinder(),
        )
    }

    private fun packageInstaller(fakeInstallSource: String): PackageInstaller {
        val installerPackageName =
            if (fakeInstallSource == "") appContext.packageName else fakeInstallSource
        isRoot = Shizuku.getUid() == 0
        val userId = if (!isRoot) Process.myUserHandle().hashCode() else 0
        val installer = iPackageInstaller()
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            Refine.unsafeCast(
                PackageInstallerHidden(
                    installer,
                    installerPackageName,
                    appContext.attributionTag,
                    userId,
                ),
            )
        } else {
            Refine.unsafeCast(
                PackageInstallerHidden(installer, installerPackageName, userId),
            )
        }
    }

    private fun sessionParams(): PackageInstaller.SessionParams {
        val params =
            PackageInstaller.SessionParams(PackageInstaller.SessionParams.MODE_FULL_INSTALL)
        var flags =
            Refine.unsafeCast<PackageInstallerHidden.SessionParamsHidden>(params).installFlags
        flags = flags or PackageManagerHidden.INSTALL_ALLOW_TEST or
            PackageManagerHidden.INSTALL_REPLACE_EXISTING
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            flags = flags or PackageManagerHidden.INSTALL_BYPASS_LOW_TARGET_SDK_BLOCK
        }
        Refine.unsafeCast<PackageInstallerHidden.SessionParamsHidden>(params).installFlags = flags
        return params
    }

    private fun createPackageInstallerSession(fakeInstallSource: String): PackageInstaller.Session {
        val installer = packageInstaller(fakeInstallSource)
        val iInstaller = iPackageInstaller()
        val sessionId = installer.createSession(sessionParams())
        val iSession = IPackageInstallerSession.Stub.asInterface(
            iInstaller.openSession(sessionId).asShizukuBinder(),
        )
        return Refine.unsafeCast(PackageInstallerHidden.SessionHidden(iSession))
    }

    private suspend fun checkShizukuPermissionImpl(): String {
        return if (Shizuku.isPreV11()) {
            "old_shizuku"
        } else if (Shizuku.checkSelfPermission() == PackageManager.PERMISSION_GRANTED) {
            if (!registerUidObserverPermissionLimitedCheck()) {
                "granted_" + if (isRoot) "root" else "adb"
            } else {
                "old_android_with_adb"
            }
        } else if (Shizuku.shouldShowRequestPermissionRationale()) {
            "denied"
        } else {
            Shizuku.requestPermission(requestPermissionCode)
            requestPermissionMutex.lock()
            if (!registerUidObserverPermissionLimitedCheck()) {
                if (permissionGranted) {
                    "granted_" + if (isRoot) "root" else "adb"
                } else {
                    "denied"
                }
            } else {
                "old_android_with_adb"
            }
        }
    }

    suspend fun checkShizukuPermissionCode(): String {
        ensureInitialized()
        if (!isBinderAvailable) return "services_not_found"
        return checkShizukuPermissionImpl()
    }

    fun getShizukuBackendKind(): String {
        ensureInitialized()
        return if (isSuiBackend) "sui" else "shizuku"
    }

    private fun registerUidObserverPermissionLimitedCheck(): Boolean {
        isRoot = Shizuku.getUid() == 0
        return !isRoot && Build.VERSION.SDK_INT < Build.VERSION_CODES.O_MR1
    }

    suspend fun installViaShizuku(apkUri: String, fakeInstallSource: String): Int {
        ensureInitialized()
        if (!checkShizukuPermissionCode().startsWith("granted")) {
            Log.e(TAG, "Shizuku permission not granted for fallback install")
            return PackageInstaller.STATUS_FAILURE
        }
        var status = PackageInstaller.STATUS_FAILURE
        withContext(Dispatchers.IO) {
            runCatching {
                createPackageInstallerSession(fakeInstallSource).use { session ->
                    val uri = apkUri.toUri()
                    val stream = appContext.contentResolver.openInputStream(uri)
                        ?: throw IOException("Cannot open input stream")
                    stream.use {
                        session.openWrite("0.apk", 0, stream.available().toLong()).use { out ->
                            stream.copyTo(out)
                            session.fsync(out)
                        }
                    }
                    var result: Intent? = null
                    suspendCoroutine { cont ->
                        val adapter = ShizukuIntentSenderHelper.IIntentSenderAdaptor { intent ->
                            result = intent
                            cont.resume(Unit)
                        }
                        val intentSender =
                            ShizukuIntentSenderHelper.newIntentSender(adapter)
                        session.commit(intentSender)
                    }
                    result?.let {
                        status = it.getIntExtra(
                            PackageInstaller.EXTRA_STATUS,
                            PackageInstaller.STATUS_FAILURE,
                        )
                        val message = it.getStringExtra(
                            PackageInstaller.EXTRA_STATUS_MESSAGE,
                        ) ?: "No message"
                        Log.i(TAG, "Shizuku fallback install result: $message")
                    } ?: throw IOException("Intent is null")
                }
            }.onFailure {
                Log.e(TAG, "Shizuku fallback install error: ${it.message}", it)
            }
        }
        return status
    }

    companion object {
        private const val TAG = "obtainium_shizuku_fallback"
    }
}
