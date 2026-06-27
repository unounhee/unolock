package com.unolock.unolock_app

import android.app.ActivityManager
import android.content.Context
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
                    else -> result.notImplemented()
                }
            }
    }
}
