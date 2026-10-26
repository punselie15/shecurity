package io.github.punselie15.shecurity;

import android.Manifest;
import android.annotation.SuppressLint;
import android.app.Activity;
import android.content.ActivityNotFoundException;
import android.content.Intent;
import android.content.pm.PackageManager;
import android.graphics.Color;
import android.net.Uri;
import android.os.Build;
import android.os.Bundle;
import android.view.View;
import android.view.WindowInsets;
import android.webkit.GeolocationPermissions;
import android.webkit.JavascriptInterface;
import android.webkit.PermissionRequest;
import android.webkit.ValueCallback;
import android.webkit.WebChromeClient;
import android.webkit.WebResourceRequest;
import android.webkit.WebResourceResponse;
import android.webkit.WebSettings;
import android.webkit.WebView;
import android.webkit.WebViewClient;
import android.widget.FrameLayout;

import androidx.webkit.WebViewAssetLoader;

import java.io.IOException;
import java.io.InputStream;
import java.util.ArrayList;
import java.util.List;

/**
 * Shecurity's own app screen. The whole web app ships inside the APK (assets/www) and is served
 * at https://shecurity.app/app/ by WebViewAssetLoader, so it opens instantly and works offline.
 * Only the circle (Supabase), maps and donations go to the internet.
 */
public class LauncherActivity extends Activity {
    static final String HOME = "https://shecurity.app/app/";
    static final int APP_VERSION = 5; // tells the web app which native features it has
    private static final int REQ_LOCATION = 1, REQ_MIC = 2, REQ_NOTIFY = 3;

    private WebView web;
    private WebViewAssetLoader assets;
    private GeolocationPermissions.Callback geoCallback;
    private String geoOrigin;
    private PermissionRequest micRequest;

    @SuppressLint("SetJavaScriptEnabled")
    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        getWindow().setStatusBarColor(Color.parseColor("#FBF8FA"));
        getWindow().setNavigationBarColor(Color.parseColor("#FBF8FA"));
        getWindow().getDecorView().setSystemUiVisibility(View.SYSTEM_UI_FLAG_LIGHT_STATUS_BAR
                | (Build.VERSION.SDK_INT >= 26 ? View.SYSTEM_UI_FLAG_LIGHT_NAVIGATION_BAR : 0));

        assets = new WebViewAssetLoader.Builder()
                .setDomain("shecurity.app")
                .addPathHandler("/app/", path -> local(path))
                .build();

        FrameLayout root = new FrameLayout(this);
        root.setBackgroundColor(Color.parseColor("#FBF8FA"));
        web = new WebView(this);
        web.setBackgroundColor(Color.parseColor("#FBF8FA"));
        root.addView(web, new FrameLayout.LayoutParams(FrameLayout.LayoutParams.MATCH_PARENT, FrameLayout.LayoutParams.MATCH_PARENT));
        // Android 15+ draws apps edge to edge, so keep the page clear of the status and navigation bars
        root.setOnApplyWindowInsetsListener((v, insets) -> {
            if (Build.VERSION.SDK_INT >= 30) {
                android.graphics.Insets bars = insets.getInsets(WindowInsets.Type.systemBars() | WindowInsets.Type.ime());
                v.setPadding(bars.left, bars.top, bars.right, bars.bottom);
            } else {
                v.setPadding(insets.getSystemWindowInsetLeft(), insets.getSystemWindowInsetTop(),
                        insets.getSystemWindowInsetRight(), insets.getSystemWindowInsetBottom());
            }
            return insets;
        });
        setContentView(root);

        WebSettings s = web.getSettings();
        s.setJavaScriptEnabled(true);
        s.setDomStorageEnabled(true);
        s.setDatabaseEnabled(true);
        s.setGeolocationEnabled(true);
        s.setMediaPlaybackRequiresUserGesture(false);
        s.setAllowFileAccess(false);
        s.setAllowContentAccess(false);
        s.setSupportMultipleWindows(false);
        s.setUserAgentString(s.getUserAgentString() + " ShecurityApp/" + APP_VERSION);
        web.addJavascriptInterface(new Bridge(), "ShecurityNative");
        web.setWebViewClient(new Client());
        web.setWebChromeClient(new Chrome());
        web.setDownloadListener((url, ua, disposition, mime, length) -> openOutside(Uri.parse(url)));

