// Sends push notifications to a user's safety circle when they raise an alert,
// and to the alert's sender when someone in the circle responds.
import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import webpush from "npm:web-push@3.6.7";
import { createClient } from "npm:@supabase/supabase-js@2.45.4";

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};
const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), { status, headers: { ...cors, "Content-Type": "application/json" } });

const ALERT_TEXT: Record<string, (n: string, msg: string) => [string, string, boolean]> = {
  sos: (n, m) => [`${n} needs help`, m || "Open Shecurity to see where she is.", true],
  missed_checkin: (n, m) => [`${n} missed her check-in`, m || "She hasn't said she's safe. Open Shecurity to see where she is.", true],
  walk: (n, m) => [`${n} is walking home`, m || "Tap to follow her live location.", false],
  location: (n) => [`${n} shared her location`, "Tap to see where she is.", false],
  safe: (n, m) => [`${n} is safe`, m || "She marked herself safe.", false],
};
const RESPONSE_TEXT: Record<string, string> = {
  seen: "has seen your alert",
  on_my_way: "is on the way",
  calling: "is calling you",
  called_police: "has called emergency services",
};


// Store apps get alerts through Firebase Cloud Messaging (endpoint "fcm:<token>").
// The service account JSON is the FCM_SERVICE_ACCOUNT function secret.
let fcmAuth: { token: string; until: number } | null = null;
async function fcmAccessToken(sa: { client_email: string; private_key: string }) {
  if (fcmAuth && fcmAuth.until > Date.now() + 60_000) return fcmAuth.token;
  const b64 = (o: unknown) => btoa(typeof o === "string" ? o : JSON.stringify(o)).replace(/=+$/, "").replace(/\+/g, "-").replace(/\//g, "_");
  const now = Math.floor(Date.now() / 1000);
  const unsigned = b64({ alg: "RS256", typ: "JWT" }) + "." + b64({
    iss: sa.client_email, scope: "https://www.googleapis.com/auth/firebase.messaging",
    aud: "https://oauth2.googleapis.com/token", iat: now, exp: now + 3600,
  });
  const der = Uint8Array.from(atob(sa.private_key.replace(/-----[^-]+-----/g, "").replace(/\s+/g, "")), (c) => c.charCodeAt(0));
  const key = await crypto.subtle.importKey("pkcs8", der, { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" }, false, ["sign"]);
  const sig = new Uint8Array(await crypto.subtle.sign("RSASSA-PKCS1-v1_5", key, new TextEncoder().encode(unsigned)));
  const jwt = unsigned + "." + b64(String.fromCharCode(...sig));
  const r = await fetch("https://oauth2.googleapis.com/token", {
    method: "POST", headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: "grant_type=urn%3Aietf%3Aparams%3Aoauth%3Agrant-type%3Ajwt-bearer&assertion=" + jwt,
  });
  const j = await r.json();
  if (!j.access_token) throw new Error("fcm auth failed");
  fcmAuth = { token: j.access_token, until: Date.now() + (j.expires_in || 3600) * 1000 };
  return fcmAuth.token;
}
async function sendFcm(token: string, msg: { title: string; body: string; tag: string; urgent: boolean }) {
  const raw = Deno.env.get("FCM_SERVICE_ACCOUNT");
  if (!raw) return 0; // Firebase not set up yet
  const sa = JSON.parse(raw);
  const r = await fetch(`https://fcm.googleapis.com/v1/projects/${sa.project_id}/messages:send`, {
    method: "POST",
    headers: { Authorization: "Bearer " + await fcmAccessToken(sa), "Content-Type": "application/json" },
    body: JSON.stringify({ message: {
      token,
      data: { title: msg.title, body: msg.body, tag: String(msg.tag), route: "circle" },
      android: { priority: "high", ttl: "3600s" },
      apns: { headers: { "apns-priority": "10" }, payload: { aps: { alert: { title: msg.title, body: msg.body }, sound: "default", "interruption-level": msg.urgent ? "time-sensitive" : "active" } } },
    } }),
  });
  return r.status;
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  try {
    const admin = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!, {
      auth: { persistSession: false },
    });
    const token = (req.headers.get("Authorization") || "").replace(/^Bearer\s+/i, "");
    const { data: who, error: authErr } = await admin.auth.getUser(token);
    if (authErr || !who?.user) return json({ error: "not signed in" }, 401);
    const me = who.user.id;

    const { type, alert_id } = await req.json();
    const { data: alert } = await admin.from("alerts").select("*").eq("id", alert_id).maybeSingle();
    if (!alert) return json({ error: "alert not found" }, 404);

    // sent to one small circle, or to everyone in all the sender's circles
    const { data: senderCircles } = await admin.from("circle_members").select("circle_id").eq("user_id", alert.sender_id);
    const circleIds = (senderCircles || []).map((r) => r.circle_id).filter((id) => !alert.circle_id || id === alert.circle_id);
    const { data: mates } = circleIds.length
      ? await admin.from("circle_members").select("user_id").in("circle_id", circleIds)
      : { data: [] as { user_id: string }[] };
    const mateIds = [...new Set((mates || []).map((m) => m.user_id))];

    let recipients: string[] = [];
    let title = "", body = "", urgent = false;

    if (type === "alert") {
      if (alert.sender_id !== me) return json({ error: "not your alert" }, 403);
      if (alert.notified_at) return json({ sent: 0, note: "already sent" });
      const make = ALERT_TEXT[alert.kind];
      if (!make) return json({ sent: 0, note: "no notification for this kind" });
      const { data: p } = await admin.from("profiles").select("display_name").eq("id", me).maybeSingle();
      [title, body, urgent] = make(p?.display_name || "Someone in your circle", alert.message || "");
      recipients = mateIds.filter((id) => id !== me);
      await admin.from("alerts").update({ notified_at: new Date().toISOString() }).eq("id", alert.id);
    } else if (type === "response") {
      if (!mateIds.includes(me) || alert.sender_id === me) return json({ error: "not in this circle" }, 403);
      const { data: r } = await admin.from("alert_responses").select("response").eq("alert_id", alert.id).eq("user_id", me).maybeSingle();
      if (!r) return json({ error: "no response" }, 400);
      const { data: p } = await admin.from("profiles").select("display_name").eq("id", me).maybeSingle();
      title = `${p?.display_name || "Someone"} ${RESPONSE_TEXT[r.response] || "responded"}`;
      body = "Open Shecurity to see who's responding.";
      urgent = true;
      recipients = [alert.sender_id];
    } else {
      return json({ error: "unknown type" }, 400);
    }

    if (!recipients.length) return json({ sent: 0 });
    const { data: subs } = await admin.from("push_subscriptions").select("*").in("user_id", recipients);
    if (!subs?.length) return json({ sent: 0, note: "no devices with alerts on" });

    const { data: pub } = await admin.rpc("get_app_secret", { p_name: "vapid_public" });
    const { data: priv } = await admin.rpc("get_app_secret", { p_name: "vapid_private" });
    const { data: subject } = await admin.rpc("get_app_secret", { p_name: "vapid_subject" });
    webpush.setVapidDetails(subject || "mailto:hello@shecurity.app", pub, priv);

    const payload = JSON.stringify({ title, body, tag: alert.id, urgent, url: "./#circle" });
    let sent = 0;
    const failures: number[] = [];
    await Promise.all(subs.map(async (s) => {
      try {
        if (s.endpoint.startsWith("fcm:")) {
          const code = await sendFcm(s.endpoint.slice(4), { title, body, tag: alert.id, urgent });
          if (code === 200) { sent++; return; }
          if (code === 0) return;
          throw Object.assign(new Error("fcm"), { statusCode: code === 404 || code === 400 ? 410 : code });
        }
        await webpush.sendNotification({ endpoint: s.endpoint, keys: { p256dh: s.p256dh, auth: s.auth } }, payload, {
          TTL: 3600,
          urgency: urgent ? "high" : "normal",
        });
        sent++;
      } catch (e) {
        const code = (e as { statusCode?: number }).statusCode || 0;
        failures.push(code);
        if (code === 404 || code === 410) await admin.from("push_subscriptions").delete().eq("endpoint", s.endpoint);
      }
    }));
    return json({ sent, failed: failures.length, codes: failures });
  } catch (e) {
    return json({ error: String((e as Error).message || e) }, 500);
  }
});
