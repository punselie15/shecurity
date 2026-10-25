package io.github.punselie15.shecurity.wear;

import android.content.Context;
import android.content.SharedPreferences;

/** What the phone app sent over: the four buttons, the watch key and the emergency number. */
final class Config {
    static final String PREFS = "watch";
    static final String STANDARD = "location:My location|fakecall-now:Call me in 5s|help:Send help|call:Call 112";

    final String[] buttons;
    final String key, endpoint, apikey, emergency, caller;

    private Config(SharedPreferences p) {
        String[] b = p.getString("buttons", STANDARD).split("\\|");
        buttons = b.length == 4 ? b : STANDARD.split("\\|");
        key = p.getString("key", "");
        endpoint = p.getString("endpoint", "");
        apikey = p.getString("apikey", "");
        emergency = p.getString("emergency", "112");
        caller = p.getString("caller", "Mom");
    }

    static Config load(Context c) { return new Config(c.getSharedPreferences(PREFS, Context.MODE_PRIVATE)); }

    boolean linked() { return !key.isEmpty() && endpoint.startsWith("https://"); }
}
