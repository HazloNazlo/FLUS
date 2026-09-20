package com.openflux.launcher

import java.net.URI
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

object LauncherRules {
    fun validate(value: String): String? {
        if (value.isBlank()) return "URL пустой. Вставьте Yandex / Mail.ru URL."
        if (value.length > 16384 || value.any { it.isISOControl() }) return "Некорректная ссылка."
        val uri = try { URI(value) } catch (_: Exception) { return "Некорректная ссылка." }
        if (uri.scheme != "https" || uri.rawUserInfo != null) return "URL должен начинаться с https://"
        if (uri.host !in listOf("disk.yandex.ru", "disk.yandex.com", "cloud.mail.ru", "doc.mail.ru") || uri.port !in listOf(-1, 443))
            return "Используйте HTTPS-ссылку disk.yandex.ru, cloud.mail.ru или doc.mail.ru."
        return null
    }

    /** Allowlist only. Unknown upstream logs are discarded, not regex-redacted. */
    fun safeEvent(line: String, verbose: Boolean): String? = when {
        line == "FLUS_LISTENING" -> "SOCKS5 слушает 127.0.0.1:1080"
        line.contains("address already in use", true) -> "Порт 1080 уже занят. Остановите другое приложение."
        line.contains("websocket", true) && (line.contains("error", true) || line.contains("failed", true) || line.contains("close", true)) -> "Ошибка WebSocket. Проверьте ссылку, сеть и exit-node."
        line.contains("Auth OK") -> "Подключение к документу успешно установлено!"
        line.contains("fetchDocInfo failed") -> "Не удалось открыть документ. Проверьте edit-ссылку и права доступа."
        line.contains("panic:") -> "Внутренняя ошибка OpenFlux."
        line.contains("Failed to start transport") -> "Не удалось запустить транспорт."
        verbose && line.contains("connectToDoc attempt") -> "Попытка подключения к документу"
        verbose && line.contains("Keep-alive failed") -> "Соединение с транспортом потеряно"
        else -> null
    }
}

object LauncherState {
    private var state = "stopped"
    private var detail = "Готов к запуску"
    private val logs = ArrayDeque<String>()
    @Synchronized fun isActive() = state in listOf("starting", "running", "stopping")
    @Synchronized fun update(value: String, text: String) { state = value; detail = text; add(text) }
    @Synchronized fun add(text: String) {
        val stamp = SimpleDateFormat("HH:mm:ss", Locale.ROOT).format(Date())
        logs.addLast("$stamp  $text")
        while (logs.size > 400) logs.removeFirst()
    }
    @Synchronized fun clear() = logs.clear()
    @Synchronized fun snapshot(): Map<String, Any> = mapOf("state" to state, "detail" to detail, "logs" to logs.toList())
}
