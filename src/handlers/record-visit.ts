import { createClient } from "@supabase/supabase-js";

const headers = { "Access-Control-Allow-Origin": "*", "Access-Control-Allow-Headers": "authorization, apikey, content-type, x-client-info", "Content-Type": "application/json" };
export default async function handler(req: Request): Promise<Response> {
  if (req.method === "OPTIONS") return new Response(null, { headers });
  if (req.method !== "POST") return new Response(null, { status: 405, headers });
  const client = createClient(process.env.SUPABASE_URL ?? "", process.env.SUPABASE_SERVICE_ROLE_KEY ?? "");
  const token = req.headers.get("authorization")?.replace(/^Bearer\s+/i, "");
  if (!token) return new Response(null, { status: 401, headers });
  const { data: { user }, error } = await client.auth.getUser(token);
  if (error || !user) return new Response(null, { status: 401, headers });
  // Only request metadata is accepted; callers cannot supply another user or timestamp.
  const rawIp = req.headers.get("x-forwarded-for")?.split(",")[0]?.trim() ?? null;
  const ip = rawIp && /^[0-9a-fA-F:.]+$/.test(rawIp) ? rawIp : null;
  const rawCountry = req.headers.get("cf-ipcountry");
  const country = rawCountry && /^[A-Z]{2}$/.test(rawCountry) && !["XX", "T1"].includes(rawCountry) ? rawCountry : null;
  const { error: saveError } = await client.from("user_last_visits").upsert({ user_id: user.id, ip_address: ip, country, last_seen_at: new Date().toISOString() });
  return new Response(JSON.stringify({ ok: !saveError }), { status: saveError ? 500 : 200, headers });
}

