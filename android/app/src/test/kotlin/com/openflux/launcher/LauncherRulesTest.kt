package com.openflux.launcher

import org.junit.Assert.*
import org.junit.Test

class LauncherRulesTest {
    @Test fun validatesHostAndHttps() {
        assertNotNull(LauncherRules.validate(""))
        assertNotNull(LauncherRules.validate("http://disk.yandex.ru/edit/d/test"))
        assertNotNull(LauncherRules.validate("https://disk.yandex.ru.evil.example/edit/d/test"))
        assertNotNull(LauncherRules.validate("https://u@disk.yandex.ru/edit/d/test"))
        assertNotNull(LauncherRules.validate("https://disk.yandex.ru:8080/edit/d/test"))
        assertNull(LauncherRules.validate("https://disk.yandex.ru/edit/d/test"))
        assertNull(LauncherRules.validate("https://disk.yandex.com/i/test"))
    }
    @Test fun logsNeverExposeUpstreamSecrets() {
        val privateValue = "synthetic-test-secret"
        assertNull(LauncherRules.safeEvent("token=$privateValue", true))
        val result = LauncherRules.safeEvent("fetchDocInfo failed: https://disk.yandex.ru/edit/d/test?sk=$privateValue", true)
        assertNotNull(result)
        assertFalse(result!!.contains(privateValue))
        assertFalse(result.contains("https://"))
        assertEquals("SOCKS5 слушает 127.0.0.1:1080", LauncherRules.safeEvent("FLUS_LISTENING", false))
    }
    @Test fun logsAreBoundedAndClearable() {
        LauncherState.clear()
        repeat(500) { LauncherState.add("safe event") }
        assertEquals(400, (LauncherState.snapshot()["logs"] as List<*>).size)
        LauncherState.clear()
        assertEquals(0, (LauncherState.snapshot()["logs"] as List<*>).size)
    }
}
