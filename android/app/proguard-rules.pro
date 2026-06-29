# The Flutter Gradle plugin auto-wires this file when it exists, in addition to
# its own flutter_proguard_rules.pro. R8 is always enabled on release builds
# (the --no-shrink flag has no effect per the official docs), so custom rules
# here are the intended way to handle build-time warnings and prevent the
# shrinker from stripping plugin classes accessed by reflection.

# androidx.window transitively provides optional OEM-supplied stubs that are
# compile-time-only; R8 rejects them as missing.
-dontwarn androidx.window.extensions.**
-dontwarn androidx.window.sidecar.**

# Prevent R8 from stripping plugin classes that are only accessed
# reflectively (GeneratedPluginRegistrant, MethodChannel, JNI). Without
# these, the release APK crashes immediately on launch.
-keep class dev.imranr.obtainium.** { *; }
-keep class io.flutter.plugins.** { *; }
-keep class io.flutter.embedding.** { *; }
-keep class com.android_package_installer.** { *; }
-keep class com.android_package_manager.** { *; }
-keep class com.pravera.flutter_foreground_task.** { *; }
-keep class rikka.shizuku.** { *; }
-keep class rikka.sui.** { *; }
-keep class com.afollestad.materialdialogs.** { *; }
-keep class com.baseflow.permissionhandler.** { *; }
-keep class com.dexterous.flutterlocalnotifications.** { *; }
-keep class com.tekartik.sqflite.** { *; }
-keep class com.transistorsoft.** { *; }
-keep class com.llfbandit.app_links.** { *; }
-keep class com.madlonkay.flutter_charset_detector.** { *; }
-keep class com.ajinasokan.flutter_fgbg.** { *; }
-keep class com.anggrayudi.storage.** { *; }
-keep class com.it_nomads.fluttersecurestorage.** { *; }
-keep class com.getkeepsafe.relinker.** { *; }
-keep class com.rosan.dhizuku.** { *; }
-keep class com.kineapps.flutterarchive.** { *; }
-keep class org.lsposed.hiddenapibypass.** { *; }
-keep class dev.fluttercommunity.plus.** { *; }
-keep class dev.re.** { *; }
-keep class dev.rikka.tools.** { *; }
-keep class com.mr.flutter.** { *; }
