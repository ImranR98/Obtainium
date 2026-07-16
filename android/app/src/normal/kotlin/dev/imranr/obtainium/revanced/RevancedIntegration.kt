package dev.imranr.obtainium.revanced

import android.content.Context
import io.flutter.embedding.engine.FlutterEngine

/** Normal-flavor entry point: registers the ReVanced patching MethodChannel. */
object RevancedIntegration {
    fun register(engine: FlutterEngine, context: Context) {
        RevancedChannel(context).register(engine.dartExecutor.binaryMessenger)
    }
}
