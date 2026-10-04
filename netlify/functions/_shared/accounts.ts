import { supabaseAdmin } from "./auth";

function dailyLimit() {
  const raw = Number(Netlify.env.get("DAILY_PHOTO_LIMIT"));
  if (!Number.isFinite(raw) || raw <= 0) return 20;
  return Math.min(100, Math.floor(raw));
}

/// Counts one photo against the signed-in user. Returns false when today's cap is spent.
export async function consumePhotoCredit(userID: string) {
  const client = supabaseAdmin();
  if (!client) throw new Error("Supabase is not configured");

  const { data, error } = await client.rpc("consume_photo_credit", {
    target_user: userID,
    daily_limit: dailyLimit(),
  });
  if (error) throw error;
  return data === true;
}

export async function deleteAccount(userID: string) {
  const client = supabaseAdmin();
  if (!client) throw new Error("Supabase is not configured");

  const { error } = await client.auth.admin.deleteUser(userID);
  if (error) throw error;
}
