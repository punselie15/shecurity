// Lets a paired watch raise an SOS or share location for its owner, using the watch key
// the phone app handed it (see watch-setup.sql), then pushes the alert to the circle.
import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import webpush from "npm:web-push@3.6.7";
import { createClient } from "npm:@supabase/supabase-js@2.45.4";

const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), { status, headers: { "Content-Type": "application/json" } });
const num = (v: unknown) => (typeof v === "number" && isFinite(v) ? v : null);

const TEXT: Record<string, (n: string) => [string, string, boolean]> = {
  sos: (n) => [`${n} needs help`, "Sent from her watch. Open Shecurity to see where she is.", true],
  location: (n) => [`${n} shared her location`, "Tap to see where she is.", false],
};

Deno.serve(async (req) => {
  if (req.method !== "POST") return json({ error: "POST only" }, 405);
  try {
    const admin = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!, {
      auth: { persistSession: false },
    });
    const b = await req.json();
    const kind = b.kind === "location" ? "location" : "sos";
    if (typeof b.key !== "string" || !/^shw_[0-9a-f]{48}$/.test(b.key)) return json({ error: "bad key" }, 401);
    const { data: me } = await admin.rpc("watch_key_user", { p_key: b.key });
    if (!me) return json({ error: "unknown key" }, 401);

    // one alert per 20 seconds is plenty, even if the button is pressed again
    const { data: last } = await admin.from("alerts").select("id, created_at, kind").eq("sender_id", me)
      .order("created_at", { ascending: false }).limit(1).maybeSingle();
    if (last && last.kind === kind && Date.now() - new Date(last.created_at).getTime() < 20000) {
      return json({ id: last.id, sent: 0, note: "already sent" });
    }

    const row = {
      sender_id: me, kind, message: typeof b.message === "string" ? b.message.slice(0, 300) : null,
      lat: num(b.lat), lng: num(b.lng), accuracy: num(b.accuracy) === null ? null : Math.round(b.accuracy),
      battery: num(b.battery) === null ? null : Math.round(b.battery),
    };
    const { data: alert, error } = await admin.from("alerts").insert(row).select().single();
    if (error) return json({ error: error.message }, 400);

    const { data: mine } = await admin.from("circle_members").select("circle_id").eq("user_id", me);
    const circleIds = (mine || []).map((r) => r.circle_id);
    const { data: mates } = circleIds.length
      ? await admin.from("circle_members").select("user_id").in("circle_id", circleIds)
      : { data: [] as { user_id: string }[] };
    const recipients = [...new Set((mates || []).map((m) => m.user_id))].filter((id) => id !== me);
    await admin.from("alerts").update({ notified_at: new Date().toISOString() }).eq("id", alert.id);
    if (!recipients.length) return json({ id: alert.id, sent: 0, note: "no one in your circle yet" });

    const { data: p } = await admin.from("profiles").select("display_name").eq("id", me).maybeSingle();
    const [title, body, urgent] = TEXT[kind](p?.display_name || "Someone in your circle");
    const { data: subs } = await admin.from("push_subscriptions").select("*").in("user_id", recipients);
    if (!subs?.length) return json({ id: alert.id, sent: 0, note: "no devices with alerts on" });

    const { data: pub } = await admin.rpc("get_app_secret", { p_name: "vapid_public" });
    const { data: priv } = await admin.rpc("get_app_secret", { p_name: "vapid_private" });
    const { data: subject } = await admin.rpc("get_app_secret", { p_name: "vapid_subject" });
    webpush.setVapidDetails(subject || "mailto:hello@shecurity.app", pub, priv);
    const payload = JSON.stringify({ title, body, tag: alert.id, urgent, url: "./#circle" });
    let sent = 0;
    await Promise.all(subs.map(async (s) => {
      try {
        await webpush.sendNotification({ endpoint: s.endpoint, keys: { p256dh: s.p256dh, auth: s.auth } }, payload, {
          TTL: 3600, urgency: urgent ? "high" : "normal",
        });
        sent++;
      } catch (e) {
        const code = (e as { statusCode?: number }).statusCode || 0;
        if (code === 404 || code === 410) await admin.from("push_subscriptions").delete().eq("endpoint", s.endpoint);
      }
    }));
    return json({ id: alert.id, sent });
  } catch (e) {
    return json({ error: String((e as Error).message || e) }, 500);
  }
});
