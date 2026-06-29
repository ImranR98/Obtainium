# The Flutter Gradle plugin appends this file automatically when it exists
# (FlutterPlugin.kt lines 222-225). It also applies flutter_proguard_rules.pro
# which ships -dontwarn android.**, -dontwarn io.flutter.plugin.**, and an
# -if..-keep for FlutterPlugin implementations — so those are not repeated here.
# This file only adds what the SDK's defaults don't cover.

# androidx.window transitively provides optional OEM-supplied extension /
# sidecar classes that are compile-time-only stubs, absent from the classpath
# at build time. R8 (rightly) rejects them unless we tell it to ignore.
-dontwarn androidx.window.extensions.**
-dontwarn androidx.window.sidecar.**
