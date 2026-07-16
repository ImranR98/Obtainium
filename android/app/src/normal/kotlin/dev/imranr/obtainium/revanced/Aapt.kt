package dev.imranr.obtainium.revanced

import android.content.Context
import java.io.File

/**
 * Resolves the prebuilt aapt2 binary bundled under jniLibs for the device's ABI,
 * the same approach ReVanced Manager uses (aapt2 is just another .so, resolved by
 * filename search under the app's native library dir rather than any special
 * Gradle mechanism).
 *
 * NOTE: the actual `libaapt2obtainium.so` binaries are not produced by this change
 * and must be added separately under android/app/src/normal/jniLibs/<abi>/ before
 * this can work at runtime - see the plan's Phase 3 notes.
 */
object Aapt {
    private const val LIB_NAME = "libaapt2obtainium.so"

    fun binary(context: Context): File? {
        val nativeLibDir = context.applicationInfo.nativeLibraryDir ?: return null
        val candidate = File(nativeLibDir, LIB_NAME)
        return if (candidate.exists()) candidate else null
    }
}
