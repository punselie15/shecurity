package io.github.punselie15.shecurity.wear;

import android.Manifest;
import android.app.Activity;
import android.content.Intent;
import android.content.pm.PackageManager;
import android.graphics.Color;
import android.graphics.Typeface;
import android.graphics.drawable.GradientDrawable;
import android.location.Location;
import android.location.LocationManager;
import android.net.Uri;
import android.os.BatteryManager;
import android.os.Bundle;
import android.os.Handler;
import android.os.Looper;
import android.os.VibrationEffect;
import android.os.Vibrator;
import android.view.Gravity;
import android.view.MotionEvent;
import android.view.View;
import android.widget.Button;
import android.widget.GridLayout;
import android.widget.LinearLayout;
import android.widget.ScrollView;
import android.widget.TextView;

import com.google.android.gms.wearable.DataClient;
import com.google.android.gms.wearable.DataEvent;
import com.google.android.gms.wearable.DataEventBuffer;
import com.google.android.gms.wearable.DataItem;
import com.google.android.gms.wearable.DataMapItem;
import com.google.android.gms.wearable.Node;
import com.google.android.gms.wearable.Wearable;

import org.json.JSONObject;

import java.io.OutputStream;
import java.net.HttpURLConnection;
import java.net.URL;
import java.nio.charset.StandardCharsets;

