import type { Config } from "@netlify/functions";
import { authorize } from "./_shared/auth";
import { deleteAccount } from "./_shared/accounts";
import { revokeAppleSignIn } from "./_shared/apple";
import { json } from "./_shared/http";

export default async (req: Request) => {
  if (req.method !== "DELETE") return json({ error: "Method not allowed" }, 405);

  const sub = await authorize(req);
  if (sub instanceof Response) return sub;

  // Present for Sign in with Apple accounts: a fresh code from the app, so the
  // Apple ID connection can be revoked along with the account.
  let appleCode = "";
  try {
    const body = (await req.json()) as { apple_authorization_code?: unknown };
    if (typeof body.apple_authorization_code === "string") appleCode = body.apple_authorization_code;
  } catch {
    // No body: not an Apple account.
  }

  if (appleCode) {
    try {
      await revokeAppleSignIn(appleCode);
    } catch (error) {
      // Still delete. Keeping someone's account because Apple was unreachable would be worse.
      console.error("Apple revoke failed", error);
    }
  }

  try {
    await deleteAccount(sub);
  } catch (error) {
    console.error("Account deletion failed", error);
    return json({ error: "Couldn't delete the account. Try again." }, 502);
  }

  return json({ ok: true }, 200);
};

export const config: Config = {
  path: "/api/account",
  method: "DELETE",
};
