import type { Config } from "@netlify/functions";
import { issueSession } from "./_shared/auth";
import { appleUserID, refreshTokenFromCode } from "./_shared/apple";
import { saveAccount } from "./_shared/accounts";
import { json } from "./_shared/http";

export default async (req: Request) => {
  if (req.method !== "POST") return json({ error: "Method not allowed" }, 405);

  const raw = await req.text();
  if (raw.length > 20_000) return json({ error: "Couldn't sign in. Try again." }, 400);

  let payload: Record<string, unknown>;
  try {
    const parsed = JSON.parse(raw) as unknown;
    if (!parsed || typeof parsed !== "object" || Array.isArray(parsed)) {
      return json({ error: "Couldn't sign in. Try again." }, 400);
    }
    payload = parsed as Record<string, unknown>;
  } catch {
    return json({ error: "Couldn't sign in. Try again." }, 400);
  }

  if (typeof payload.identity_token !== "string" || payload.identity_token.length === 0) {
    return json({ error: "Couldn't sign in. Try again." }, 400);
  }

  let sub: string;
  try {
    sub = await appleUserID(payload.identity_token);
  } catch (error) {
    console.error("Apple identity token rejected", error);
    return json({ error: "Couldn't sign in. Try again." }, 401);
  }

  let refreshToken: string | null = null;
  if (typeof payload.authorization_code === "string" && payload.authorization_code.length > 0) {
    try {
      refreshToken = await refreshTokenFromCode(payload.authorization_code);
    } catch (error) {
      console.error("Apple authorization code exchange failed", error);
      return json({ error: "Couldn't sign in. Try again." }, 502);
    }
  }

  try {
    await saveAccount(sub, refreshToken);
    const token = await issueSession(sub);
    return json({ token }, 200);
  } catch (error) {
    console.error("Could not start session", error);
    return json({ error: "Photo estimates aren't available right now." }, 503);
  }
};

export const config: Config = {
  path: "/api/session",
  method: "POST",
};
