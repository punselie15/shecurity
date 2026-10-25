package io.github.punselie15.shecurity;

import android.content.Intent;
import android.net.Uri;

import com.google.android.gms.wearable.MessageEvent;
import com.google.android.gms.wearable.WearableListenerService;

import org.json.JSONObject;

import java.io.OutputStream;
import java.net.HttpURLConnection;
import java.net.URL;
import java.nio.charset.StandardCharsets;

/** When the watch can't get online, it hands its SOS or location to the phone, which sends it instead. */
public class WatchListenerService extends WearableListenerService {
    @Override
    public void onMessageReceived(MessageEvent event) {
        if (!"/action".equals(event.getPath())) return;
        String action = new String(event.getData(), StandardCharsets.UTF_8);
        if ("help".equals(action) || "location".equals(action)) {
            String key = getSharedPreferences(QuickWidget.PREFS, MODE_PRIVATE).getString("key", "");
            if (key.matches("shw_[0-9a-f]{48}") && post(key, "help".equals(action) ? "sos" : "location")) return;
        }
        if (!WidgetSyncActivity.valid(action + ":x|location:x|location:x|location:x")) return;
        // other actions open the app; Android may only allow this while the phone is in use
        Intent open = new Intent(Intent.ACTION_VIEW, Uri.parse("https://shecurity.app/app/?android=3#q-" + action),
                this, LauncherActivity.class).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
        try { startActivity(open); } catch (Exception ignored) { }
    }

    private static boolean post(String key, String kind) {
        try {
            HttpURLConnection c = (HttpURLConnection) new URL(WidgetSyncActivity.WATCH_ENDPOINT).openConnection();
            c.setConnectTimeout(10000); c.setReadTimeout(15000);
            c.setRequestMethod("POST"); c.setDoOutput(true);
            c.setRequestProperty("Content-Type", "application/json");
            byte[] body = new JSONObject().put("key", key).put("kind", kind).put("message", "Sent from her watch through her phone").toString().getBytes(StandardCharsets.UTF_8);
            try (OutputStream out = c.getOutputStream()) { out.write(body); }
            boolean ok = c.getResponseCode() == 200;
            c.disconnect();
            return ok;
        } catch (Exception e) {
            return false;
        }
    }
}
