package com.seojasoos.hostel_app

import android.util.Log
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.plugins.FlutterPlugin

/**
 * Plugin registration that survives one bad plugin.
 *
 * Flutter's generated registrant adds plugins one after another and only catches
 * `Exception`. The `jni` plugin (pulled in by path_provider) loads a native library in a
 * static initializer; when that fails it throws an `Error` (UnsatisfiedLinkError /
 * ExceptionInInitializerError), the registrant stops half-way, and every plugin after it
 * (open_filex, package_info_plus, printing, share_plus, url_launcher) is never registered.
 * That is what caused "MissingPluginException ... net.nfet.printing" and
 * "... dev.fluttercommunity.plus/share" on the receipt screen.
 *
 * Here we let Flutter register what it can, then add any plugin that is still missing,
 * each one on its own and catching Throwable, so one broken plugin can't take the others down.
 */
class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        try {
            super.configureFlutterEngine(flutterEngine)
        } catch (t: Throwable) {
            Log.e(TAG, "Automatic plugin registration failed part-way", t)
        }
        for (name in PLUGINS) ensure(flutterEngine, name)
    }

    private fun ensure(engine: FlutterEngine, className: String) {
        try {
            @Suppress("UNCHECKED_CAST")
            val cls = Class.forName(className) as Class<out FlutterPlugin>
            if (engine.plugins.has(cls)) return
            engine.plugins.add(cls.getDeclaredConstructor().newInstance())
            Log.i(TAG, "Registered $className")
        } catch (t: Throwable) {
            Log.e(TAG, "Could not register $className", t)
        }
    }

    companion object {
        private const val TAG = "HostelPlugins"

        // Order matters only for readability; each is registered independently.
        private val PLUGINS = listOf(
            "com.mr.flutter.plugin.filepicker.FilePickerPlugin",
            "io.flutter.plugins.flutter_plugin_android_lifecycle.FlutterAndroidLifecyclePlugin",
            "com.it_nomads.fluttersecurestorage.FlutterSecureStoragePlugin",
            "io.flutter.plugins.imagepicker.ImagePickerPlugin",
            "com.crazecoder.openfile.OpenFilePlugin",
            "dev.fluttercommunity.plus.packageinfo.PackageInfoPlugin",
            "net.nfet.flutter.printing.PrintingPlugin",
            "dev.fluttercommunity.plus.share.SharePlusPlugin",
            "io.flutter.plugins.urllauncher.UrlLauncherPlugin",
            // Last: these load native code and are the ones that can fail.
            "com.github.dart_lang.jni_flutter.JniFlutterPlugin",
            "com.github.dart_lang.jni.JniPlugin",
        )
    }
}
