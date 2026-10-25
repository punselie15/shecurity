package io.github.punselie15.shecurity;

import android.app.Activity;
import android.net.Uri;
import android.os.Bundle;
import android.widget.Toast;

/** Receives the widget buttons chosen in the app (shecurity://widget?b=...), saves them and closes. */
public class WidgetSyncActivity extends Activity {
    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        Uri data = getIntent().getData();
        String b = data != null ? data.getQueryParameter("b") : null;
        if (valid(b)) {
            getSharedPreferences(QuickWidget.PREFS, MODE_PRIVATE).edit().putString(QuickWidget.KEY, b).apply();
            QuickWidget.refresh(this);
            Toast.makeText(this, "Widget updated", Toast.LENGTH_SHORT).show();
        }
        finish();
    }

    private static final java.util.List<String> ACTIONS = java.util.Arrays.asList(
            "help", "location", "fakecall-now", "call", "siren", "walk", "timer", "fakecall", "plan", "ride", "date", "record", "lines");

    /** Only known actions, four of them, with short plain labels. */
    private static boolean valid(String b) {
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
