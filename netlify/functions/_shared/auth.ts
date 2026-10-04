import { createClient, type SupabaseClient } from "@supabase/supabase-js";
import WebSocket from "ws";
import { json } from "./http";

// Netlify's function runtime does not provide a global WebSocket. The Supabase
// client constructs one during startup, so install the same implementation Node 22 uses.
if (typeof globalThis.WebSocket === "undefined") {
  globalThis.WebSocket = WebSocket as unknown as typeof globalThis.WebSocket;
}

export function supabaseAdmin(): SupabaseClient | null {
  const url = Netlify.env.get("SUPABASE_URL");
  const key = Netlify.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!url || !key) return null;
  return createClient(url, key, {
    auth: { persistSession: false, autoRefreshToken: false },
  });
}

/// Returns the signed-in user id, or a response the handler should return as-is.
export async function authorize(req: Request): Promise<string | Response> {
  const client = supabaseAdmin();
  if (!client) {
    console.error("SUPABASE_URL or SUPABASE_SERVICE_ROLE_KEY is not set");
    return json({ error: "Photo estimates aren't available right now." }, 503);
  }

  const header = req.headers.get("authorization") ?? "";
  const token = header.startsWith("Bearer ") ? header.slice("Bearer ".length).trim() : "";
  if (!token) return json({ error: "Sign in again to estimate from a photo." }, 401);

  const { data, error } = await client.auth.getUser(token);
  if (error || !data.user) {
    return json({ error: "Sign in again to estimate from a photo." }, 401);
  }
  return data.user.id;
}
