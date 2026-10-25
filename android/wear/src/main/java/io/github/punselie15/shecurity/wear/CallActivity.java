package io.github.punselie15.shecurity.wear;

import android.app.Activity;
import android.graphics.Color;
import android.graphics.Typeface;
import android.graphics.drawable.GradientDrawable;
import android.os.Bundle;
import android.os.Handler;
import android.os.Looper;
import android.os.SystemClock;
import android.os.VibrationEffect;
import android.os.Vibrator;
import android.speech.tts.TextToSpeech;
import android.view.Gravity;
import android.widget.Button;
import android.widget.Chronometer;
import android.widget.LinearLayout;
import android.widget.TextView;

import java.util.Locale;

/** A pretend incoming call on the wrist, so you have a reason to leave. */
public class CallActivity extends Activity {
    private static final String[] LINES = {
        "Hi, it's me. Where are you right now?",
        "Okay. I need you to come home now, something's come up.",
        "I'll explain when you get here. Can you leave right away?",
        "Good. Stay on the phone with me while you walk."
    };
    private final Handler main = new Handler(Looper.getMainLooper());
    private TextToSpeech tts;
    private Vibrator vibrator;
    private boolean live = true;

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        vibrator = getSystemService(Vibrator.class);
        if (vibrator != null) vibrator.vibrate(VibrationEffect.createWaveform(new long[] { 0, 800, 600 }, 0));
        tts = new TextToSpeech(this, status -> { if (status == TextToSpeech.SUCCESS) tts.setLanguage(Locale.US); });

        LinearLayout root = new LinearLayout(this);
        root.setOrientation(LinearLayout.VERTICAL);
        root.setGravity(Gravity.CENTER);
        root.setBackgroundColor(Color.BLACK);
        TextView name = new TextView(this);
        String caller = getIntent().getStringExtra("caller");
        name.setText(caller == null || caller.isEmpty() ? "Mom" : caller);
        name.setTextColor(Color.WHITE); name.setTextSize(20); name.setTypeface(Typeface.DEFAULT_BOLD); name.setGravity(Gravity.CENTER);
        TextView sub = new TextView(this);
        sub.setText("Mobile"); sub.setTextColor(Color.LTGRAY); sub.setGravity(Gravity.CENTER);
        Chronometer clock = new Chronometer(this);
        clock.setTextColor(Color.LTGRAY); clock.setGravity(Gravity.CENTER);
        LinearLayout row = new LinearLayout(this);
        row.setGravity(Gravity.CENTER);
        Button decline = round("✕", Color.parseColor("#E53935"));
        Button accept = round("✓", Color.parseColor("#43A047"));
        row.addView(decline); row.addView(accept);
        root.addView(name); root.addView(sub); root.addView(row);
        setContentView(root);

        decline.setOnClickListener(v -> finish());
        accept.setOnClickListener(v -> {
            if (vibrator != null) vibrator.cancel();
            row.removeView(accept);
            root.removeView(sub);
            root.addView(clock, 1);
            clock.setBase(SystemClock.elapsedRealtime()); clock.start();
            for (int i = 0; i < LINES.length; i++) {
                final String line = LINES[i];
                main.postDelayed(() -> { if (live && tts != null) tts.speak(line, TextToSpeech.QUEUE_ADD, null, line); }, 1000 + i * 6000L);
            }
        });
    }

    private Button round(String text, int color) {
        Button b = new Button(this);
        b.setText(text); b.setTextColor(Color.WHITE); b.setTextSize(20);
        GradientDrawable bg = new GradientDrawable(); bg.setShape(GradientDrawable.OVAL); bg.setColor(color);
        b.setBackground(bg);
        int s = Math.round(56 * getResources().getDisplayMetrics().density);
        LinearLayout.LayoutParams lp = new LinearLayout.LayoutParams(s, s);
        lp.setMargins(12, 16, 12, 0);
        b.setLayoutParams(lp);
        return b;
    }

    @Override
    protected void onDestroy() {
        live = false;
        if (vibrator != null) vibrator.cancel();
        if (tts != null) { tts.stop(); tts.shutdown(); }
        super.onDestroy();
    }
}
