package com.unolock.unolock_app

import android.app.ActivityManager
import android.content.Context
import android.content.Intent
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    // Flutter(화면)와 안드로이드(잠금 기능)를 연결하는 통로 이름
    private val channelName = "unolock/lock"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    // 화면 고정 시작 (Screen Pinning)
                    "lock" -> {
                        try {
                            startLockTask()
                            result.success(true)
                        } catch (e: Exception) {
                            result.error("LOCK_FAILED", e.message, null)
                        }
                    }
                    // 화면 고정 해제
                    "unlock" -> {
                        try {
                            stopLockTask()
                            result.success(true)
                        } catch (e: Exception) {
                            result.error("UNLOCK_FAILED", e.message, null)
                        }
                    }
                    // 지금 고정된 상태인지 확인
                    "isLocked" -> {
                        val am = getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager
                        val locked = am.lockTaskModeState != ActivityManager.LOCK_TASK_MODE_NONE
                        result.success(locked)
                    }
                    // 폰에 깔린 "실행 가능한 앱"(런처 아이콘 있는 것) 목록
                    "listApps" -> {
                        try {
                            val pm = packageManager
                            val intent = Intent(Intent.ACTION_MAIN, null)
                                .addCategory(Intent.CATEGORY_LAUNCHER)
                            val acts = pm.queryIntentActivities(intent, 0)
                            val apps = acts
                                .map { ri ->
                                    mapOf(
                                        "name" to ri.loadLabel(pm).toString(),
                                        "package" to ri.activityInfo.packageName,
                                    )
                                }
                                .distinctBy { it["package"] }
                                .sortedBy { (it["name"] ?: "").lowercase() }
                            result.success(apps)
                        } catch (e: Exception) {
                            result.error("LIST_FAILED", e.message, null)
                        }
                    }
                    // 접근성 설정 화면 열기 (사용자가 직접 켜야 함)
                    "openAccessibilitySettings" -> {
                        startActivity(Intent(Settings.ACTION_ACCESSIBILITY_SETTINGS))
                        result.success(true)
                    }
                    // 우리 접근성 서비스가 켜져 있나?
                    "isAccessibilityEnabled" -> {
                        val expected = "$packageName/$packageName.BlockerService"
                        val enabled = Settings.Secure.getString(
                            contentResolver,
                            Settings.Secure.ENABLED_ACCESSIBILITY_SERVICES,
                        ) ?: ""
                        val on = enabled.split(':').any { it.equals(expected, true) }
                        result.success(on)
                    }
                    // 막을 앱 1개 지정(실험용)
                    "setBlockedPackage" -> {
                        val pkg = call.argument<String>("package")
                        getSharedPreferences("unolock_blocker", Context.MODE_PRIVATE)
                            .edit().putString("blocked_package", pkg).apply()
                        result.success(true)
                    }
                    "getBlockedPackage" -> {
                        val pkg = getSharedPreferences("unolock_blocker", Context.MODE_PRIVATE)
                            .getString("blocked_package", null)
                        result.success(pkg)
                    }
                    else -> result.notImplemented()
                }
            }
    }
}
