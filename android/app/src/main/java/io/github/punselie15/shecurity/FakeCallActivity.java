package io.github.punselie15.shecurity;

import android.Manifest;
import android.app.Activity;
import android.app.Notification;
import android.app.NotificationChannel;
import android.app.NotificationManager;
import android.app.PendingIntent;
import android.content.Context;
import android.content.Intent;
import android.content.pm.PackageManager;
import android.content.res.AssetFileDescriptor;
import android.graphics.Color;
import android.graphics.Typeface;
import android.graphics.drawable.GradientDrawable;
import android.media.AudioAttributes;
import android.media.AudioDeviceInfo;
import android.media.AudioManager;
import android.media.MediaPlayer;
import android.media.Ringtone;
import android.media.RingtoneManager;
import android.net.Uri;
import android.os.Build;
import android.os.Bundle;
import android.os.Handler;
import android.os.Looper;
import android.os.PowerManager;
import android.os.SystemClock;
import android.os.VibrationEffect;
import android.os.Vibrator;
import android.speech.RecognitionListener;
import android.speech.RecognizerIntent;
import android.speech.SpeechRecognizer;
import android.view.Gravity;
import android.view.View;
import android.view.WindowManager;
import android.widget.Chronometer;
import android.widget.LinearLayout;
import android.widget.TextView;

import org.json.JSONArray;
import org.json.JSONObject;

import java.io.InputStream;
import java.nio.charset.StandardCharsets;
import java.util.ArrayList;
import java.util.List;
import java.util.Random;
import java.util.regex.Pattern;

/**
 * The fake call on the phone (shecurity://fakecall?d=5&n=Mom&s=mom&m=0&l=1). It waits, rings like a
 * real call, and on answer plays the caller's recorded lines through the ear speaker. With the
 * microphone allowed it listens and answers in the same way as the web app (assets/voices/script.json).
 */
public class FakeCallActivity extends Activity {
    private static final String CHANNEL = "fakecall";
    private final Handler main = new Handler(Looper.getMainLooper());
    private final Random random = new Random();

    private String name = "Mom", voice = "af_heart";
    private boolean listenWanted = true, ringing, live;
    private JSONObject who;
    private final List<Object[]> intents = new ArrayList<>();
    private int step, idle, nudged;
    private String lastExpect;

    private Vibrator vibrator;
    private Ringtone ringtone;
    private MediaPlayer player;
    private SpeechRecognizer recognizer;
    private AudioManager audio;
    private PowerManager.WakeLock proximity, wake;
    private LinearLayout root;
    private TextView title, sub;

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        if (Build.VERSION.SDK_INT >= 27) { setShowWhenLocked(true); setTurnScreenOn(true); }
        else getWindow().addFlags(WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED | WindowManager.LayoutParams.FLAG_TURN_SCREEN_ON);
        vibrator = (Vibrator) getSystemService(Context.VIBRATOR_SERVICE);
        audio = (AudioManager) getSystemService(Context.AUDIO_SERVICE);

        Uri data = getIntent().getData();
        int delay = 5;
        String script = "mom";
        if (data != null) {
            try { delay = Math.max(1, Math.min(600, Integer.parseInt(data.getQueryParameter("d")))); } catch (Exception ignored) {}
            String n = data.getQueryParameter("n");
            if (n != null && !n.trim().isEmpty()) name = n.trim().length() > 30 ? n.trim().substring(0, 30) : n.trim();
            String s = data.getQueryParameter("s");
            if (s != null && s.matches("[a-z]{1,12}")) script = s;
            voice = "1".equals(data.getQueryParameter("m")) ? "am_michael" : "af_heart";
            listenWanted = !"0".equals(data.getQueryParameter("l"));
        }
        loadScript(script);
        if (listenWanted && who != null && Build.VERSION.SDK_INT >= 23 && checkSelfPermission(Manifest.permission.RECORD_AUDIO) != PackageManager.PERMISSION_GRANTED)
            requestPermissions(new String[] { Manifest.permission.RECORD_AUDIO }, 1);

