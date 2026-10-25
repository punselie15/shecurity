package io.github.punselie15.shecurity;

import android.app.PendingIntent;
import android.appwidget.AppWidgetManager;
import android.appwidget.AppWidgetProvider;
import android.content.ComponentName;
import android.content.Context;
import android.content.Intent;
import android.content.SharedPreferences;
import android.net.Uri;
import android.os.Build;
import android.widget.RemoteViews;

/** Home-screen widget with four big buttons. The buttons are chosen in the app under You. */
public class QuickWidget extends AppWidgetProvider {
    static final String PREFS = "quick_widget";
    static final String KEY = "buttons";
    static final String STANDARD = "location:My location|fakecall-now:Call me in 5s|help:Send help|call:Call 112";
    private static final int[] CELLS = { R.id.q0, R.id.q1, R.id.q2, R.id.q3 };

    @Override
    public void onUpdate(Context context, AppWidgetManager manager, int[] ids) {
        for (int id : ids) manager.updateAppWidget(id, build(context));
    }

    static void refresh(Context context) {
        AppWidgetManager manager = AppWidgetManager.getInstance(context);
        int[] ids = manager.getAppWidgetIds(new ComponentName(context, QuickWidget.class));
        for (int id : ids) manager.updateAppWidget(id, build(context));
    }

    static String[] buttons(Context context) {
        SharedPreferences prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE);
        String[] list = prefs.getString(KEY, STANDARD).split("\\|");
        return list.length == 4 ? list : STANDARD.split("\\|");
    }

    private static RemoteViews build(Context context) {
        RemoteViews views = new RemoteViews(context.getPackageName(), R.layout.widget_quick);
        String[] list = buttons(context);
        int flags = PendingIntent.FLAG_UPDATE_CURRENT | (Build.VERSION.SDK_INT >= 23 ? PendingIntent.FLAG_IMMUTABLE : 0);
        for (int i = 0; i < 4; i++) {
            String[] parts = list[i].split(":", 2);
            String action = parts[0];
            String label = parts.length > 1 ? parts[1] : action;
            views.setTextViewText(CELLS[i], label);
            views.setTextViewCompoundDrawables(CELLS[i], 0, icon(action, i == 0 || i == 3), 0, 0);
            views.setContentDescription(CELLS[i], label);
            Intent open = new Intent(Intent.ACTION_VIEW,
                    Uri.parse("https://punselie15.github.io/shecurity/app/?android=2#q-" + action),
                    context, LauncherActivity.class);
            open.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
            views.setOnClickPendingIntent(CELLS[i], PendingIntent.getActivity(context, i, open, flags));
        }
        return views;
    }

    private static int icon(String action, boolean onPink) {
        switch (action) {
            case "help": return onPink ? R.drawable.wq_bell_w : R.drawable.wq_bell;
            case "location": return onPink ? R.drawable.wq_pin_w : R.drawable.wq_pin;
            case "fakecall-now": case "fakecall": case "call": return onPink ? R.drawable.wq_phone_w : R.drawable.wq_phone;
            case "siren": return onPink ? R.drawable.wq_siren_w : R.drawable.wq_siren;
            case "walk": return onPink ? R.drawable.wq_walk_w : R.drawable.wq_walk;
            case "timer": return onPink ? R.drawable.wq_timer_w : R.drawable.wq_timer;
            case "date": return onPink ? R.drawable.wq_heart_w : R.drawable.wq_heart;
            case "record": return onPink ? R.drawable.wq_mic_w : R.drawable.wq_mic;
            case "ride": return onPink ? R.drawable.wq_car_w : R.drawable.wq_car;
            default: return onPink ? R.drawable.wq_star_w : R.drawable.wq_star;
        }
    }
}
