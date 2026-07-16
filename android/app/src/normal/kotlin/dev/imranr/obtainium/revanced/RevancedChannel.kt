package dev.imranr.obtainium.revanced

import android.content.Context
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch

/**
 * Native surface for ReVanced patching: keystore management (this phase) and,
 * once wired up, patch-bundle introspection and patch application. Kept as its
 * own channel rather than folded into the existing "external_install" channel,
 * since that one is scoped to install-target probing/FileProvider access and
 * this is an unrelated, much heavier capability.
 */
class RevancedChannel(private val context: Context) {
    companion object {
        const val CHANNEL = "dev.imranr.obtainium/revanced"
    }

    private val keystoreManager by lazy { KeystoreManager(context) }
    private val scope = CoroutineScope(Dispatchers.Default)

    fun register(messenger: io.flutter.plugin.common.BinaryMessenger) {
        MethodChannel(messenger, CHANNEL).setMethodCallHandler { call, result ->
            handle(call, result)
        }
    }

    private fun handle(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "hasKeystore" -> result.success(keystoreManager.hasKeystore())

            "regenerateKeystore" -> scope.launch {
                try {
                    val alias = call.argument<String>("alias") ?: KeystoreManager.DEFAULT_ALIAS
                    val pass = call.argument<String>("password") ?: KeystoreManager.DEFAULT_PASSWORD
                    keystoreManager.regenerate(alias, pass)
                    result.success(null)
                } catch (e: Exception) {
                    result.error("REGENERATE_FAILED", e.message, null)
                }
            }

            "importKeystore" -> scope.launch {
                try {
                    val alias = call.argument<String>("alias") ?: KeystoreManager.DEFAULT_ALIAS
                    val pass = call.argument<String>("password") ?: KeystoreManager.DEFAULT_PASSWORD
                    val bytes = call.argument<ByteArray>("bytes")
                    if (bytes == null) {
                        result.error("BAD_ARGS", "Missing keystore bytes", null)
                        return@launch
                    }
                    result.success(keystoreManager.import(alias, pass, bytes))
                } catch (e: Exception) {
                    result.error("IMPORT_FAILED", e.message, null)
                }
            }

            "exportKeystore" -> scope.launch {
                try {
                    result.success(keystoreManager.export())
                } catch (e: Exception) {
                    result.error("EXPORT_FAILED", e.message, null)
                }
            }

            "listPatches" -> scope.launch {
                try {
                    val bundlePath = call.argument<String>("bundlePath")
                    if (bundlePath == null) {
                        result.error("BAD_ARGS", "Missing bundlePath", null)
                        return@launch
                    }
                    result.success(PatchBundleLoader.listUniversalPatches(bundlePath))
                } catch (e: Exception) {
                    result.error("LIST_PATCHES_FAILED", e.message, null)
                }
            }

            "applyPatches" -> scope.launch {
                try {
                    val bundlePath = call.argument<String>("bundlePath")
                    val inputApkPath = call.argument<String>("inputApkPath")
                    val outputApkPath = call.argument<String>("outputApkPath")
                    val packageName = call.argument<String>("packageName")
                    @Suppress("UNCHECKED_CAST")
                    val patchNames = call.argument<List<String>>("patchNames") ?: emptyList()
                    @Suppress("UNCHECKED_CAST")
                    val options = call.argument<Map<String, Map<String, Any?>>>("options") ?: emptyMap()
                    val alias = call.argument<String>("alias") ?: KeystoreManager.DEFAULT_ALIAS
                    val pass = call.argument<String>("password") ?: KeystoreManager.DEFAULT_PASSWORD
                    val signOnly = call.argument<Boolean>("signOnly") ?: false
                    if (bundlePath == null || inputApkPath == null || outputApkPath == null || packageName == null) {
                        result.error("BAD_ARGS", "Missing required argument", null)
                        return@launch
                    }
                    val engine = PatchEngine(context, keystoreManager)
                    val patchResult = engine.patchAndSign(
                        bundlePath = bundlePath,
                        inputApkPath = inputApkPath,
                        outputApkPath = outputApkPath,
                        packageName = packageName,
                        selectedPatchNames = patchNames,
                        options = options,
                        alias = alias,
                        password = pass,
                        signOnly = signOnly,
                    )
                    result.success(
                        mapOf(
                            "success" to patchResult.success,
                            "outputPath" to patchResult.outputPath,
                            "error" to patchResult.error,
                        )
                    )
                } catch (e: Exception) {
                    result.error("APPLY_PATCHES_FAILED", e.message, null)
                }
            }

            else -> result.notImplemented()
        }
    }
}
