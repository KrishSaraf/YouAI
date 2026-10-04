import type { Config } from "@netlify/functions";
import { authorize } from "./_shared/auth";
import { deleteAccount } from "./_shared/accounts";
import { json } from "./_shared/http";

export default async (req: Request) => {
  if (req.method !== "DELETE") return json({ error: "Method not allowed" }, 405);

  const sub = await authorize(req);
  if (sub instanceof Response) return sub;

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
