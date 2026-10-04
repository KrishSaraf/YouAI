import { jwtVerify, SignJWT } from "jose";
import { getAccount } from "./accounts";
import { json } from "./http";

function sessionKey() {
  const value = Netlify.env.get("SESSION_SECRET");
  if (!value || value.length < 32) return null;
  return new TextEncoder().encode(value);
}

export async function issueSession(sub: string) {
  const key = sessionKey();
  if (!key) throw new Error("SESSION_SECRET is not set");
  return new SignJWT({})
    .setProtectedHeader({ alg: "HS256" })
    .setSubject(sub)
    .setIssuer("youai")
    .setIssuedAt()
    .setExpirationTime("30d")
    .sign(key);
}

async function subjectFromAuthorization(header: string | null) {
  if (!header?.startsWith("Bearer ")) return null;
  const token = header.slice("Bearer ".length).trim();
  const key = sessionKey();
  if (!key || !token) return null;
  try {
    const { payload } = await jwtVerify(token, key, { issuer: "youai" });
    return payload.sub ?? null;
  } catch {
    return null;
  }
}

/// Returns the Apple user id, or a response the handler should return as-is.
export async function authorize(req: Request): Promise<string | Response> {
  if (!sessionKey()) {
    console.error("SESSION_SECRET is not set");
    return json({ error: "Photo estimates aren't available right now." }, 503);
  }

  const sub = await subjectFromAuthorization(req.headers.get("authorization"));
  if (!sub) return json({ error: "Sign in again to estimate from a photo." }, 401);

  try {
    const account = await getAccount(sub);
    if (!account) return json({ error: "Sign in again to estimate from a photo." }, 401);
    return sub;
  } catch (error) {
    console.error("Account lookup failed", error);
    return json({ error: "Photo estimates aren't available right now." }, 503);
  }
}
