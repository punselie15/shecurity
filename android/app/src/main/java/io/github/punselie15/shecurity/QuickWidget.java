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
import android.os.Bundle;
import android.util.SizeF;
import android.widget.RemoteViews;

import java.util.HashMap;
import java.util.Map;

/** Home-screen widget with four big buttons. The buttons are chosen in the app under You. */
public class QuickWidget extends AppWidgetProvider {
    static final String PREFS = "quick_widget";
    static final String KEY = "buttons";
    static final String STANDARD = "help:Send help|location:My location|fakecall-now:Call me in 5s|call:Call 112";
    private static final int[] CELLS = { R.id.c0, R.id.c1, R.id.c2, R.id.c3 };
    private static final int[] ICONS = { R.id.i0, R.id.i1, R.id.i2, R.id.i3 };
    private static final int[] LABELS = { R.id.l0, R.id.l1, R.id.l2, R.id.l3 };
    private static final int[] LINES = { R.id.s0, R.id.s1, R.id.s2, R.id.s3 };
    private static final int INK = 0xFF2A2152;

    @Override
    public void onUpdate(Context context, AppWidgetManager manager, int[] ids) {
        for (int id : ids) manager.updateAppWidget(id, views(context, manager, id));
    }

    @Override
    public void onAppWidgetOptionsChanged(Context context, AppWidgetManager manager, int id, Bundle options) {
        manager.updateAppWidget(id, views(context, manager, id));
    }

    static void refresh(Context context) {
        AppWidgetManager manager = AppWidgetManager.getInstance(context);
        int[] ids = manager.getAppWidgetIds(new ComponentName(context, QuickWidget.class));
        for (int id : ids) manager.updateAppWidget(id, views(context, manager, id));
    }

    static String[] buttons(Context context) {
        SharedPreferences prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE);
        String[] list = prefs.getString(KEY, STANDARD).split("\\|");
        return list.length == 4 ? list : STANDARD.split("\\|");
    }

    // Android 12+ picks the layout that fits as the widget is resized; older versions get it from the current size.
    private static RemoteViews views(Context context, AppWidgetManager manager, int id) {
        if (Build.VERSION.SDK_INT >= 31) {
            Map<SizeF, RemoteViews> sizes = new HashMap<>();
            sizes.put(new SizeF(100f, 100f), build(context, R.layout.widget_quick_compact));
            sizes.put(new SizeF(220f, 100f), build(context, R.layout.widget_quick));
            sizes.put(new SizeF(220f, 280f), build(context, R.layout.widget_quick_large));
            return new RemoteViews(sizes);
        }
        Bundle o = manager.getAppWidgetOptions(id);
        int w = o.getInt(AppWidgetManager.OPTION_APPWIDGET_MIN_WIDTH, 250);
        int h = o.getInt(AppWidgetManager.OPTION_APPWIDGET_MAX_HEIGHT, 110);
        int layout = w < 220 ? R.layout.widget_quick_compact : h >= 280 ? R.layout.widget_quick_large : R.layout.widget_quick;
        return build(context, layout);
    }

    private static RemoteViews build(Context context, int layout) {
        RemoteViews views = new RemoteViews(context.getPackageName(), layout);
        String[] list = buttons(context);
        int flags = PendingIntent.FLAG_UPDATE_CURRENT | (Build.VERSION.SDK_INT >= 23 ? PendingIntent.FLAG_IMMUTABLE : 0);
        for (int i = 0; i < 4; i++) {
            // "id:label" or "id:label:line", the app sends them in the phone's language
            String[] parts = list[i].split(":", 3);
            String action = parts[0];
            String label = parts.length > 1 ? parts[1] : action;
            String line = parts.length > 2 ? parts[2] : detail(action);
            boolean hot = urgent(action);
            views.setInt(CELLS[i], "setBackgroundResource", hot ? R.drawable.wq_pink : R.drawable.wq_white);
            views.setInt(ICONS[i], "setBackgroundResource", hot ? R.drawable.wq_chip_glass : R.drawable.wq_chip_soft);
            views.setImageViewResource(ICONS[i], icon(action, hot));
            views.setTextViewText(LABELS[i], label);
            views.setTextColor(LABELS[i], hot ? 0xFFFFFFFF : INK);
            views.setTextViewText(LINES[i], line);
            views.setTextColor(LINES[i], hot ? 0xB3FFFFFF : 0xB32A2152);
            views.setContentDescription(CELLS[i], label + ". " + line);
            Intent open = new Intent(Intent.ACTION_VIEW,
                    Uri.parse("https://shecurity.app/app/?android=3#q-" + action),
                    context, LauncherActivity.class);
            open.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
            views.setOnClickPendingIntent(CELLS[i], PendingIntent.getActivity(context, i, open, flags));
        }
        return views;
    }

    // the actions for a real emergency are pink, the rest white
    private static boolean urgent(String action) {
        return action.equals("help") || action.equals("call") || action.equals("siren");
    }

    // one short line under each button, so it's clear what a tap does
    private static String detail(String action) {
        switch (action) {
            case "help": return "Alerts your circle";
            case "location": return "Texts where you are";
            case "fakecall-now": return "Your phone rings";
            case "call": return "Emergency services";
            case "siren": return "Loud alarm";
            case "walk": return "Circle follows you";
            case "timer": return "Alert if no check-in";
            case "fakecall": return "Pick when it rings";
            case "plan": return "Tell your circle";
            case "ride": return "Share your ride";
            case "date": return "Date check-ins";
            case "record": return "Saves audio";
            case "lines": return "Free support";
            default: return "";
        }
    }

    private static int icon(String action, boolean onPink) {
        switch (action) {
            case "help": return onPink ? R.drawable.wq_bell_w : R.drawable.wq_bell;
            case "location": case "plan": return onPink ? R.drawable.wq_pin_w : R.drawable.wq_pin;
            case "fakecall-now": case "fakecall": return onPink ? R.drawable.wq_phone_w : R.drawable.wq_phone;
            case "call": return onPink ? R.drawable.wq_sos_w : R.drawable.wq_sos;
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
