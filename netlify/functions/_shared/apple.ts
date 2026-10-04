import { createRemoteJWKSet, importPKCS8, jwtVerify, SignJWT } from "jose";

const appleJWKS = createRemoteJWKSet(new URL("https://appleid.apple.com/auth/keys"));

function bundleID() {
  return Netlify.env.get("APPLE_BUNDLE_ID") || "com.ht.YouAI";
}

export async function appleUserID(identityToken: string) {
  const { payload } = await jwtVerify(identityToken, appleJWKS, {
    issuer: "https://appleid.apple.com",
    audience: bundleID(),
  });
  if (!payload.sub) throw new Error("Apple token had no subject");
  return payload.sub;
}

function appleCredentials() {
  const privateKey = Netlify.env.get("APPLE_PRIVATE_KEY");
  const teamID = Netlify.env.get("APPLE_TEAM_ID");
  const keyID = Netlify.env.get("APPLE_KEY_ID");
  if (!privateKey || !teamID || !keyID) return null;
  return { privateKey: privateKey.replace(/\\n/g, "\n"), teamID, keyID };
}

async function appleClientSecret() {
  const credentials = appleCredentials();
  if (!credentials) return null;
  const key = await importPKCS8(credentials.privateKey, "ES256");
  const clientSecret = await new SignJWT({})
    .setProtectedHeader({ alg: "ES256", kid: credentials.keyID })
    .setIssuer(credentials.teamID)
    .setSubject(bundleID())
    .setAudience("https://appleid.apple.com")
    .setIssuedAt()
    .setExpirationTime("5m")
    .sign(key);
  return { clientSecret, clientID: bundleID() };
}

/// Exchanges the one-time authorization code for a refresh token so account
/// deletion can disconnect Sign in with Apple. Returns null when the Apple
/// key is not configured yet.
export async function refreshTokenFromCode(code: string) {
  const client = await appleClientSecret();
  if (!client) return null;

  const response = await fetch("https://appleid.apple.com/auth/token", {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      client_id: client.clientID,
      client_secret: client.clientSecret,
      code,
      grant_type: "authorization_code",
    }),
  });
  const text = await response.text();
  if (!response.ok) {
    console.error("Apple token exchange failed", response.status, text.slice(0, 300));
    throw new Error("Apple token exchange failed");
  }
  const parsed = JSON.parse(text) as { refresh_token?: string };
  return parsed.refresh_token ?? null;
}

export async function revokeRefreshToken(refreshToken: string) {
  const client = await appleClientSecret();
  if (!client) return;

  const response = await fetch("https://appleid.apple.com/auth/revoke", {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      client_id: client.clientID,
      client_secret: client.clientSecret,
      token: refreshToken,
      token_type_hint: "refresh_token",
    }),
  });
  if (!response.ok) {
    console.error("Apple revoke failed", response.status, (await response.text()).slice(0, 300));
    throw new Error("Apple revoke failed");
  }
}
