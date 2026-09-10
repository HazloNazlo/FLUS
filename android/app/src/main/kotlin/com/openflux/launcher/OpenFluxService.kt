package com.openflux.launcher

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder
import android.os.Handler
import android.os.Looper
import android.os.PowerManager
import java.io.File
import java.net.InetSocketAddress
import java.net.ServerSocket
import java.net.Socket
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicBoolean
import kotlin.concurrent.thread

class OpenFluxService : Service() {
    companion object {
        const val START = "com.openflux.launcher.START"
        const val STOP = "com.openflux.launcher.STOP"
        private const val CHANNEL = "flus_running"
        private const val NOTIFICATION = 1080
    }
    private val stopping = AtomicBoolean(false)
    private val executing = AtomicBoolean(false)
    private val listening = AtomicBoolean(false)
    private val portCollision = AtomicBoolean(false)
    @Volatile private var child: Process? = null
    private var wakeLock: PowerManager.WakeLock? = null
    @Volatile private var serviceDestroyed = false
    private val mainHandler = Handler(Looper.getMainLooper())
    private var latestStartId = 0

    override fun onBind(intent: Intent?): IBinder? = null
    override fun onCreate() {
        super.onCreate()
        getSystemService(NotificationManager::class.java).createNotificationChannel(
            NotificationChannel(CHANNEL, "FLUS — локальный SOCKS5", NotificationManager.IMPORTANCE_LOW))
    }
    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        latestStartId = startId
        if (intent?.action == STOP) {
            stopping.set(true)
            if (executing.get()) {
                LauncherState.update("stopping", "Завершаем OpenFlux…")
                child?.destroy()
            } else stopSelf()
            return START_NOT_STICKY
        }
        if (intent?.action != START) { stopSelf(); return START_NOT_STICKY }
        if (!executing.compareAndSet(false, true)) return START_NOT_STICKY
        stopping.set(false); listening.set(false); portCollision.set(false)
        LauncherState.update("starting", "Запускаем локальный SOCKS5…")
        try {
            val notification = notification("Запускается")
            if (Build.VERSION.SDK_INT >= 34) startForeground(NOTIFICATION, notification, ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE)
            else startForeground(NOTIFICATION, notification)
            wakeLock = (getSystemService(POWER_SERVICE) as PowerManager).newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "FLUS:OpenFlux").apply {
                setReferenceCounted(false)
                // Released in all shutdown paths. Continuous use consumes battery.
                acquire()
            }
            thread(name = "flus-supervisor") { runSession(intent.getBooleanExtra("debug", false)) }
        } catch (_: Exception) {
            executing.set(false)
            LauncherState.update("error", "Не удалось запустить foreground service. Откройте FLUS и повторите запуск.")
            stopSelf()
        }
        return START_NOT_STICKY
    }

    private fun runSession(verbose: Boolean) {
        var failure: String? = null
        var reader: Thread? = null
        try {
            val url = SecretStore(this).load()
            LauncherRules.validate(url)?.let { throw LauncherFailure(it) }
            try {
                ServerSocket().use { socket -> socket.reuseAddress = true; socket.bind(InetSocketAddress("127.0.0.1", 1080)) }
            } catch (_: Exception) { throw LauncherFailure("Порт 1080 уже занят. Остановите другое приложение.") }
            if (stopping.get()) return
            val binary = File(applicationInfo.nativeLibraryDir, "libopenflux.so")
            if (!binary.isFile) throw LauncherFailure("Встроенный OpenFlux не найден. Установите arm64 APK из Releases.")
            if (!binary.canExecute()) throw LauncherFailure("Не удалось запустить OpenFlux: проверьте упаковку APK.")
            val process = ProcessBuilder(binary.absolutePath, "--client", "--transport", "yandex", "--url-stdin", "--socks5", "127.0.0.1:1080", "--debug")
                .directory(noBackupFilesDir).redirectErrorStream(true).start()
            child = process
            if (stopping.get()) { process.destroy(); return }
            // The URL never appears in argv, intent extras, plaintext files or logs.
            process.outputStream.bufferedWriter().use { it.write(url); it.newLine() }
            reader = thread(name = "flus-events") {
                try {
                    process.inputStream.bufferedReader().use { stream ->
                        var lastEvent = ""
                        var lastTime = 0L
                        stream.forEachLine { raw ->
                            if (raw == "FLUS_LISTENING") listening.set(true)
                            if (raw.contains("address already in use", true)) portCollision.set(true)
                            val event = LauncherRules.safeEvent(raw, verbose)
                            if (event != null && (event != lastEvent || System.currentTimeMillis() - lastTime > 3000)) {
                                LauncherState.add(event); lastEvent = event; lastTime = System.currentTimeMillis()
                            }
                        }
                    }
                } catch (_: Exception) { /* No raw exception text is exported. */ }
            }
            val deadline = System.currentTimeMillis() + 15000
            var ready = false
            while (!stopping.get() && process.isAlive && System.currentTimeMillis() < deadline) {
                if (listening.get() && socksHandshake()) { ready = true; break }
                Thread.sleep(150)
            }
            if (stopping.get()) return
            if (!ready) throw LauncherFailure(if (portCollision.get()) "Порт 1080 уже занят. Остановите другое приложение." else "SOCKS5 не запустился. Проверьте журнал и повторите запуск.")
            LauncherState.update("running", "SOCKS5 готов. Доступность VPS не проверена.")
            getSystemService(NotificationManager::class.java).notify(NOTIFICATION, notification("SOCKS5: 127.0.0.1:1080"))
            var consecutiveFailures = 0
            while (!stopping.get() && process.isAlive) {
                if (process.waitFor(3, TimeUnit.SECONDS)) break
                if (socksHandshake()) consecutiveFailures = 0 else consecutiveFailures++
                if (consecutiveFailures >= 3) throw LauncherFailure("Локальный SOCKS5 перестал отвечать. Перезапустите FLUS.")
            }
            if (!stopping.get()) failure = "OpenFlux завершился неожиданно. Проверьте ссылку и сеть, затем нажмите Start."
        } catch (e: LauncherFailure) {
            failure = e.message
        } catch (_: Exception) {
            failure = "Не удалось запустить OpenFlux. Проверьте сборку APK и повторите запуск."
        } finally {
            val process = child
            process?.destroy()
            if (process != null) {
                try { if (!process.waitFor(1500, TimeUnit.MILLISECONDS)) { process.destroyForcibly(); process.waitFor(1500, TimeUnit.MILLISECONDS) } }
                catch (_: Exception) { process.destroyForcibly() }
            }
            child = null
            try { reader?.join(1000) } catch (_: Exception) { }
            releaseWakeLock()
            val finalFailure = failure
            mainHandler.post {
                if (stopping.get() || finalFailure == null) LauncherState.update("stopped", "OpenFlux остановлен")
                else LauncherState.update("error", finalFailure)
                executing.set(false)
                if (!serviceDestroyed) {
                    stopForeground(STOP_FOREGROUND_REMOVE)
                    stopSelf(latestStartId)
                }
            }
        }
    }

    private fun socksHandshake(): Boolean = try {
        Socket().use { socket ->
            socket.connect(InetSocketAddress("127.0.0.1", 1080), 700)
            socket.soTimeout = 700
            socket.getOutputStream().write(byteArrayOf(5, 1, 0))
            socket.getOutputStream().flush()
            val input = socket.getInputStream()
            input.read() == 5 && input.read() == 0
        }
    } catch (_: Exception) { false }

    private fun notification(text: String): Notification {
        val open = PendingIntent.getActivity(this, 0, Intent(this, MainActivity::class.java), PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        val stop = PendingIntent.getService(this, 1, Intent(this, OpenFluxService::class.java).setAction(STOP), PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        return Notification.Builder(this, CHANNEL).setSmallIcon(R.drawable.ic_notification)
            .setContentTitle("FLUS TEST").setContentText(text).setContentIntent(open)
            .setOngoing(true).setOnlyAlertOnce(true)
            .addAction(Notification.Action.Builder(null, "Остановить", stop).build()).build()
    }
    @Synchronized private fun releaseWakeLock() { wakeLock?.let { if (it.isHeld) it.release() }; wakeLock = null }
    override fun onDestroy() {
        serviceDestroyed = true; stopping.set(true); child?.destroyForcibly(); releaseWakeLock()
        super.onDestroy()
    }
    private class LauncherFailure(message: String) : Exception(message)
}
