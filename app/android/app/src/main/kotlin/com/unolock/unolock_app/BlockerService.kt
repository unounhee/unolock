package com.unolock.unolock_app

import android.accessibilityservice.AccessibilityService
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.view.accessibility.AccessibilityEvent
import android.widget.Toast

// 접근성 서비스: 차단 모드가 켜지면 "허용 앱만 통과", 나머지는 홈으로 튕긴다.
// 안전장치: 우리 앱 / 홈 런처 / 시스템UI / 설정 은 항상 통과(폰이 잠겨버리지 않게).
class BlockerService : AccessibilityService() {

    private var homePackage: String? = null

    private val alwaysAllow = setOf(
        "com.android.systemui",
        "com.android.settings",
        "com.samsung.android.settings",
    )

    override fun onServiceConnected() {
        super.onServiceConnected()
        val intent = Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_HOME)
        val ri = packageManager.resolveActivity(intent, PackageManager.MATCH_DEFAULT_ONLY)
        homePackage = ri?.activityInfo?.packageName
    }

    override fun onAccessibilityEvent(event: AccessibilityEvent?) {
        if (event == null) return
        if (event.eventType != AccessibilityEvent.TYPE_WINDOW_STATE_CHANGED) return

        val prefs = getSharedPreferences("unolock_blocker", Context.MODE_PRIVATE)
        if (!prefs.getBoolean("block_mode", false)) return

        val pkg = event.packageName?.toString() ?: return
        if (pkg == packageName) return            // 우리 앱
        if (pkg == homePackage) return            // 홈 화면
        if (pkg in alwaysAllow) return            // 시스템UI/설정

        val raw = prefs.getString("allowed_packages", "") ?: ""
        val allowed = if (raw.isEmpty()) emptyList() else raw.split(",")
        if (pkg in allowed) return                // 허용된 앱

        // 그 외 → 차단
        performGlobalAction(GLOBAL_ACTION_HOME)
        Toast.makeText(this, "지금은 막혀 있는 앱이에요", Toast.LENGTH_SHORT).show()
    }

    override fun onInterrupt() {}
}
