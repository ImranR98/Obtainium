package dev.imranr.obtainium

import android.content.ComponentName
import android.content.Intent
import android.content.pm.PackageManager
import android.content.pm.ResolveInfo
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.drawable.BitmapDrawable
import android.net.Uri
import android.os.Build
import android.system.Os
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream
import java.io.File

private const val CHANNEL = "dev.imranr.obtainium/installer"
private const val APK_MIME = "application/vnd.android.package-archive"
private const val RELEASE_DIR = "releases"

class MainActivity : FlutterActivity() {

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "queryApkInstallerActivities" -> {
                    try {
                        result.success(queryApkInstallerActivities())
                    } catch (ex: Exception) {
                        result.error("QUERY_ERROR", ex.message, null)
                    }
                }
                "launchInstallIntent" -> {
                    try {
                        val apkFilePath = call.argument<String>("path")!!
                        val targetPackage = call.argument<String>("package")
                        val targetActivity = call.argument<String>("activity")
                        launchInstallIntent(apkFilePath, targetPackage, targetActivity)
                        result.success(null)
                    } catch (ex: Exception) {
                        result.error("INSTALL_ERROR", ex.message, null)
                    }
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun queryApkInstallerActivities(): List<Map<String, Any>> {
        val results = mutableMapOf<String, Map<String, Any>>()

        val installIntent = Intent(Intent.ACTION_INSTALL_PACKAGE).apply {
            setDataAndType(Uri.parse("content://dummy/test.apk"), APK_MIME)
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        }
        for (resolveInfo in packageManager.queryIntentActivities(installIntent, 0)) {
            val key = "${resolveInfo.activityInfo.packageName}|${resolveInfo.activityInfo.name}"
            if (!results.containsKey(key)) {
                results[key] = resolveInfoToMap(resolveInfo)
            }
        }

        val viewIntent = Intent(Intent.ACTION_VIEW).apply {
            setDataAndType(Uri.parse("content://dummy/test.apk"), APK_MIME)
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        }
        for (resolveInfo in packageManager.queryIntentActivities(viewIntent, 0)) {
            val key = "${resolveInfo.activityInfo.packageName}|${resolveInfo.activityInfo.name}"
            if (!results.containsKey(key)) {
                results[key] = resolveInfoToMap(resolveInfo)
            }
        }

        return results.values.toList()
    }

    private fun resolveInfoToMap(resolveInfo: ResolveInfo): Map<String, Any> {
        val pkgName = resolveInfo.activityInfo.packageName
        val activityName = resolveInfo.activityInfo.name
        val label = resolveInfo.loadLabel(packageManager).toString()
        val iconBytes = try {
            val drawable = resolveInfo.loadIcon(packageManager)
            val bitmap = if (drawable is BitmapDrawable && drawable.bitmap != null) {
                drawable.bitmap
            } else {
                val bmp = Bitmap.createBitmap(
                    drawable.intrinsicWidth.coerceAtLeast(1),
                    drawable.intrinsicHeight.coerceAtLeast(1),
                    Bitmap.Config.ARGB_8888
                )
                val canvas = Canvas(bmp)
                drawable.setBounds(0, 0, canvas.width, canvas.height)
                drawable.draw(canvas)
                bmp
            }
            val stream = ByteArrayOutputStream()
            bitmap.compress(Bitmap.CompressFormat.PNG, 100, stream)
            stream.toByteArray()
        } catch (_: Exception) {
            ByteArray(0)
        }
        val result = mutableMapOf<String, Any>(
            "packageName" to pkgName,
            "activityName" to activityName,
            "label" to label,
        )
        if (iconBytes.isNotEmpty()) {
            result["icon"] = iconBytes
        }
        return result
    }

    @Suppress("DEPRECATION")
    private fun launchInstallIntent(
        apkFilePath: String,
        targetPackage: String?,
        targetActivity: String?
    ) {
        val sourceFile = File(apkFilePath)
        val releaseFile = copyToReleaseCache(sourceFile)

        val providerAuthority = findCacheProviderAuthority()
        val relativePath = releaseFile.path.drop(cacheDir.path.length)
        val contentUri = Uri.Builder()
            .scheme("content")
            .authority(providerAuthority)
            .encodedPath(relativePath)
            .build()

        val installFlag = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
            Intent.FLAG_GRANT_READ_URI_PERMISSION
        } else {
            0
        }

        val intent = Intent(Intent.ACTION_INSTALL_PACKAGE).apply {
            setDataAndType(contentUri, APK_MIME)
            flags = installFlag or Intent.FLAG_ACTIVITY_NEW_TASK
            if (!targetPackage.isNullOrEmpty() && !targetActivity.isNullOrEmpty()) {
                component = ComponentName(targetPackage, targetActivity)
            }
        }

        startActivity(intent)
    }

    private fun findCacheProviderAuthority(): String {
        val packageInfo = packageManager.getPackageInfo(packageName, PackageManager.GET_PROVIDERS)
        val providerInfo = packageInfo.providers?.find {
            it.name == CacheContentProvider::class.java.name
        } ?: throw IllegalStateException("CacheContentProvider not found in manifest")
        return providerInfo.authority
    }

    private fun copyToReleaseCache(sourceFile: File): File {
        val releasesDir = File(cacheDir, RELEASE_DIR).apply { mkdirs() }
        val releaseFile = File(releasesDir, sourceFile.name)
        sourceFile.inputStream().use { input ->
            releaseFile.outputStream().use { output ->
                input.copyTo(output)
            }
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
            try {
                val cacheRoot = cacheDir.parentFile!!.parentFile!!
                generateSequence(releaseFile) { it.parentFile }
                    .takeWhile { it != cacheRoot }
                    .forEach { file ->
                        val mode = if (file.isDirectory) 0b001001001 else 0b100100100
                        val oldMode = Os.stat(file.path).st_mode and 0b111111111111
                        val newMode = oldMode or mode
                        if (newMode != oldMode) Os.chmod(file.path, newMode)
                    }
            } catch (_: Exception) { }
        }
        return releaseFile
    }
}
