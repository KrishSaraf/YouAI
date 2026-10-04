import { getStore } from "@netlify/blobs";
import { revokeRefreshToken } from "./apple";

const STORE = "youai";

type Account = { refreshToken: string | null };

function store() {
  return getStore(STORE);
}

export async function getAccount(sub: string): Promise<Account | null> {
  const value = await store().get(`account:${sub}`, { type: "json", consistency: "strong" });
  if (!value || typeof value !== "object") return null;
  const refreshToken = (value as { refreshToken?: unknown }).refreshToken;
  return { refreshToken: typeof refreshToken === "string" ? refreshToken : null };
}

export async function saveAccount(sub: string, refreshToken: string | null) {
  const existing = await getAccount(sub);
  const account: Account = { refreshToken: refreshToken ?? existing?.refreshToken ?? null };
  await store().setJSON(`account:${sub}`, account);
}

export async function deleteAccount(sub: string) {
  const account = await getAccount(sub);
  if (account?.refreshToken) {
    try {
      await revokeRefreshToken(account.refreshToken);
    } catch (error) {
      console.error("Could not revoke Sign in with Apple", error);
    }
  }

  await store().delete(`account:${sub}`);
  const listed = await store().list({ prefix: `usage:${sub}:` });
  await Promise.all(listed.blobs.map((blob) => store().delete(blob.key)));
}

function dailyLimit() {
  const raw = Number(Netlify.env.get("DAILY_PHOTO_LIMIT"));
  if (!Number.isFinite(raw) || raw <= 0) return 20;
  return Math.min(100, Math.floor(raw));
}

/// Counts one photo against the signed-in user. Returns false when today's cap is spent.
export async function consumePhotoCredit(sub: string) {
  const day = new Date().toISOString().slice(0, 10);
  const key = `usage:${sub}:${day}`;
  const current = Number((await store().get(key, { consistency: "strong" })) ?? "0");
  if (current >= dailyLimit()) return false;
  await store().set(key, String(current + 1));
  return true;
}
