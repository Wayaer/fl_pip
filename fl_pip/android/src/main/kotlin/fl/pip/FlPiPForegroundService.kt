package fl.pip

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder
import android.util.Log

/**
 * 只要还有至少一个画中画悬浮窗或媒体窗口可见，就通过前台服务保活进程。
 *
 * 说明：悬浮窗使用 specialUse 类型，媒体窗口使用 mediaPlayback 类型；为避免 Android 14
 * 运行时切换前台服务类型失败，这里始终以两种类型的组合启动。
 *
 * Keeps the process alive while at least one PiP overlay or media window is visible.
 */
class FlPiPForegroundService : Service() {
    companion object {
        private const val TAG = "FlPiPService"
        private const val CHANNEL_ID = "fl_pip_foreground"
        private const val NOTIFICATION_ID = 4202
        private const val EXTRA_MEDIA = "fl_pip_media"
        private var running = false
        private var runningAsMedia = false

        fun start(context: Context, media: Boolean = false) {
            if (running && runningAsMedia == media) return
            val intent = Intent(context, FlPiPForegroundService::class.java).putExtra(EXTRA_MEDIA, media)
            try {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    context.startForegroundService(intent)
                } else {
                    context.startService(intent)
                }
                running = true
                runningAsMedia = media
            } catch (exception: Exception) {
                // 后台启动前台服务可能被系统拒绝（Android 12+）；窗口仍然可用，不能让调用方崩溃。
                // Starting a foreground service from the background may be rejected; keep the window
                // usable instead of crashing the caller.
                Log.w(TAG, "Unable to start the foreground service", exception)
                running = false
                runningAsMedia = false
            }
        }

        fun stop(context: Context) {
            running = false
            runningAsMedia = false
            context.stopService(Intent(context, FlPiPForegroundService::class.java))
        }
    }

    private var media = false

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        media = intent?.getBooleanExtra(EXTRA_MEDIA, media) ?: media
        startForegroundNotification()
        return START_STICKY
    }

    private fun startForegroundNotification() {
        val notification = buildNotification()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            // 同时声明两种类型，后续媒体窗口/悬浮窗切换时无需重新启动服务。
            // Declare both types so switching between media and overlay never restarts the service.
            val type = ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE or
                ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PLAYBACK
            startForeground(NOTIFICATION_ID, notification, type)
        } else {
            startForeground(NOTIFICATION_ID, notification)
        }
    }

    private fun buildNotification(): Notification {
        val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(CHANNEL_ID, "Picture in picture", NotificationManager.IMPORTANCE_LOW)
            manager.createNotificationChannel(channel)
        }

        val launchIntent = packageManager.getLaunchIntentForPackage(packageName)
        val pendingIntent = launchIntent?.let {
            PendingIntent.getActivity(
                this,
                0,
                it,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
            )
        }

        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(this, CHANNEL_ID)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(this)
        }
        builder.setSmallIcon(android.R.drawable.ic_media_play)
            .setContentTitle(if (media) "Media playback" else "Picture in picture")
            .setContentText(
                if (media) "The media window is running" else "The picture-in-picture window is running",
            )
            .setOngoing(true)
        pendingIntent?.let(builder::setContentIntent)
        return builder.build()
    }

    override fun onDestroy() {
        running = false
        runningAsMedia = false
        super.onDestroy()
    }

    override fun onBind(intent: Intent?): IBinder? = null
}