/** Hold SOS to alert your circle, or tap one of the four buttons chosen in the phone app. */
public class MainActivity extends Activity implements DataClient.OnDataChangedListener {
    static final int PINK = Color.parseColor("#E5487F"), INK = Color.parseColor("#2A2152");
    private final Handler main = new Handler(Looper.getMainLooper());
    private LinearLayout root;
    private TextView status;
    private Config config;
    private Runnable countdown;

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        config = Config.load(this);
        build();
        if (checkSelfPermission(Manifest.permission.ACCESS_FINE_LOCATION) != PackageManager.PERMISSION_GRANTED) {
            requestPermissions(new String[] { Manifest.permission.ACCESS_FINE_LOCATION, Manifest.permission.ACCESS_COARSE_LOCATION }, 1);
        }
        Wearable.getDataClient(this).getDataItems().addOnSuccessListener(items -> {
            for (DataItem item : items) save(item);
            items.release();
        });
    }

    @Override protected void onResume() { super.onResume(); Wearable.getDataClient(this).addListener(this); }
    @Override protected void onPause() { super.onPause(); Wearable.getDataClient(this).removeListener(this); }

    @Override
    public void onDataChanged(DataEventBuffer events) {
        for (DataEvent e : events) if (e.getType() == DataEvent.TYPE_CHANGED) save(e.getDataItem());
    }

    private void save(DataItem item) {
        if (!"/config".equals(item.getUri().getPath())) return;
        com.google.android.gms.wearable.DataMap m = DataMapItem.fromDataItem(item).getDataMap();
        getSharedPreferences(Config.PREFS, MODE_PRIVATE).edit()
                .putString("buttons", m.getString("buttons", Config.STANDARD))
                .putString("key", m.getString("key", ""))
                .putString("endpoint", m.getString("endpoint", ""))
                .putString("apikey", m.getString("apikey", ""))
                .putString("emergency", m.getString("emergency", "112"))
                .putString("caller", m.getString("caller", "Mom"))
                .apply();
        config = Config.load(this);
        main.post(this::build);
    }

    private int dp(int v) { return Math.round(v * getResources().getDisplayMetrics().density); }

    private void build() {
        ScrollView scroll = new ScrollView(this);
        scroll.setBackgroundColor(Color.BLACK);
        root = new LinearLayout(this);
        root.setOrientation(LinearLayout.VERTICAL);
        root.setGravity(Gravity.CENTER_HORIZONTAL);
        root.setPadding(dp(14), dp(22), dp(14), dp(30));
        scroll.addView(root);

        TextView sos = new TextView(this);
        sos.setText("SOS");
        sos.setTextColor(Color.WHITE);
        sos.setTextSize(24);
        sos.setTypeface(Typeface.DEFAULT_BOLD);
        sos.setGravity(Gravity.CENTER);
        GradientDrawable circle = new GradientDrawable();
        circle.setShape(GradientDrawable.OVAL);
        circle.setColor(PINK);
        circle.setStroke(dp(6), Color.WHITE);
        sos.setBackground(circle);
        sos.setContentDescription("SOS. Press and hold to alert your circle");
        LinearLayout.LayoutParams lp = new LinearLayout.LayoutParams(dp(110), dp(110));
        root.addView(sos, lp);
        holdToSend(sos);

        status = new TextView(this);
        status.setText(config.linked() ? "Hold to alert your circle" : "Open Shecurity on your phone to link this watch");
        status.setTextColor(Color.LTGRAY);
        status.setTextSize(12);
        status.setGravity(Gravity.CENTER);
        status.setPadding(0, dp(6), 0, dp(8));
        root.addView(status);

        GridLayout grid = new GridLayout(this);
        grid.setColumnCount(2);
        for (int i = 0; i < 4; i++) {
            String[] parts = config.buttons[i].split(":", 2);
            final String id = parts[0];
            Button b = new Button(this);
            b.setText(parts.length > 1 ? parts[1] : id);
            b.setAllCaps(false);
            b.setTextSize(12);
            b.setTypeface(Typeface.DEFAULT_BOLD);
            boolean pinkCell = i == 0 || i == 3;
            b.setTextColor(pinkCell ? Color.WHITE : INK);
            GradientDrawable bg = new GradientDrawable();
            bg.setCornerRadius(dp(16));
            bg.setColor(pinkCell ? PINK : Color.WHITE);
            b.setBackground(bg);
            GridLayout.LayoutParams g = new GridLayout.LayoutParams(GridLayout.spec(i / 2, 1f), GridLayout.spec(i % 2, 1f));
            g.width = 0; g.height = dp(56);
            g.setMargins(dp(3), dp(3), dp(3), dp(3));
            b.setOnClickListener(v -> run(id));
            grid.addView(b, g);
        }
        root.addView(grid, new LinearLayout.LayoutParams(LinearLayout.LayoutParams.MATCH_PARENT, LinearLayout.LayoutParams.WRAP_CONTENT));
        setContentView(scroll);
    }

    private void holdToSend(View v) {
        final Runnable fire = () -> { buzz(new long[] { 0, 400 }); send("sos"); };
        v.setOnTouchListener((view, e) -> {
            if (e.getAction() == MotionEvent.ACTION_DOWN) { buzz(new long[] { 0, 60 }); status.setText("Keep holding…"); main.postDelayed(fire, 1500); return true; }
            if (e.getAction() == MotionEvent.ACTION_UP || e.getAction() == MotionEvent.ACTION_CANCEL) {
                main.removeCallbacks(fire);
                if ("Keep holding…".contentEquals(status.getText())) status.setText("Hold to alert your circle");
                return true;
            }
            return false;
        });
    }

    private void run(String id) {
        switch (id) {
            case "help": startCountdown(5); break;
            case "location": send("location"); break;
            case "call": callEmergency(); break;
            case "fakecall-now": case "fakecall":
                status.setText("Your watch rings in 5 seconds");
                main.postDelayed(() -> startActivity(new Intent(this, CallActivity.class).putExtra("caller", config.caller)), 5000);
                break;
            default: askPhone(id); status.setText("Opened on your phone");
        }
    }

    private void startCountdown(int left) {
        if (left <= 0) { send("sos"); return; }
        status.setText("Alerting your circle in " + left + "… tap SOS area to cancel");
        buzz(new long[] { 0, 80 });
        countdown = () -> startCountdown(left - 1);
        main.postDelayed(countdown, 1000);
        root.setOnClickListener(v -> { main.removeCallbacks(countdown); status.setText("Cancelled. Nothing was sent."); root.setOnClickListener(null); });
    }

    private void callEmergency() {
        String digits = config.emergency.replaceAll("[^0-9]", "");
        try { startActivity(new Intent(Intent.ACTION_DIAL, Uri.parse("tel:" + (digits.isEmpty() ? "112" : digits)))); }
        catch (Exception e) { status.setText("Call " + config.emergency + " from your phone"); }
    }

    private void send(String kind) {
        status.setText("Sending…");
        new Thread(() -> {
            boolean ok = false;
            if (config.linked()) {
                try {
                    JSONObject body = new JSONObject().put("key", config.key).put("kind", kind);
                    Location loc = lastLocation();
                    if (loc != null) body.put("lat", loc.getLatitude()).put("lng", loc.getLongitude()).put("accuracy", loc.getAccuracy());
                    BatteryManager bm = (BatteryManager) getSystemService(BATTERY_SERVICE);
                    if (bm != null) body.put("battery", bm.getIntProperty(BatteryManager.BATTERY_PROPERTY_CAPACITY));
                    HttpURLConnection c = (HttpURLConnection) new URL(config.endpoint).openConnection();
                    c.setConnectTimeout(10000); c.setReadTimeout(15000);
                    c.setRequestMethod("POST"); c.setDoOutput(true);
                    c.setRequestProperty("Content-Type", "application/json");
                    if (!config.apikey.isEmpty()) c.setRequestProperty("apikey", config.apikey);
                    try (OutputStream out = c.getOutputStream()) { out.write(body.toString().getBytes(StandardCharsets.UTF_8)); }
                    ok = c.getResponseCode() == 200;
                    c.disconnect();
                } catch (Exception ignored) { }
            }
            final boolean sent = ok;
            main.post(() -> {
                if (sent) { buzz(new long[] { 0, 120, 100, 120 }); status.setText("sos".equals(kind) ? "Your circle has been alerted" : "Location sent to your circle"); }
                else { askPhone("sos".equals(kind) ? "help" : "location"); buzz(new long[] { 0, 600 }); status.setText("Couldn't reach your circle from the watch. Your phone will try. Tap a button to call " + config.emergency + "."); }
            });
        }).start();
    }

    private Location lastLocation() {
        if (checkSelfPermission(Manifest.permission.ACCESS_FINE_LOCATION) != PackageManager.PERMISSION_GRANTED) return null;
        LocationManager lm = (LocationManager) getSystemService(LOCATION_SERVICE);
        Location best = null;
        for (String p : lm.getProviders(true)) {
            Location l = lm.getLastKnownLocation(p);
            if (l != null && (best == null || l.getTime() > best.getTime())) best = l;
        }
        return best;
    }

    private void askPhone(String action) {
        Wearable.getNodeClient(this).getConnectedNodes().addOnSuccessListener(nodes -> {
            for (Node n : nodes) Wearable.getMessageClient(this).sendMessage(n.getId(), "/action", action.getBytes(StandardCharsets.UTF_8));
        });
    }

    private void buzz(long[] pattern) {
        Vibrator v = getSystemService(Vibrator.class);
        if (v != null) v.vibrate(VibrationEffect.createWaveform(pattern, -1));
    }
}
