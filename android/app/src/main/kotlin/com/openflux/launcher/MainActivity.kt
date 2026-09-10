package com.openflux.launcher

import android.Manifest
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // URL is a credential: do not include it in screenshots / recents thumbnails.
        window.addFlags(WindowManager.LayoutParams.FLAG_SECURE)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "com.openflux.launcher/control")
            .setMethodCallHandler { call, result ->
                try {
                    when (call.method) {
                        "loadUrl" -> result.success(SecretStore(this).load())
                        "snapshot" -> result.success(LauncherState.snapshot())
                        "clearLogs" -> { LauncherState.clear(); result.success(null) }
                        "start" -> {
                            val url = call.argument<String>("url")?.trim() ?: ""
                            val invalid = LauncherRules.validate(url)
                            if (invalid != null) { result.error("invalid_url", invalid, null); return@setMethodCallHandler }
                            if (LauncherState.isActive()) { result.success(null); return@setMethodCallHandler }
                            if (Build.VERSION.SDK_INT >= 33 && checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED) {
                                requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), 101)
                            }
                            SecretStore(this).save(url)
                            val intent = Intent(this, OpenFluxService::class.java)
                                .setAction(OpenFluxService.START)
                                .putExtra("debug", call.argument<Boolean>("debug") ?: false)
                            startForegroundService(intent)
                            result.success(null)
                        }
                        "stop" -> {
                            if (LauncherState.isActive()) startService(Intent(this, OpenFluxService::class.java).setAction(OpenFluxService.STOP))
                            result.success(null)
                        }
                        else -> result.notImplemented()
                    }
                } catch (_: Exception) {
                    // Never return platform exception text: it can contain credentials.
                    result.error("platform_error", "Не удалось выполнить операцию. Проверьте разрешения или введите ссылку заново.", null)
                }
            }
    }
}
