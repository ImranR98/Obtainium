package dev.imranr.obtainium.revanced

import android.content.Context
import app.revanced.library.ApkUtils
import app.revanced.patcher.Patcher
import app.revanced.patcher.PatcherConfig
import java.io.File

data class PatchResult(
    val success: Boolean,
    val outputPath: String?,
    val error: String?,
)

/**
 * Runs a patch job entirely in-process (no separate-process OOM isolation, unlike
 * ReVanced Manager's ProcessRuntime - out of scope per the plan) and signs the
 * result with Obtainium's own keystore.
 *
 * Also supports signOnly mode: re-sign the input APK with the keystore without
 * applying any patches, used as the opt-in fallback when a configured patch fails
 * to apply to a new app version (see Phase 3 "patch failure fallback" decision).
 *
 * NOTE: this file has not been compiled against the pinned revanced-patcher /
 * revanced-library versions (no JVM/Android build toolchain was available while
 * writing it) - the Patcher/PatcherConfig constructor shape and ApkUtils.applyTo
 * signature are based on ReVanced Manager's CoroutineRuntime.kt at the time of
 * writing and should be double-checked against those exact dependency versions
 * before shipping.
 */
class PatchEngine(
    private val context: Context,
    private val keystoreManager: KeystoreManager,
) {
    suspend fun patchAndSign(
        bundlePath: String,
        inputApkPath: String,
        outputApkPath: String,
        packageName: String,
        selectedPatchNames: List<String>,
        options: Map<String, Map<String, Any?>>,
        alias: String,
        password: String,
        signOnly: Boolean = false,
    ): PatchResult {
        val inputApk = File(inputApkPath)
        val outputApk = File(outputApkPath)
        outputApk.parentFile?.mkdirs()

        if (signOnly || selectedPatchNames.isEmpty()) {
            return try {
                keystoreManager.sign(inputApk, outputApk, alias, password)
                PatchResult(success = true, outputPath = outputApkPath, error = null)
            } catch (e: Exception) {
                PatchResult(success = false, outputPath = null, error = e.message ?: "Signing failed")
            }
        }

        return try {
            val aaptBinary = Aapt.binary(context)
                ?: return PatchResult(
                    success = false,
                    outputPath = null,
                    error = "aapt2 binary not found for this device ABI",
                )

            val selectedPatches = PatchBundleLoader.resolveSelectedPatches(
                bundlePath = bundlePath,
                selectedPatchNames = selectedPatchNames,
                options = options,
            )
            if (selectedPatches.isEmpty()) {
                return PatchResult(
                    success = false,
                    outputPath = null,
                    error = "None of the configured patches were found in the bundle for $packageName",
                )
            }

            val workDir = context.cacheDir.resolve("revanced-work").apply { mkdirs() }
            val unsignedApk = File(workDir, "${packageName}-unsigned.apk")

            val patcherConfig = PatcherConfig(
                apkFile = inputApk,
                temporaryFilesPath = workDir,
                aaptBinaryPath = aaptBinary.absolutePath,
            )
            Patcher(patcherConfig).use { patcher ->
                patcher.apply {
                    acceptPatches(selectedPatches.toList())
                }
                val patcherResult = patcher.patch()
                ApkUtils.applyTo(patcherResult, unsignedApk)
            }

            keystoreManager.sign(unsignedApk, outputApk, alias, password)
            unsignedApk.delete()

            PatchResult(success = true, outputPath = outputApkPath, error = null)
        } catch (e: Exception) {
            PatchResult(success = false, outputPath = null, error = e.message ?: "Patching failed")
        }
    }
}
