# Flutter plugins are found by class name (GeneratedPluginRegistrant and MainActivity's
# fallback registration), and several talk to native code through JNI. Keep them whole.
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }
-keep class net.nfet.flutter.printing.** { *; }
-keep class dev.fluttercommunity.plus.** { *; }
-keep class com.crazecoder.openfile.** { *; }
-keep class com.mr.flutter.plugin.filepicker.** { *; }
-keep class com.it_nomads.fluttersecurestorage.** { *; }
-keep class com.github.dart_lang.** { *; }
-keep class com.seojasoos.hostel_app.** { *; }
-keepclasseswithmembernames class * { native <methods>; }
-keep class * implements io.flutter.embedding.engine.plugins.FlutterPlugin { <init>(); *; }
# Classes looked up from Dart through package:jni (path_provider).
-keep class androidx.core.content.** { *; }
-keep class android.** { *; }
-dontwarn com.google.android.play.core.**
-dontwarn io.flutter.embedding.**
-dontwarn javax.annotation.**
