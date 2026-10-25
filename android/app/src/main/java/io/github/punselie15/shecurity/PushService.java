package io.github.punselie15.shecurity;

import android.app.Notification;
import android.app.NotificationChannel;
import android.app.NotificationManager;
import android.app.PendingIntent;
import android.content.Context;
import android.content.Intent;
import android.media.AudioAttributes;
import android.media.RingtoneManager;
import android.net.Uri;
import android.os.Build;

import com.google.firebase.FirebaseApp;
import com.google.firebase.messaging.FirebaseMessaging;
import com.google.firebase.messaging.FirebaseMessagingService;
import com.google.firebase.messaging.RemoteMessage;

import java.util.Map;

/**
 * Circle alerts while Shecurity is closed, through Firebase Cloud Messaging. The `notify` edge
 * function sends a data message with title, body, tag and route; this shows it as a loud alert.
 * Without google-services.json in the build, Firebase is not set up and this stays switched off.
 */
public class PushService extends FirebaseMessagingService {
    static final String PREFS = "push", CHANNEL = "circle-alerts";

    static boolean available(Context c) {
        return !FirebaseApp.getApps(c).isEmpty();
    }

    static String token(Context c) {
        return c.getSharedPreferences(PREFS, MODE_PRIVATE).getString("token", "");
    }

    /** Fetches the token once notifications are allowed; the web app reads it through the bridge. */
    static void register(Context c) {
        if (!available(c)) return;
        FirebaseMessaging.getInstance().getToken().addOnSuccessListener(t ->
                c.getSharedPreferences(PREFS, MODE_PRIVATE).edit().putString("token", t).apply());
    }

    @Override
    public void onNewToken(String token) {
        getSharedPreferences(PREFS, MODE_PRIVATE).edit().putString("token", token).apply();
    }

    @Override
    public void onMessageReceived(RemoteMessage msg) {
        Map<String, String> d = msg.getData();
        String title = d.containsKey("title") ? d.get("title") : (msg.getNotification() != null ? msg.getNotification().getTitle() : "Shecurity");
        String body = d.containsKey("body") ? d.get("body") : (msg.getNotification() != null ? msg.getNotification().getBody() : "");
        String route = d.containsKey("route") ? d.get("route") : "circle";
        if (route == null || !route.matches("[A-Za-z0-9_-]{1,40}")) route = "circle";
        String tag = d.containsKey("tag") ? d.get("tag") : "alert";
        show(this, title, body, route, tag);
    }

    static void show(Context c, String title, String body, String route, String tag) {
        NotificationManager nm = c.getSystemService(NotificationManager.class);
        if (nm == null) return;
        if (Build.VERSION.SDK_INT >= 26 && nm.getNotificationChannel(CHANNEL) == null) {
            NotificationChannel ch = new NotificationChannel(CHANNEL, "Alerts from your circle", NotificationManager.IMPORTANCE_HIGH);
            ch.setDescription("When someone in your circle sends an SOS or shares where they are");
            ch.enableVibration(true);
            ch.setVibrationPattern(new long[] { 0, 400, 200, 400, 200, 400 });
            ch.setSound(RingtoneManager.getDefaultUri(RingtoneManager.TYPE_ALARM),
                    new AudioAttributes.Builder().setUsage(AudioAttributes.USAGE_ALARM).build());
            nm.createNotificationChannel(ch);
        }
        Intent open = new Intent(Intent.ACTION_VIEW, Uri.parse(LauncherActivity.HOME + "#" + route), c, LauncherActivity.class);
        open.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK | Intent.FLAG_ACTIVITY_CLEAR_TOP);
        PendingIntent pi = PendingIntent.getActivity(c, tag.hashCode(), open,
                PendingIntent.FLAG_UPDATE_CURRENT | PendingIntent.FLAG_IMMUTABLE);
        Notification.Builder b = Build.VERSION.SDK_INT >= 26 ? new Notification.Builder(c, CHANNEL) : new Notification.Builder(c);
        b.setSmallIcon(R.drawable.ic_notification_icon)
                .setContentTitle(title)
                .setContentText(body)
                .setStyle(new Notification.BigTextStyle().bigText(body))
                .setColor(0xFFE5487F)
                .setCategory(Notification.CATEGORY_ALARM)
                .setPriority(Notification.PRIORITY_MAX)
                .setAutoCancel(true)
                .setContentIntent(pi);
        nm.notify(tag, 1, b.build());
    }
}
