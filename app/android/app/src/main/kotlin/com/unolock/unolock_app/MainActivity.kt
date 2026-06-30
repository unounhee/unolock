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
                    // 차단 모드 켜기/끄기 (켜면 "허용 앱만 통과")
                    "setBlockMode" -> {
                        val on = call.argument<Boolean>("on") ?: false
                        getSharedPreferences("unolock_blocker", Context.MODE_PRIVATE)
                            .edit().putBoolean("block_mode", on).apply()
                        result.success(true)
                    }
                    "getBlockMode" -> {
                        val on = getSharedPreferences("unolock_blocker", Context.MODE_PRIVATE)
                            .getBoolean("block_mode", false)
                        result.success(on)
                    }
                    // 허용 앱 목록 저장/조회 (이 앱들만 통과)
                    "setAllowedPackages" -> {
                        val list = call.argument<List<String>>("packages") ?: emptyList()
                        getSharedPreferences("unolock_blocker", Context.MODE_PRIVATE)
                            .edit().putString("allowed_packages", list.joinToString(",")).apply()
                        result.success(true)
                    }
                    "getAllowedPackages" -> {
                        val s = getSharedPreferences("unolock_blocker", Context.MODE_PRIVATE)
                            .getString("allowed_packages", "") ?: ""
                        val list = if (s.isEmpty()) emptyList() else s.split(",")
                        result.success(list)
                    }
                    // 보상 시간 시작: 지금부터 minutes분 동안 전부 자유
                    "startReward" -> {
                        val minutes = call.argument<Int>("minutes") ?: 0
                        val until = System.currentTimeMillis() + minutes * 60000L
                        getSharedPreferences("unolock_blocker", Context.MODE_PRIVATE)
                            .edit().putLong("reward_until", until).apply()
                        result.success(until)
                    }
                    // 남은 보상 시간(ms)
                    "getRewardRemaining" -> {
                        val until = getSharedPreferences("unolock_blocker", Context.MODE_PRIVATE)
                            .getLong("reward_until", 0L)
                        val remain = (until - System.currentTimeMillis()).coerceAtLeast(0)
                        result.success(remain)
                    }
                    // 보상 시간 즉시 종료
                    "endReward" -> {
                        getSharedPreferences("unolock_blocker", Context.MODE_PRIVATE)
                            .edit().putLong("reward_until", 0L).apply()
                        result.success(true)
                    }
                    // 보상 시간을 "절대 시각(epoch ms)"으로 지정.
                    // 모든 미션 완료 → 오늘 잠금시각까지 자유 줄 때 사용.
                    "startRewardUntil" -> {
                        val until = (call.argument<Any>("until") as? Number)?.toLong() ?: 0L
                        getSharedPreferences("unolock_blocker", Context.MODE_PRIVATE)
                            .edit().putLong("reward_until", until).apply()
                        result.success(until)
                    }
                    // 매일 잠금 시각(hour:minute) 저장 — 부모 설정의 "로컬 사본".
                    // 인터넷이 없어도 폰은 이 로컬 값으로 잠긴다. (서버 동기화는 17-7)
                    "setLockTime" -> {
                        val hour = call.argument<Int>("hour") ?: -1
                        val minute = call.argument<Int>("minute") ?: 0
                        getSharedPreferences("unolock_blocker", Context.MODE_PRIVATE)
                            .edit().putInt("lock_hour", hour).putInt("lock_minute", minute)
                            .apply()
                        result.success(true)
                    }
                    "getLockTime" -> {
                        val p = getSharedPreferences("unolock_blocker", Context.MODE_PRIVATE)
                        result.success(
                            mapOf(
                                "hour" to p.getInt("lock_hour", -1),  // -1 = 아직 설정 안 함
                                "minute" to p.getInt("lock_minute", 0),
                            )
                        )
                    }
                    else -> result.notImplemented()
                }
            }
    }
}
