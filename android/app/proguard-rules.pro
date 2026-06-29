# Preserve the app itself and all plugin classes. The Flutter Gradle plugin
# forces R8 on release builds, and these classes are accessed reflectively
# (GeneratedPluginRegistrant, MethodChannel lookup, JNI callbacks) so R8
# cannot trace the usage and strips them — causing immediate launch crashes
# (NoClassDefFoundError) or MissingPluginException at runtime.
-keep class dev.imranr.obtainium.** { *; }
-keep class io.flutter.plugins.** { *; }
-keep class io.flutter.embedding.** { *; }
-keep class com.android_package_installer.** { *; }
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

# androidx.window transitively provides optional OEM-supplied extension /
# sidecar classes that are *not* present at compile time — they live on the
# device (or are absent, in which case the library falls back gracefully).
# Suppress the R8 missing-class errors so the build completes.
-dontwarn androidx.window.extensions.**
-dontwarn androidx.window.sidecar.**
