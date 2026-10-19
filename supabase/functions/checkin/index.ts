// eMail to Claude: app check-in.
//
// Called by the app when it opens and about once a week for updates. It
//  - records the install (device ID and the two dates; analytics fields only with consent),
//  - checks the license key when an update check is requested,
//  - hands out a short-lived download link for a newer release when the license is valid.
//
// Runs with the service role; the tables have RLS enabled and no policies, so nothing else can read them.
// Deployed with verify_jwt = false: the app sends no credentials, and every field is validated here.

import { createClient } from "jsr:@supabase/supabase-js@2";
import { isIP } from "node:net";

const supabase = createClient(
  Deno.env.get("SUPABASE_URL")!,
  Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
  { auth: { persistSession: false } },
);

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const VERSION = /^\d+(\.\d+){0,3}$/;
const SIGNED_URL_SECONDS = 900;
const MIN_REWRITE_SECONDS = 60;

type LicenseStatus = "valid" | "missing" | "invalid" | "revoked" | "expired";

interface Body {
  device_id?: unknown;
  event?: unknown;
  action?: unknown;
  analytics?: unknown;
  wants_update?: unknown;
  app_version?: unknown;
  macos_version?: unknown;
  os_language?: unknown;
  license_key?: unknown;
}

const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json", "Cache-Control": "no-store" },
  });

const clip = (value: unknown, max: number): string | null => {
  if (typeof value !== "string") return null;
  const trimmed = value.trim().slice(0, max);
  return trimmed.length > 0 ? trimmed : null;
};

function compareVersions(a: string, b: string): number {
  const pa = a.split(".").map((n) => parseInt(n, 10) || 0);
  const pb = b.split(".").map((n) => parseInt(n, 10) || 0);
  for (let i = 0; i < Math.max(pa.length, pb.length); i++) {
    const diff = (pa[i] ?? 0) - (pb[i] ?? 0);
    if (diff !== 0) return diff;
  }
  return 0;
}

function clientIp(req: Request): string | null {
  const candidates = [
    req.headers.get("cf-connecting-ip"),
    req.headers.get("x-forwarded-for")?.split(",")[0],
    req.headers.get("x-real-ip"),
  ];
  for (const candidate of candidates) {
    const ip = candidate?.trim();
    if (ip && isIP(ip) !== 0) return ip;
  }
  return null;
}

// Country and city for an IP. With an IPINFO_TOKEN secret it asks ipinfo.io; otherwise it uses
// location headers when the platform forwards them. Returns nulls when neither is available.
async function lookupGeo(ip: string | null, req: Request): Promise<{ country: string | null; city: string | null }> {
  const token = Deno.env.get("IPINFO_TOKEN");
  if (ip && token) {
    try {
      const res = await fetch(`https://ipinfo.io/${ip}?token=${token}`, { signal: AbortSignal.timeout(2500) });
      if (res.ok) {
        const data = await res.json();
        return { country: clip(data.country, 8), city: clip(data.city, 128) };
      }
    } catch (error) {
      console.error("geo lookup failed", error);
    }
  }
  const country = clip(req.headers.get("cf-ipcountry"), 8);
  return {
    country: country && country !== "XX" && country !== "T1" ? country : null,
    city: clip(req.headers.get("cf-ipcity"), 128),
  };
}

async function licenseStatus(rawKey: string | null): Promise<LicenseStatus> {
  const key = rawKey?.toUpperCase() ?? "";
  if (!key) return "missing";
  const { data, error } = await supabase.from("licenses").select("status, expires_at").eq("key", key).maybeSingle();
  if (error) throw error;
  if (!data) return "invalid";
  if (data.status !== "active") return "revoked";
  if (data.expires_at && new Date(data.expires_at) < new Date()) return "expired";
  return "valid";
}

Deno.serve(async (req) => {
  if (req.method !== "POST") return json({ error: "method_not_allowed" }, 405);

  let body: Body;
  try {
    body = await req.json();
  } catch {
    return json({ error: "bad_request" }, 400);
  }

  const deviceId = typeof body.device_id === "string" ? body.device_id.toLowerCase() : "";
  if (!UUID.test(deviceId)) return json({ error: "bad_device_id" }, 400);

  try {
    // Erase everything stored for this device.
    if (body.action === "erase") {
      const { error } = await supabase.from("installs").delete().eq("device_id", deviceId);
      if (error) throw error;
      return json({ ok: true });
    }

    const analytics = body.analytics === true;
    const wantsUpdate = body.wants_update === true;
    const appVersion = clip(body.app_version, 32);
    const macosVersion = clip(body.macos_version, 64);
    const licenseKey = clip(body.license_key, 64);
    const now = new Date();

    // --- Record the check-in -------------------------------------------------------------
    const { data: existing, error: readError } = await supabase
      .from("installs")
      .select("last_used_at, analytics_consent")
      .eq("device_id", deviceId)
      .maybeSingle();
    if (readError) throw readError;

    const consentChanged = !existing || existing.analytics_consent !== analytics;
    const recentlyWritten = existing && now.getTime() - new Date(existing.last_used_at).getTime() < MIN_REWRITE_SECONDS * 1000;

    if (consentChanged || !recentlyWritten) {
      const ip = analytics ? clientIp(req) : null;
      const geo = analytics ? await lookupGeo(ip, req) : { country: null, city: null };
      const row: Record<string, unknown> = {
        device_id: deviceId,
        last_used_at: now.toISOString(),
        analytics_consent: analytics,
        // Analytics fields exist only while consent is given; opting out clears them.
        macos_version: analytics ? macosVersion : null,
        os_language: analytics ? clip(body.os_language, 32) : null,
        app_version: analytics ? appVersion : null,
        ip_address: ip,
        ip_country: geo.country,
        ip_city: geo.city,
        license_key: analytics ? licenseKey : null,
      };
      if (consentChanged) row.consent_updated_at = now.toISOString();
      // first_open_at is left out so an existing value is kept; new rows get the column default.
      const { error } = await supabase.from("installs").upsert(row, { onConflict: "device_id" });
      if (error) throw error;
    }

    if (!wantsUpdate) return json({ ok: true });

    // --- License and updates -------------------------------------------------------------
    const license = await licenseStatus(licenseKey);

    const { data: releases, error: releasesError } = await supabase.from("releases").select("*").eq("published", true);
    if (releasesError) throw releasesError;
    const latest = (releases ?? [])
      .filter((r) => VERSION.test(r.version))
      .sort((a, b) => compareVersions(b.version, a.version))[0];

    const response: Record<string, unknown> = { ok: true, license, latest_version: latest?.version ?? null };

    const newer = latest && appVersion && VERSION.test(appVersion) && compareVersions(latest.version, appVersion) > 0;
    if (newer) {
      if (license === "valid") {
        const { data: signed, error } = await supabase.storage.from("releases").createSignedUrl(latest.dmg_path, SIGNED_URL_SECONDS);
        if (error || !signed) throw error ?? new Error("no signed url");
        response.update = {
          version: latest.version,
          notes: latest.notes,
          sha256: latest.sha256,
          min_macos: latest.min_macos,
          url: signed.signedUrl,
        };
      } else {
        response.update_blocked = { version: latest.version, reason: license };
      }
    }
    return json(response);
  } catch (error) {
    console.error("checkin failed", error);
    return json({ error: "server_error" }, 500);
  }
});
