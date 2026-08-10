package com.fitlog.app.reminder

import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.Context
import android.os.Build
import androidx.core.app.NotificationCompat
import androidx.work.CoroutineWorker
import androidx.work.ExistingPeriodicWorkPolicy
import androidx.work.PeriodicWorkRequestBuilder
import androidx.work.WorkManager
import androidx.work.WorkerParameters
import com.fitlog.app.data.Graph
import com.fitlog.app.data.ReminderTarget
import java.util.concurrent.TimeUnit

/** 周期检查：有哪些动作超过了设定的间隔，发本地通知提醒。 */
class ReminderWorker(ctx: Context, params: WorkerParameters) : CoroutineWorker(ctx, params) {

    override suspend fun doWork(): Result {
        Graph.init(applicationContext)
        val targets = Graph.repository.getReminderTargets(System.currentTimeMillis())
        if (targets.isNotEmpty()) postNotification(targets)
        return Result.success()
    }

    private fun postNotification(targets: List<ReminderTarget>) {
        val nm = applicationContext.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        ensureChannel(nm)
        val notification = if (targets.size == 1) {
            val t = targets[0]
            val days = t.elapsedHours / 24
            val body = if (days >= 1) {
                "已 ${days} 天没练了，该练『${t.exercise.name}』啦"
            } else {
                "已 ${t.elapsedHours} 小时没练了，该练『${t.exercise.name}』啦"
            }
            build("训练提醒", body)
        } else {
            val lines = targets.take(5).joinToString("\n") { "· ${it.exercise.name}" }
            val more = if (targets.size > 5) "\n…等 ${targets.size} 个动作" else ""
            build("该去训练啦", "有 ${targets.size} 个动作该练了：\n$lines$more")
        }
        nm.notify(NOTIF_ID, notification)
    }

    private fun build(title: String, text: String) = NotificationCompat.Builder(applicationContext, CHANNEL_ID)
        .setSmallIcon(android.R.drawable.ic_dialog_info)
        .setContentTitle(title)
        .setContentText(text)
        .setStyle(NotificationCompat.BigTextStyle().bigText(text))
        .setPriority(NotificationCompat.PRIORITY_DEFAULT)
        .setAutoCancel(true)
        .build()

    private fun ensureChannel(nm: NotificationManager) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val ch = NotificationChannel(
                CHANNEL_ID, "训练提醒", NotificationManager.IMPORTANCE_DEFAULT
            )
            nm.createNotificationChannel(ch)
        }
    }

    companion object {
        const val CHANNEL_ID = "fitlog_reminder"
        const val NOTIF_ID = 1001
    }
}

object ReminderScheduler {
    private const val WORK_NAME = "fitlog_reminder_work"

    /** 每 6 小时检查一次（首次延迟 1 小时）。WorkManager 会自动在重启后恢复。 */
    fun schedule(context: Context) {
        val request = PeriodicWorkRequestBuilder<ReminderWorker>(6, TimeUnit.HOURS)
            .setInitialDelay(1, TimeUnit.HOURS)
            .build()
        WorkManager.getInstance(context).enqueueUniquePeriodicWork(
            WORK_NAME, ExistingPeriodicWorkPolicy.UPDATE, request
        )
    }
}