        if (savedInstanceState != null) web.restoreState(savedInstanceState);
        else web.loadUrl(startUrl(getIntent()));
    }

    /** Serves a file of the bundled web app; the voices live once in assets/voices for the native fake call too. */
    private WebResourceResponse local(String path) {
        if (path.isEmpty()) path = "index.html";
        String file = path.startsWith("voices/") ? path : "www/" + path;
        try {
            InputStream in = getAssets().open(file);
            WebResourceResponse r = new WebResourceResponse(mime(path), null, in);
            java.util.Map<String, String> h = new java.util.HashMap<>();
            h.put("Cache-Control", "no-cache");
            r.setResponseHeaders(h);
            return r;
        } catch (IOException e) {
            return null;
        }
    }

    private static String mime(String p) {
        if (p.endsWith(".html")) return "text/html";
        if (p.endsWith(".js")) return "text/javascript";
        if (p.endsWith(".css")) return "text/css";
        if (p.endsWith(".json") || p.endsWith(".webmanifest")) return "application/json";
        if (p.endsWith(".png")) return "image/png";
        if (p.endsWith(".svg")) return "image/svg+xml";
        if (p.endsWith(".mp3")) return "audio/mpeg";
        if (p.endsWith(".woff2")) return "font/woff2";
        return "application/octet-stream";
    }

    /** The page to open: a widget, shortcut or watch link names a route after #. */
    private String startUrl(Intent intent) {
        String hash = "";
        Uri data = intent != null ? intent.getData() : null;
        if (data != null) {
            String f = data.getFragment();
            if (f != null && f.matches("[A-Za-z0-9_-]{1,40}")) hash = "#" + f;
        }
        return HOME + "?android=" + APP_VERSION + hash;
    }

    @Override
    protected void onNewIntent(Intent intent) {
        super.onNewIntent(intent);
        Uri data = intent.getData();
        String f = data != null ? data.getFragment() : null;
        if (f != null && f.matches("[A-Za-z0-9_-]{1,40}")) {
            web.evaluateJavascript("location.hash = '" + f + "';", null);
        }
    }

    @Override
    protected void onSaveInstanceState(Bundle out) {
        super.onSaveInstanceState(out);
        web.saveState(out);
    }

    @Override
    public void onBackPressed() {
        if (web.canGoBack()) web.goBack();
        else super.onBackPressed();
    }

    @Override
    protected void onResume() { super.onResume(); web.onResume(); }

    @Override
    protected void onPause() { web.onPause(); super.onPause(); }

    private boolean isApp(Uri u) {
        return "https".equals(u.getScheme()) && "shecurity.app".equals(u.getHost())
                && u.getPath() != null && u.getPath().startsWith("/app");
    }

    /** sms:, tel:, mailto:, maps, the donate page and other sites open in the right app. */
    private void openOutside(Uri u) {
        try {
            Intent i = new Intent(Intent.ACTION_VIEW, u);
            i.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
            startActivity(i);
        } catch (ActivityNotFoundException ignored) { }
    }

    private class Client extends WebViewClient {
        @Override
        public WebResourceResponse shouldInterceptRequest(WebView view, WebResourceRequest req) {
            return assets.shouldInterceptRequest(req.getUrl());
        }

        @Override
        public boolean shouldOverrideUrlLoading(WebView view, WebResourceRequest req) {
            Uri u = req.getUrl();
            if (isApp(u)) return false;
            if ("intent".equals(u.getScheme())) {
                // our own shecurity:// screens (widget sync, fake call); never other apps' intents
                try {
                    Intent i = Intent.parseUri(u.toString(), Intent.URI_INTENT_SCHEME);
                    i.setPackage(getPackageName());
                    i.setComponent(null);
                    i.setSelector(null);
                    i.addCategory(Intent.CATEGORY_BROWSABLE);
                    startActivity(i);
                } catch (Exception ignored) { }
                return true;
            }
            openOutside(u);
            return true;
        }

        // the phone may stop the page's process to free memory; start fresh instead of closing Shecurity
        @Override
        public boolean onRenderProcessGone(WebView view, android.webkit.RenderProcessGoneDetail detail) {
            if (view.getParent() instanceof android.view.ViewGroup) ((android.view.ViewGroup) view.getParent()).removeView(view);
            view.destroy();
            Intent again = new Intent(LauncherActivity.this, LauncherActivity.class);
            again.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK | Intent.FLAG_ACTIVITY_CLEAR_TASK);
            finish();
            startActivity(again);
            return true;
        }
    }

    private class Chrome extends WebChromeClient {
        @Override
        public void onGeolocationPermissionsShowPrompt(String origin, GeolocationPermissions.Callback callback) {
            if (hasLocation()) { callback.invoke(origin, true, false); return; }
            geoOrigin = origin;
            geoCallback = callback;
            requestPermissions(new String[] { Manifest.permission.ACCESS_FINE_LOCATION, Manifest.permission.ACCESS_COARSE_LOCATION }, REQ_LOCATION);
        }

        @Override
        public void onPermissionRequest(PermissionRequest request) {
            List<String> ok = new ArrayList<>();
            for (String r : request.getResources()) if (PermissionRequest.RESOURCE_AUDIO_CAPTURE.equals(r)) ok.add(r);
            if (ok.isEmpty()) { request.deny(); return; }
            if (checkSelfPermission(Manifest.permission.RECORD_AUDIO) == PackageManager.PERMISSION_GRANTED) {
                request.grant(ok.toArray(new String[0]));
                return;
            }
            micRequest = request;
            requestPermissions(new String[] { Manifest.permission.RECORD_AUDIO }, REQ_MIC);
        }

        @Override
        public boolean onShowFileChooser(WebView v, ValueCallback<Uri[]> cb, FileChooserParams p) {
            cb.onReceiveValue(null);
            return true;
        }
    }

    private boolean hasLocation() {
        return checkSelfPermission(Manifest.permission.ACCESS_FINE_LOCATION) == PackageManager.PERMISSION_GRANTED
                || checkSelfPermission(Manifest.permission.ACCESS_COARSE_LOCATION) == PackageManager.PERMISSION_GRANTED;
    }

    @Override
    public void onRequestPermissionsResult(int code, String[] perms, int[] results) {
        boolean granted = false;
        for (int r : results) if (r == PackageManager.PERMISSION_GRANTED) granted = true;
        if (code == REQ_LOCATION && geoCallback != null) {
            geoCallback.invoke(geoOrigin, granted, false);
            geoCallback = null;
        } else if (code == REQ_MIC && micRequest != null) {
            if (granted) micRequest.grant(new String[] { PermissionRequest.RESOURCE_AUDIO_CAPTURE });
            else micRequest.deny();
            micRequest = null;
        } else if (code == REQ_NOTIFY) {
            final boolean on = granted;
            web.post(() -> web.evaluateJavascript("window.onShecurityNotify && onShecurityNotify(" + on + ")", null));
            if (on) PushService.register(this);
        }
    }

    /** What the web app can ask the phone for. */
    private class Bridge {
        @JavascriptInterface public int version() { return APP_VERSION; }

        /** Where the phone is (mobile network, then SIM, then the phone's region), for the right emergency number. */
        @JavascriptInterface public String country() {
            try {
                android.telephony.TelephonyManager tm = (android.telephony.TelephonyManager) getSystemService(TELEPHONY_SERVICE);
                if (tm != null) {
                    String c = tm.getNetworkCountryIso();
                    if (c == null || c.length() != 2) c = tm.getSimCountryIso();
                    if (c != null && c.length() == 2) return c.toUpperCase(java.util.Locale.ROOT);
                }
            } catch (Exception ignored) { }
            return java.util.Locale.getDefault().getCountry();
        }

        /** Quietly updates the home-screen widget and watch with the buttons, number and caller name the app uses. */
        @JavascriptInterface public boolean setWidget(String buttons, String emergency, String caller, String key) {
            return WidgetSyncActivity.save(LauncherActivity.this, buttons, key, emergency, caller);
        }

        /** Asks the launcher to place the widget. False when the launcher can't, so the app shows the steps. */
        @JavascriptInterface public boolean pinWidget() { return WidgetSyncActivity.pin(LauncherActivity.this); }

        @JavascriptInterface public boolean online() {
            android.net.ConnectivityManager cm = (android.net.ConnectivityManager) getSystemService(CONNECTIVITY_SERVICE);
            android.net.NetworkInfo n = cm != null ? cm.getActiveNetworkInfo() : null;
            return n != null && n.isConnected();
        }

        /** The Firebase token for circle alerts, or "" until the phone has one. */
        @JavascriptInterface public String pushToken() { return PushService.token(LauncherActivity.this); }

        @JavascriptInterface public boolean pushAvailable() { return PushService.available(LauncherActivity.this); }

        @JavascriptInterface public String notifyPermission() {
            if (Build.VERSION.SDK_INT < 33) return "granted";
            return checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) == PackageManager.PERMISSION_GRANTED ? "granted" : "default";
        }

        @JavascriptInterface public void askNotify() {
            runOnUiThread(() -> {
                if (Build.VERSION.SDK_INT >= 33 && checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED) {
                    requestPermissions(new String[] { Manifest.permission.POST_NOTIFICATIONS }, REQ_NOTIFY);
                } else {
                    PushService.register(LauncherActivity.this);
                    web.evaluateJavascript("window.onShecurityNotify && onShecurityNotify(true)", null);
                }
            });
        }
    }
}