        buildWaiting(delay);
        main.postDelayed(this::ring, delay * 1000L);
    }

    private void loadScript(String script) {
        try (InputStream in = getAssets().open("voices/script.json")) {
            byte[] buf = new byte[in.available()];
            int read = 0;
            while (read < buf.length) { int r = in.read(buf, read, buf.length - read); if (r < 0) break; read += r; }
            JSONObject all = new JSONObject(new String(buf, 0, read, StandardCharsets.UTF_8));
            who = all.getJSONObject("personas").optJSONObject(script);
            if (who == null) who = all.getJSONObject("personas").optJSONObject("mom");
            if (who != null && who.optJSONArray("spine") != null && who.optJSONArray("spine").length() == 0) who = null; // "you talk"
            JSONArray list = all.getJSONArray("intents");
            for (int i = 0; i < list.length(); i++) {
                JSONArray it = list.getJSONArray(i);
                intents.add(new Object[] { it.getString(0), Pattern.compile(it.getString(1)) });
            }
        } catch (Exception e) { who = null; }
    }

    // ---------- screens ----------

    private void buildWaiting(int delay) {
        root = column(Color.parseColor("#0E0B1F"));
        title = text("Call from " + name + " in " + delay + " s", 22, Color.WHITE, true);
        sub = text("You can lock your phone. It will ring like a real call.", 15, Color.parseColor("#B9B9C4"), false);
        TextView cancel = pill("Cancel", Color.parseColor("#3A3360"));
        cancel.setOnClickListener(v -> finish());
        root.addView(title); root.addView(sub); root.addView(cancel);
        setContentView(root);
    }

    private void ring() {
        if (isFinishing()) return;
        ringing = true;
        PowerManager pm = (PowerManager) getSystemService(Context.POWER_SERVICE);
        try {
            //noinspection deprecation
            wake = pm.newWakeLock(PowerManager.SCREEN_BRIGHT_WAKE_LOCK | PowerManager.ACQUIRE_CAUSES_WAKEUP, "shecurity:ring");
            wake.acquire(60_000);
        } catch (Exception ignored) {}
        if (vibrator != null) {
            long[] pattern = { 0, 800, 400, 800, 1600 };
            if (Build.VERSION.SDK_INT >= 26) vibrator.vibrate(VibrationEffect.createWaveform(pattern, 0)); else vibrator.vibrate(pattern, 0);
        }
        try {
            ringtone = RingtoneManager.getRingtone(this, RingtoneManager.getDefaultUri(RingtoneManager.TYPE_RINGTONE));
            if (Build.VERSION.SDK_INT >= 28) ringtone.setLooping(true);
            ringtone.play();
        } catch (Exception ignored) {}

        root.removeAllViews();
        root.setBackgroundColor(Color.parseColor("#1B1B1F"));
        root.addView(avatar());
        root.addView(text(name, 32, Color.WHITE, false));
        root.addView(text("Mobile", 16, Color.parseColor("#B9B9C4"), false));
        LinearLayout row = new LinearLayout(this);
        row.setGravity(Gravity.CENTER);
        TextView decline = round("✕", Color.parseColor("#E53935"));
        TextView accept = round("✓", Color.parseColor("#34C759"));
        row.addView(decline); row.addView(accept);
        root.addView(row);
        decline.setOnClickListener(v -> finish());
        accept.setOnClickListener(v -> answer());
        // if the screen isn't ours (she went to another app), show the call as a notification too
        if (!hasWindowFocus()) notifyRinging();
    }

    private void answer() {
        stopRinging();
        live = true;
        root.removeAllViews();
        root.addView(avatar());
        root.addView(text(name, 32, Color.WHITE, false));
        Chronometer clock = new Chronometer(this);
        clock.setTextColor(Color.parseColor("#B9B9C4")); clock.setTextSize(16); clock.setGravity(Gravity.CENTER);
        clock.setBase(SystemClock.elapsedRealtime()); clock.start();
        root.addView(clock);
        root.addView(text("Hold the phone to your ear", 13, Color.parseColor("#8D8DA0"), false));
        TextView end = round("✕", Color.parseColor("#E53935"));
        end.setOnClickListener(v -> finish());
        root.addView(end);

        toEarpiece();
        PowerManager pm = (PowerManager) getSystemService(Context.POWER_SERVICE);
        if (pm.isWakeLockLevelSupported(PowerManager.PROXIMITY_SCREEN_OFF_WAKE_LOCK)) {
            proximity = pm.newWakeLock(PowerManager.PROXIMITY_SCREEN_OFF_WAKE_LOCK, "shecurity:ear");
            proximity.acquire(60 * 60_000L);
        }
        main.postDelayed(this::nextLine, 1100);
    }

    // ---------- conversation, same rules as the web app ----------

    private void nextLine() {
        if (!live || who == null) return;
        JSONArray spine = who.optJSONArray("spine");
        if (spine != null && step < spine.length()) {
            JSONObject line = spine.optJSONObject(step++);
            lastExpect = line.optString("expect", null);
            say(line.optString("say"), this::listen);
            return;
        }
        JSONArray idleLines = who.optJSONArray("idle");
        if (idleLines == null || idle >= idleLines.length()) return; // script done, the call stays open quietly
        lastExpect = null;
        say(idleLines.optString(idle++), this::listen);
    }

    private void listen() {
        if (!live) return;
        boolean allowed = listenWanted && SpeechRecognizer.isRecognitionAvailable(this)
                && (Build.VERSION.SDK_INT < 23 || checkSelfPermission(Manifest.permission.RECORD_AUDIO) == PackageManager.PERMISSION_GRANTED);
        if (!allowed) { main.postDelayed(this::nextLine, 3200 + random.nextInt(1500)); return; }
        if (recognizer == null) recognizer = SpeechRecognizer.createSpeechRecognizer(this);
        final boolean[] finished = { false };
        Runnable quiet = () -> { if (!finished[0]) { finished[0] = true; recognizer.cancel(); heard(""); } };
        recognizer.setRecognitionListener(new RecognitionListener() {
            @Override public void onResults(Bundle results) {
                if (finished[0]) return; finished[0] = true; main.removeCallbacks(quiet);
                ArrayList<String> list = results.getStringArrayList(SpeechRecognizer.RESULTS_RECOGNITION);
                heard(list == null || list.isEmpty() ? "" : list.get(0));
            }
            @Override public void onError(int error) {
                if (finished[0]) return; finished[0] = true; main.removeCallbacks(quiet);
                if (error == SpeechRecognizer.ERROR_INSUFFICIENT_PERMISSIONS) listenWanted = false;
                heard("");
            }
            @Override public void onReadyForSpeech(Bundle params) {}
            @Override public void onBeginningOfSpeech() {}
            @Override public void onRmsChanged(float rmsdB) {}
            @Override public void onBufferReceived(byte[] buffer) {}
            @Override public void onEndOfSpeech() {}
            @Override public void onPartialResults(Bundle partialResults) {}
            @Override public void onEvent(int eventType, Bundle params) {}
        });
        Intent i = new Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH);
        i.putExtra(RecognizerIntent.EXTRA_LANGUAGE_MODEL, RecognizerIntent.LANGUAGE_MODEL_FREE_FORM);
        i.putExtra(RecognizerIntent.EXTRA_LANGUAGE, "en-US");
        i.putExtra(RecognizerIntent.EXTRA_MAX_RESULTS, 1);
        main.postDelayed(quiet, 7000);
        try { recognizer.startListening(i); } catch (Exception e) { finished[0] = true; main.removeCallbacks(quiet); main.postDelayed(this::nextLine, 2500); }
    }

    private void heard(String text) {
        if (!live) return;
        if (text.trim().isEmpty()) {
            // silence: check she's there once, then carry on with the script
            if (nudged < 1 && step <= 1) { nudged++; say(pick("nudge"), this::listen); }
            else main.postDelayed(this::nextLine, 600);
            return;
        }
        String intent = intentOf(text);
        if ("place".equals(lastExpect) && (intent.equals("ok") || intent.equals("hi") || intent.equals("who"))) intent = "place";
        if (intent.equals("bye")) {
            say(pick("bye"), null);
            step = Integer.MAX_VALUE / 2; idle = Integer.MAX_VALUE / 2;
            return;
        }
        String reply = pick(intent);
        if (reply.isEmpty()) reply = pick("ok");
        final boolean quick = intent.equals("ok");
        say(reply, () -> main.postDelayed(this::nextLine, quick ? 150 : 500));
    }

    private String intentOf(String text) {
        String t = text.toLowerCase();
        for (Object[] it : intents) if (((Pattern) it[1]).matcher(t).find()) return (String) it[0];
        return "ok";
    }

    private String pick(String key) {
        JSONArray list = who == null ? null : who.optJSONArray(key);
        return list == null || list.length() == 0 ? "" : list.optString(random.nextInt(list.length()));
    }

    // ---------- audio ----------

    private void toEarpiece() {
        audio.setMode(AudioManager.MODE_IN_COMMUNICATION);
        if (Build.VERSION.SDK_INT >= 31) {
            for (AudioDeviceInfo d : audio.getAvailableCommunicationDevices())
                if (d.getType() == AudioDeviceInfo.TYPE_BUILTIN_EARPIECE) { audio.setCommunicationDevice(d); break; }
        } else {
            //noinspection deprecation
            audio.setSpeakerphoneOn(false);
        }
    }

    private void say(String text, Runnable done) {
        if (!live || text == null || text.isEmpty()) { if (done != null) main.postDelayed(done, 400); return; }
        if (player != null) { player.release(); player = null; }
        try (AssetFileDescriptor fd = getAssets().openFd("voices/" + voice + "/" + clipName(text) + ".mp3")) {
            MediaPlayer p = new MediaPlayer();
            p.setAudioAttributes(new AudioAttributes.Builder()
                    .setUsage(AudioAttributes.USAGE_VOICE_COMMUNICATION)
                    .setContentType(AudioAttributes.CONTENT_TYPE_SPEECH).build());
            p.setDataSource(fd.getFileDescriptor(), fd.getStartOffset(), fd.getLength());
            p.setOnCompletionListener(mp -> { if (player == mp) { mp.release(); player = null; } if (done != null && live) main.postDelayed(done, 250); });
            p.prepare();
            player = p;
            p.start();
        } catch (Exception e) {
            if (done != null) main.postDelayed(done, 1500);
        }
    }

    /** Same name as the web app gives each clip: FNV-1a over the text, 8 hex digits. */
    static String clipName(String t) {
        int h = 0x811c9dc5;
        for (int i = 0; i < t.length(); i++) { h ^= t.charAt(i); h *= 0x01000193; }
        return String.format("%08x", h & 0xffffffffL);
    }

    private void stopRinging() {
        ringing = false;
        if (vibrator != null) vibrator.cancel();
        if (ringtone != null) { try { ringtone.stop(); } catch (Exception ignored) {} }
        NotificationManager nm = (NotificationManager) getSystemService(Context.NOTIFICATION_SERVICE);
        nm.cancel(7);
        if (wake != null && wake.isHeld()) wake.release();
    }

    private void notifyRinging() {
        NotificationManager nm = (NotificationManager) getSystemService(Context.NOTIFICATION_SERVICE);
        if (Build.VERSION.SDK_INT >= 26 && nm.getNotificationChannel(CHANNEL) == null) {
            NotificationChannel ch = new NotificationChannel(CHANNEL, "Fake call", NotificationManager.IMPORTANCE_HIGH);
            ch.setSound(null, null);
            nm.createNotificationChannel(ch);
        }
        Intent back = new Intent(this, FakeCallActivity.class).addFlags(Intent.FLAG_ACTIVITY_REORDER_TO_FRONT | Intent.FLAG_ACTIVITY_SINGLE_TOP);
        PendingIntent open = PendingIntent.getActivity(this, 7, back, PendingIntent.FLAG_UPDATE_CURRENT | (Build.VERSION.SDK_INT >= 23 ? PendingIntent.FLAG_IMMUTABLE : 0));
        Notification.Builder b = Build.VERSION.SDK_INT >= 26 ? new Notification.Builder(this, CHANNEL) : new Notification.Builder(this);
        b.setSmallIcon(R.drawable.ic_notification_icon)
                .setContentTitle(name)
                .setContentText("Incoming call")
                .setCategory(Notification.CATEGORY_CALL)
                .setContentIntent(open)
                .setAutoCancel(true);
        try { nm.notify(7, b.build()); } catch (Exception ignored) {}
    }

    @Override
    protected void onDestroy() {
        live = false;
        main.removeCallbacksAndMessages(null);
        stopRinging();
        if (player != null) { player.release(); player = null; }
        if (recognizer != null) { recognizer.destroy(); recognizer = null; }
        if (proximity != null && proximity.isHeld()) proximity.release();
        if (Build.VERSION.SDK_INT >= 31) audio.clearCommunicationDevice();
        audio.setMode(AudioManager.MODE_NORMAL);
        super.onDestroy();
    }

    // ---------- small view helpers ----------

    private LinearLayout column(int bg) {
        LinearLayout l = new LinearLayout(this);
        l.setOrientation(LinearLayout.VERTICAL);
        l.setGravity(Gravity.CENTER);
        l.setBackgroundColor(bg);
        int pad = dp(28);
        l.setPadding(pad, pad, pad, pad);
        return l;
    }

    private TextView text(String s, int size, int color, boolean bold) {
        TextView t = new TextView(this);
        t.setText(s); t.setTextSize(size); t.setTextColor(color); t.setGravity(Gravity.CENTER);
        if (bold) t.setTypeface(Typeface.DEFAULT_BOLD);
        t.setPadding(0, dp(6), 0, dp(6));
        return t;
    }

    private View avatar() {
        TextView a = new TextView(this);
        a.setText(name.substring(0, 1).toUpperCase());
        a.setTextSize(40); a.setTextColor(Color.WHITE); a.setGravity(Gravity.CENTER);
        GradientDrawable bg = new GradientDrawable(); bg.setShape(GradientDrawable.OVAL); bg.setColor(Color.parseColor("#6E6E78"));
        a.setBackground(bg);
        LinearLayout.LayoutParams lp = new LinearLayout.LayoutParams(dp(96), dp(96));
        lp.bottomMargin = dp(16);
        a.setLayoutParams(lp);
        return a;
    }

    private TextView round(String s, int color) {
        TextView b = new TextView(this);
        b.setText(s); b.setTextColor(Color.WHITE); b.setTextSize(26); b.setGravity(Gravity.CENTER);
        GradientDrawable bg = new GradientDrawable(); bg.setShape(GradientDrawable.OVAL); bg.setColor(color);
        b.setBackground(bg);
        LinearLayout.LayoutParams lp = new LinearLayout.LayoutParams(dp(72), dp(72));
        lp.setMargins(dp(28), dp(56), dp(28), 0);
        b.setLayoutParams(lp);
        return b;
    }

    private TextView pill(String s, int color) {
        TextView b = new TextView(this);
        b.setText(s); b.setTextColor(Color.WHITE); b.setTextSize(16); b.setGravity(Gravity.CENTER);
        GradientDrawable bg = new GradientDrawable(); bg.setCornerRadius(dp(24)); bg.setColor(color);
        b.setBackground(bg);
        b.setPadding(dp(28), dp(12), dp(28), dp(12));
        LinearLayout.LayoutParams lp = new LinearLayout.LayoutParams(LinearLayout.LayoutParams.WRAP_CONTENT, LinearLayout.LayoutParams.WRAP_CONTENT);
        lp.topMargin = dp(32);
        b.setLayoutParams(lp);
        return b;
    }

    private int dp(int v) { return Math.round(v * getResources().getDisplayMetrics().density); }
}
