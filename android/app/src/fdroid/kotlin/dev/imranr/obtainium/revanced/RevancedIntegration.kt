package dev.imranr.obtainium.revanced

import android.content.Context
import io.flutter.embedding.engine.FlutterEngine

/**
 * F-Droid flavor stub. F-Droid's inclusion policy prohibits apps that download and
 * execute compiled code fetched at runtime, which is exactly what loading a ReVanced
 * patch bundle jar does - so this flavor never links patcher-android/library-android
 * and never registers the channel.
 */
object RevancedIntegration {
    fun register(engine: FlutterEngine, context: Context) {
        // Intentionally no-op: ReVanced patching is excluded from the fdroid flavor.
    }
}
