package io.github.punselie15.shecurity;

import android.app.Activity;
import android.content.Context;
import android.content.SharedPreferences;
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
        if (save(this, b, data != null ? data.getQueryParameter("k") : null,
                data != null ? data.getQueryParameter("e") : null, data != null ? data.getQueryParameter("c") : null)) {
            if ("1".equals(data.getQueryParameter("pin")) && pin(this)) { finish(); return; }
            Toast.makeText(this, "Widget and watch updated", Toast.LENGTH_SHORT).show();
        }
        finish();
    }

    /** Saves the buttons for the widget and hands them to a paired watch. The app also calls this directly. */
    static boolean save(Context c, String b, String key, String e, String caller) {
        if (!valid(b)) return false;
        SharedPreferences prefs = c.getSharedPreferences(QuickWidget.PREFS, MODE_PRIVATE);
        if (key == null || !key.matches("shw_[0-9a-f]{48}")) key = prefs.getString("key", "");
        String emergency = clean(e, "112", 8);
        if (!emergency.matches("[0-9]{2,6}")) emergency = "112";
        caller = clean(caller, "Mom", 30);
        boolean same = b.equals(prefs.getString(QuickWidget.KEY, null)) && emergency.equals(prefs.getString("emergency", null))
                && key.equals(prefs.getString("key", "")) && caller.equals(prefs.getString("caller", null));
        if (same) return true;
        prefs.edit().putString(QuickWidget.KEY, b).putString("key", key).putString("emergency", emergency).putString("caller", caller).apply();
        QuickWidget.refresh(c);
        PutDataMapRequest req = PutDataMapRequest.create("/config");
        req.getDataMap().putString("buttons", b);
        req.getDataMap().putString("key", key);
        req.getDataMap().putString("endpoint", WATCH_ENDPOINT);
        req.getDataMap().putString("emergency", emergency);
        req.getDataMap().putString("caller", caller);
        Wearable.getDataClient(c).putDataItem(req.asPutDataRequest().setUrgent());
        return true;
    }

    /** Asks the launcher to place the widget, on Android 8 and newer. */
    static boolean pin(Context c) {
        if (android.os.Build.VERSION.SDK_INT < 26) return false;
        android.appwidget.AppWidgetManager m = android.appwidget.AppWidgetManager.getInstance(c);
        if (!m.isRequestPinAppWidgetSupported()) return false;
        return m.requestPinAppWidget(new android.content.ComponentName(c, QuickWidget.class), null, null);
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
            String[] parts = item.split(":", 3);
            if (parts.length < 2 || !ACTIONS.contains(parts[0])) return false;
            if (parts[1].isEmpty() || parts[1].length() > 28) return false;
            if (parts.length == 3 && parts[2].length() > 32) return false;
        }
        return true;
    }
}
