import { createPrivateKey, sign } from "node:crypto";

// Sign in with Apple accounts must be disconnected from the Apple ID when the
// account is deleted. Apple needs a fresh authorization code from the app,
// which is swapped for a refresh token and then revoked.

const APPLE_AUTH = "https://appleid.apple.com/auth";

type AppleConfig = { teamID: string; keyID: string; clientID: string; privateKey: string };

function config(): AppleConfig | null {
  const teamID = Netlify.env.get("APPLE_TEAM_ID");
  const keyID = Netlify.env.get("APPLE_KEY_ID");
  const clientID = Netlify.env.get("APPLE_CLIENT_ID");
  // The .p8 contents. Newlines may be stored as \n in the dashboard.
  const privateKey = Netlify.env.get("APPLE_PRIVATE_KEY")?.replace(/\\n/g, "\n");
  if (!teamID || !keyID || !clientID || !privateKey) return null;
  return { teamID, keyID, clientID, privateKey };
}

function base64url(input: Buffer | string) {
  return Buffer.from(input).toString("base64url");
}

/// Short-lived client secret: an ES256 JWT signed with the Sign in with Apple key.
function clientSecret(cfg: AppleConfig) {
  const now = Math.floor(Date.now() / 1000);
  const header = base64url(JSON.stringify({ alg: "ES256", kid: cfg.keyID }));
  const claims = base64url(JSON.stringify({
    iss: cfg.teamID,
    iat: now,
    exp: now + 300,
    aud: "https://appleid.apple.com",
    sub: cfg.clientID,
  }));
  const signature = sign("sha256", Buffer.from(`${header}.${claims}`), {
    key: createPrivateKey(cfg.privateKey),
    dsaEncoding: "ieee-p1363",
  });
  return `${header}.${claims}.${base64url(signature)}`;
}

async function post(path: string, fields: Record<string, string>) {
  return fetch(`${APPLE_AUTH}/${path}`, {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams(fields),
    signal: AbortSignal.timeout(10_000),
  });
}

/// Revokes the app's access to the person's Apple ID. Throws when it couldn't.
export async function revokeAppleSignIn(authorizationCode: string) {
  const cfg = config();
  if (!cfg) throw new Error("Sign in with Apple revoke is not configured");
  const secret = clientSecret(cfg);

  const tokenResponse = await post("token", {
    client_id: cfg.clientID,
    client_secret: secret,
    code: authorizationCode,
    grant_type: "authorization_code",
  });
  const tokens = (await tokenResponse.json().catch(() => ({}))) as {
    refresh_token?: string;
    access_token?: string;
    error?: string;
  };
  const token = tokens.refresh_token ?? tokens.access_token;
  if (!tokenResponse.ok || !token) {
    throw new Error(`Apple token exchange failed: ${tokenResponse.status} ${tokens.error ?? ""}`);
  }

  const revokeResponse = await post("revoke", {
    client_id: cfg.clientID,
    client_secret: secret,
    token,
    token_type_hint: tokens.refresh_token ? "refresh_token" : "access_token",
  });
  if (!revokeResponse.ok) {
    throw new Error(`Apple revoke failed: ${revokeResponse.status}`);
  }
}
