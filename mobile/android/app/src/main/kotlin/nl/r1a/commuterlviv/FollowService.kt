package nl.r1a.commuterlviv

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import androidx.core.app.ServiceCompat

/**
 * Keeps a followed journey going with the app off the screen.
 *
 * The fixes still come to `MainActivity`'s listener. What this adds is a
 * foreground service of the location type: while it runs, Android delivers
 * them at the rate asked for rather than a few times an hour, and the
 * while-in-use grant covers them, so no background location permission is
 * asked for. Its notification is the one `Notices.following` keeps current.
 */
class FollowService : Service() {
    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val type =
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                ServiceInfo.FOREGROUND_SERVICE_TYPE_LOCATION
            } else {
                0
            }
        try {
            ServiceCompat.startForeground(this, Notices.FOLLOWING, Notices.following(this), type)
        } catch (_: SecurityException) {
            // The location grant went away since the start was asked for
            stopSelf()
        }
        // Not restarted if killed: the follower that fed it is gone with it
        return START_NOT_STICKY
    }
}

/** The two notifications: the one kept up while following, and the alert */
object Notices {
    const val FOLLOWING = 1
    private const val ALERT = 2
    private const val FOLLOWING_CHANNEL = "following"
    private const val ALERT_CHANNEL = "alerts"

    private var title = ""
    private var text = ""

    /** [following] and [alerts] are the names the phone's settings show */
    fun channels(context: Context, following: String, alerts: String) {
        if (title.isEmpty()) title = following
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val manager = context.getSystemService(NotificationManager::class.java)
        manager.createNotificationChannel(
            NotificationChannel(FOLLOWING_CHANNEL, following, NotificationManager.IMPORTANCE_LOW)
        )
        manager.createNotificationChannel(
            NotificationChannel(ALERT_CHANNEL, alerts, NotificationManager.IMPORTANCE_HIGH)
        )
    }

    fun following(context: Context) =
        NotificationCompat.Builder(context, FOLLOWING_CHANNEL)
            .setSmallIcon(R.drawable.ic_follow)
            .setContentTitle(title)
            .setContentText(text)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setCategory(NotificationCompat.CATEGORY_NAVIGATION)
            .setContentIntent(open(context))
            .build()

    /** Says [title] and [text], and with [alert] sounds for it as well */
    fun say(context: Context, title: String, text: String, alert: Boolean) {
        this.title = title
        this.text = text
        val manager = NotificationManagerCompat.from(context)
        if (!manager.areNotificationsEnabled()) return
        try {
            manager.notify(FOLLOWING, following(context))
            if (alert) {
                manager.notify(
                    ALERT,
                    NotificationCompat.Builder(context, ALERT_CHANNEL)
                        .setSmallIcon(R.drawable.ic_follow)
                        .setContentTitle(title)
                        .setContentText(text)
                        .setPriority(NotificationCompat.PRIORITY_HIGH)
                        .setCategory(NotificationCompat.CATEGORY_NAVIGATION)
                        .setAutoCancel(true)
                        .setContentIntent(open(context))
                        .build(),
                )
            }
        } catch (_: SecurityException) {
            // Notifications were refused after the check above
        }
    }

    fun clear(context: Context) {
        NotificationManagerCompat.from(context).cancel(ALERT)
        title = ""
        text = ""
    }

    /** Back to the app as it was left, not a new copy of it */
    private fun open(context: Context): PendingIntent =
        PendingIntent.getActivity(
            context,
            0,
            Intent(context, MainActivity::class.java)
                .setFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_REORDER_TO_FRONT),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )
}
