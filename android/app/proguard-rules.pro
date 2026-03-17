# ═══════════════════════════════════════════════════════════
# PROGUARD / R8 RULES — Study Organizer
#
# IMPORTANT: Every package name here is verified against
# android/app/src/main/java/io/flutter/plugins/GeneratedPluginRegistrant.java
# DO NOT guess package names — always read GeneratedPluginRegistrant.java first.
# ═══════════════════════════════════════════════════════════

# ── Flutter core ─────────────────────────────────────────────
-keep class io.flutter.** { *; }
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.** { *; }
-keep class io.flutter.plugins.** { *; }
-keep class io.flutter.util.** { *; }
-keep class io.flutter.view.** { *; }
-keep class io.flutter.embedding.** { *; }
-keep class io.flutter.embedding.android.** { *; }
-keep class io.flutter.embedding.engine.** { *; }

# ── Gson (used internally by flutter_local_notifications) ─────
# CRITICAL FIX: R8 strips generic type parameters from Gson's TypeToken.
# flutter_local_notifications uses TypeToken to deserialize saved notification
# JSON when the alarm fires. Without this rule:
#   com.google.gson.reflect.TypeToken → renamed to "a", type parameter <T> lost
#   → getSuperclassTypeParameter() throws "Missing type parameter" → crash.
-keep class com.google.gson.** { *; }
-keep class com.google.gson.reflect.TypeToken { *; }
-keep class * extends com.google.gson.reflect.TypeToken
-keepattributes Signature
-keepattributes *Annotation*
-dontwarn com.google.gson.**
# Real class: com.dexterous.flutterlocalnotifications.FlutterLocalNotificationsPlugin
# BroadcastReceivers are invoked by Android via reflection — must not be renamed.
-keep class com.dexterous.** { *; }
-keep class com.dexterous.flutterlocalnotifications.** { *; }
-keepclassmembers class com.dexterous.flutterlocalnotifications.** { *; }
-dontwarn com.dexterous.**

# ── timezone ──────────────────────────────────────────────────
-keep class com.example.timezone.** { *; }
-keep class dev.fluttercommunity.plus.timezone.** { *; }
-dontwarn dev.fluttercommunity.plus.timezone.**

# ── sqflite ───────────────────────────────────────────────────
# Real class: com.tekartik.sqflite.SqflitePlugin
-keep class com.tekartik.sqflite.** { *; }
-keepclassmembers class com.tekartik.sqflite.** { *; }
-dontwarn com.tekartik.sqflite.**

# ── shared_preferences ────────────────────────────────────────
# Real class: io.flutter.plugins.sharedpreferences.SharedPreferencesPlugin
-keep class io.flutter.plugins.sharedpreferences.** { *; }
-dontwarn io.flutter.plugins.sharedpreferences.**

# ── flutter_tts ───────────────────────────────────────────────
# Real class: com.eyedeadevelopment.fluttertts.FlutterTtsPlugin
# PREVIOUS BUG: proguard was keeping "com.tundralabs.fluttertts.**" which
# is the WRONG package — that's an old version of flutter_tts.
# The current flutter_tts package is com.eyedeadevelopment.fluttertts.
# R8 was stripping the real class entirely because the wrong name was kept.
-keep class com.eyedeadevelopment.fluttertts.** { *; }
-keepclassmembers class com.eyedeadevelopment.fluttertts.** { *; }
-dontwarn com.eyedeadevelopment.fluttertts.**

# ── audioplayers ──────────────────────────────────────────────
# Real class: xyz.luan.audioplayers.AudioplayersPlugin
-keep class xyz.luan.audioplayers.** { *; }
-keepclassmembers class xyz.luan.audioplayers.** { *; }
-dontwarn xyz.luan.audioplayers.**

# ── share_plus ────────────────────────────────────────────────
# Real class: dev.fluttercommunity.plus.share.SharePlusPlugin
-keep class dev.fluttercommunity.plus.share.** { *; }
-dontwarn dev.fluttercommunity.plus.share.**

# ── file_picker ───────────────────────────────────────────────
# Real class: com.mr.flutter.plugin.filepicker.FilePickerPlugin
-keep class com.mr.flutter.plugin.filepicker.** { *; }
-dontwarn com.mr.flutter.plugin.filepicker.**

# ── path_provider ─────────────────────────────────────────────
# Real class: io.flutter.plugins.pathprovider.PathProviderPlugin
-keep class io.flutter.plugins.pathprovider.** { *; }
-dontwarn io.flutter.plugins.pathprovider.**

# ── flutter_android_lifecycle ─────────────────────────────────
# Real class: io.flutter.plugins.flutter_plugin_android_lifecycle
-keep class io.flutter.plugins.flutter_plugin_android_lifecycle.** { *; }
-dontwarn io.flutter.plugins.flutter_plugin_android_lifecycle.**

# ── Your app ──────────────────────────────────────────────────
-keep class com.example.study_organizer.** { *; }

# ── AndroidX ──────────────────────────────────────────────────
-keep class androidx.** { *; }
-keep interface androidx.** { *; }
-dontwarn androidx.**
-keep class androidx.multidex.** { *; }

# ── Kotlin ────────────────────────────────────────────────────
# Handled automatically by Kotlin Gradle plugin — no explicit rules needed.
-dontwarn kotlin.**

# ── Google Play Core ──────────────────────────────────────────
-dontwarn com.google.android.play.core.**
-keep class com.google.android.play.core.** { *; }

# ── Suppress common harmless warnings ────────────────────────
-dontwarn java.lang.invoke.**
-dontwarn javax.annotation.**
-dontwarn sun.misc.Unsafe