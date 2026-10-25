package io.github.punselie15.shecurity;

import android.app.Activity;
import android.net.Uri;
import android.os.Bundle;
import android.widget.Toast;

import com.google.android.gms.wearable.PutDataMapRequest;
import com.google.android.gms.wearable.Wearable;

/**
 * Receives the buttons chosen in the app (shecurity://widget?b=...&k=...), saves them for the
 * home-screen widget, passes them on to a paired Wear OS watch, and closes.
 */
public class WidgetSyncActivity extends Activity {
    static final String WATCH_ENDPOINT = "https://cgihqwekhbyhhadoizeb.supabase.co/functions/v1/watch-alert";

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        Uri data = getIntent().getData();
        String b = data != null ? data.getQueryParameter("b") : null;
        if (valid(b)) {
            String key = data.getQueryParameter("k");
            if (key == null || !key.matches("shw_[0-9a-f]{48}")) key = getSharedPreferences(QuickWidget.PREFS, MODE_PRIVATE).getString("key", "");
            String emergency = clean(data.getQueryParameter("e"), "112", 8);
            String caller = clean(data.getQueryParameter("c"), "Mom", 30);
            getSharedPreferences(QuickWidget.PREFS, MODE_PRIVATE).edit()
                    .putString(QuickWidget.KEY, b).putString("key", key).apply();
            QuickWidget.refresh(this);
            PutDataMapRequest req = PutDataMapRequest.create("/config");
            req.getDataMap().putString("buttons", b);
            req.getDataMap().putString("key", key);
            req.getDataMap().putString("endpoint", WATCH_ENDPOINT);
            req.getDataMap().putString("emergency", emergency);
            req.getDataMap().putString("caller", caller);
            Wearable.getDataClient(this).putDataItem(req.asPutDataRequest().setUrgent());
            Toast.makeText(this, "Widget and watch updated", Toast.LENGTH_SHORT).show();
        }
        finish();
    }

    private static String clean(String v, String fallback, int max) {
        if (v == null) return fallback;
        v = v.replaceAll("[\\p{Cntrl}<>]", "").trim();
        return v.isEmpty() || v.length() > max ? fallback : v;
    }

    private static final java.util.List<String> ACTIONS = java.util.Arrays.asList(
            "help", "location", "fakecall-now", "call", "siren", "walk", "timer", "fakecall", "plan", "ride", "date", "record", "lines");

    /** Only known actions, four of them, with short plain labels. */
    static boolean valid(String b) {
        if (b == null) return false;
        String[] list = b.split("\\|");
        if (list.length != 4) return false;
        for (String item : list) {
            String[] parts = item.split(":", 2);
            if (parts.length != 2 || !ACTIONS.contains(parts[0])) return false;
            if (parts[1].isEmpty() || parts[1].length() > 24) return false;
        }
        return true;
    }
}
