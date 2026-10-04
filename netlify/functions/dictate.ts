import type { Config } from "@netlify/functions";
import { authorize } from "./_shared/auth";
import { consumeVoiceCredit } from "./_shared/accounts";
import { json } from "./_shared/http";

const OPENROUTER_URL = "https://openrouter.ai/api/v1/chat/completions";
const DEFAULT_MODEL = "google/gemini-2.5-flash";

const PROMPT = [
  "You turn one spoken log into JSON for a health app used in Singapore.",
  "The person may speak English or Singlish. Keep local food names: chicken rice, cai png, nasi lemak, laksa, roti prata, kopi, teh, bubble tea.",
  "Variants change the numbers. Steamed or roasted, soup or dry, skin on or off, less rice, extra gravy, kopi-o versus kopi with milk and sugar.",
  "",
  "Decide the kind:",
  "- meal: food or a drink that is not plain water",
  "- workout: exercises with weight and reps",
  "- weight: body weight",
  "- water: water they drank",
  "- sleep: when they slept",
  "- habit: ticking a daily habit",
  "- unclear: you cannot tell",
  "",
  "Reply with only a JSON object. No prose, no markdown, no code fence.",
  'Always include "kind" and "summary". summary is one short sentence restating what will be saved.',
  "",
  "When kind is meal, also include:",
  '  "name": at most 5 words, as a person would log it',
  '  "meal_type": breakfast, lunch, dinner, or snack',
  '  "calories": kilocalories for the serving they described, nearest 10',
  '  "protein_g", "carbs_g", "fat_g": grams, nearest gram',
  '  "note": one sentence on the portion you assumed',
  "",
  "When kind is workout, also include:",
  '  "name": short session name',
  '  "duration_minutes": a number, 45 if they did not say',
  '  "exercises": [{ "name", "sets": [{ "weight_kg", "reps" }] }]',
  "Convert pounds to kilograms. If they say three sets of 8 at 60 kilos, repeat that set three times.",
  "",
  "When kind is weight, include \"kilograms\". Convert pounds.",
  "When kind is water, include \"millilitres\". A glass is 250 and a bottle is 500 unless they said otherwise.",
  'When kind is sleep, include "asleep_hour", "asleep_minute", "awake_hour", "awake_minute" on a 24-hour clock. 11.30 at night is 23 and 30.',
  'When kind is habit, include "name" as the short habit they named.',
  "When kind is unclear, include only kind and summary.",
].join("\n");

export default async (req: Request) => {
  if (req.method !== "POST") return json({ error: "Couldn't log that. Try again." }, 405);

  const apiKey = Netlify.env.get("OPENROUTER_API_KEY");
  if (!apiKey) return json({ error: "Voice logs aren't available right now." }, 503);

  const sub = await authorize(req);
  if (sub instanceof Response) return sub;

  let text = "";
  try {
    const body = (await req.json()) as { text?: unknown };
    if (typeof body.text === "string") text = body.text.trim();
  } catch {
    return json({ error: "Couldn't log that. Try again." }, 400);
  }

  if (text.length < 2 || text.length > 2000) {
    return json({ error: "Say a little more, then try again." }, 400);
  }

  try {
    const allowed = await consumeVoiceCredit(sub);
    if (!allowed) {
      return json({ error: "You've used today's voice logs. Try again tomorrow." }, 429);
    }
  } catch (error) {
    console.error("Voice quota check failed", error);
    return json({ error: "Voice logs aren't available right now." }, 503);
  }

  const model = Netlify.env.get("OPENROUTER_VISION_MODEL") || DEFAULT_MODEL;
  let upstream: Response;
  try {
    upstream = await fetch(OPENROUTER_URL, {
      method: "POST",
      headers: {
        Authorization: `Bearer ${apiKey}`,
        "Content-Type": "application/json",
        Accept: "application/json",
        "HTTP-Referer": "https://youai.app",
        "X-Title": "Lean Lah!",
      },
      body: JSON.stringify({
        model,
        messages: [
          {
            role: "user",
            content: [
              { type: "text", text: PROMPT },
              { type: "text", text: text },
            ],
          },
        ],
        max_tokens: 900,
        temperature: 0.2,
        stream: false,
      }),
      signal: AbortSignal.timeout(50_000),
    });
  } catch (error) {
    console.error("OpenRouter request failed", error);
    return json({ error: "Couldn't log that. Try again." }, 502);
  }

  const upstreamText = await upstream.text();
  if (!upstream.ok) {
    console.error("OpenRouter", upstream.status, upstreamText.slice(0, 500));
    return json({ error: "Couldn't log that. Try again." }, 502);
  }

  return new Response(upstreamText, {
    status: 200,
    headers: { "Content-Type": "application/json" },
  });
};

export const config: Config = {
  path: "/api/dictate",
  method: "POST",
};
