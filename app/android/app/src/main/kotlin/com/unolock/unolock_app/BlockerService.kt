package com.unolock.unolock_app

import android.accessibilityservice.AccessibilityService
import android.content.Context
import android.view.accessibility.AccessibilityEvent
import android.widget.Toast

// 접근성 서비스: 화면에 뜬 앱을 감지해서, "막을 앱"이면 홈으로 튕겨낸다.
// (실험 단계: SharedPreferences 의 blocked_package 하나만 막는다. 안전.)
class BlockerService : AccessibilityService() {

    override fun onAccessibilityEvent(event: AccessibilityEvent?) {
        if (event == null) return
        if (event.eventType != AccessibilityEvent.TYPE_WINDOW_STATE_CHANGED) return

        val pkg = event.packageName?.toString() ?: return
        if (pkg == packageName) return // 우리 앱은 절대 안 막음

        val prefs = getSharedPreferences("unolock_blocker", Context.MODE_PRIVATE)
        val blocked = prefs.getString("blocked_package", null) ?: return

        if (pkg == blocked) {
            performGlobalAction(GLOBAL_ACTION_HOME)
            Toast.makeText(this, "이 앱은 지금 막혀 있어요", Toast.LENGTH_SHORT).show()
        }
    }

    override fun onInterrupt() {}
}
