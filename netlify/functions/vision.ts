import type { Config } from "@netlify/functions";
import { authorize } from "./_shared/auth";
import { consumePhotoCredit } from "./_shared/accounts";
import { json } from "./_shared/http";

const OPENROUTER_URL = "https://openrouter.ai/api/v1/chat/completions";
const DEFAULT_MODEL = "google/gemini-2.5-flash";

// Photos are compressed under ~170 KB of base64 before they leave the phone.
const MAX_BODY_CHARS = 400_000;
const MAX_IMAGE_CHARS = 180_000;

const tasks = {
  meal: {
    prompt: [
      "You are a careful nutrition estimator. The user will log this estimate only after reviewing it, so accuracy matters more than a round restaurant-menu number.",
      "",
      "Look only at what is visible. Estimate the serving in the photo, not a generic database entry for the dish name.",
      "1. List the visible components: protein, starch or bread, vegetables, fruit, sauce, oil, cheese, dressing, and any drink.",
      "2. Judge portion size from the plate, bowl, utensils, hands, or packaging in the frame. If scale is unclear, assume a typical single serving and say so.",
      "3. Estimate each component, then sum. Count cooking oil, sauces, cheese, nuts, and dressings. They often dominate the calories. Do not invent hidden ingredients.",
      "4. If several foods are on one plate, name the plate as a whole and include all of them. If it is only a drink, estimate the drink.",
      "",
      "Reply with only a JSON object. No prose, no markdown, no code fence. Use numbers, not numeric strings. Keys:",
      '  "name": short dish name, at most 5 words, as a person would log it',
      '  "meal_type": one of breakfast, lunch, dinner, snack, chosen by what the food is',
      '  "calories": total kilocalories for the serving shown, rounded to the nearest 10',
      '  "protein_g", "carbs_g", "fat_g": grams for that same serving, rounded to the nearest gram',
      '  "note": one short sentence on the portion you assumed and any uncertain item',
      "",
      'Protein, carbs, and fat should be plausible for the calorie total. If the photo does not contain food or drink, set "name" to "No food detected", all numbers to 0, and "note" to "No food in the photo."',
    ].join("\n"),
    schema: {
      type: "object",
      properties: {
        name: { type: "string" },
        meal_type: { type: "string", enum: ["breakfast", "lunch", "dinner", "snack"] },
        calories: { type: "number" },
        protein_g: { type: "number" },
        carbs_g: { type: "number" },
        fat_g: { type: "number" },
        note: { type: "string" },
      },
      required: ["name", "meal_type", "calories", "protein_g", "carbs_g", "fat_g"],
      additionalProperties: false,
    },
  },
  equipment: {
    prompt: [
      "You are a strength coach identifying gym equipment from a photo so the user can start a workout log.",
      "",
      "Name only the main piece that fills the frame. Distinguish lookalikes: leg extension versus leg curl, lat pulldown versus seated row, hack squat versus leg press, Smith machine versus a power rack, cable station versus a specific cable machine.",
      "Use the name a lifter would say, not a brand, unless the brand label is clearly readable. Do not invent a brand.",
      "If several machines are visible, identify the closest one. Ignore people, flooring, and loose plates unless they are the subject.",
      "",
      "Reply with only a JSON object. No prose, no markdown, no code fence. Keys:",
      '  "equipment_name": the machine or implement',
      '  "suggested_exercises": up to 5 exercises this exact piece is actually used for, most common first. Name each the way a lifter would log it, for example "Lat pulldown" or "Romanian deadlift". Do not pad the list with unrelated movements.',
      '  "note": one short setup cue for this piece, such as seat height, pad position, or grip. No lecture.',
      "",
      'If there is no gym equipment in the photo, set "equipment_name" to "No equipment detected", "suggested_exercises" to [], and "note" to "No gym equipment in the photo."',
    ].join("\n"),
    schema: {
      type: "object",
      properties: {
        equipment_name: { type: "string" },
        suggested_exercises: {
          type: "array",
          items: { type: "string" },
          maxItems: 5,
        },
        note: { type: "string" },
      },
      required: ["equipment_name", "suggested_exercises"],
      additionalProperties: false,
    },
  },
} as const;

type TaskName = keyof typeof tasks;

export default async (req: Request) => {
  if (req.method !== "POST") {
    return json({ error: "Method not allowed" }, 405);
  }

  const apiKey = Netlify.env.get("OPENROUTER_API_KEY");
  if (!apiKey) {
    console.error("OPENROUTER_API_KEY is not set");
    return json({ error: "Photo estimates aren't available right now." }, 503);
  }

  const sub = await authorize(req);
  if (sub instanceof Response) return sub;

  const raw = await req.text();
  if (raw.length > MAX_BODY_CHARS) {
    return json({ error: "That photo is too large." }, 413);
  }

  let payload: Record<string, unknown>;
  try {
    const parsed = JSON.parse(raw) as unknown;
    if (!parsed || typeof parsed !== "object" || Array.isArray(parsed)) {
      return json({ error: "Couldn't read that photo. Try again." }, 400);
    }
    payload = parsed as Record<string, unknown>;
  } catch {
    return json({ error: "Couldn't read that photo. Try again." }, 400);
  }

  const taskName = payload.task;
  if (taskName !== "meal" && taskName !== "equipment") {
    return json({ error: "Couldn't read that photo. Try again." }, 400);
  }

  if (!isJpegDataURL(payload.image_data_url)) {
    return json({ error: "That photo is too large." }, 400);
  }

  try {
    const allowed = await consumePhotoCredit(sub);
    if (!allowed) {
      return json({ error: "You've used today's photo estimates. Try again tomorrow." }, 429);
    }
  } catch (error) {
    console.error("Quota check failed", error);
    return json({ error: "Photo estimates aren't available right now." }, 503);
  }

  const task = tasks[taskName as TaskName];
  const model = Netlify.env.get("OPENROUTER_VISION_MODEL") || DEFAULT_MODEL;

  const body = {
    model,
    messages: [message(task.prompt, payload.image_data_url)],
    max_tokens: 700,
    temperature: 0.2,
    stream: false,
  };

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
      body: JSON.stringify(body),
      signal: AbortSignal.timeout(50_000),
    });
  } catch (error) {
    console.error("OpenRouter request failed", error);
    return json({ error: "Couldn't read that photo. Try again." }, 502);
  }

  const upstreamText = await upstream.text();
  if (!upstream.ok) {
    console.error("OpenRouter", upstream.status, upstreamText.slice(0, 500));
    return json({ error: "Couldn't read that photo. Try again." }, 502);
  }

  return new Response(upstreamText, {
    status: 200,
    headers: { "Content-Type": "application/json" },
  });
};

export const config: Config = {
  path: "/api/vision",
  method: "POST",
};

function message(prompt: string, image: string) {
  return {
    role: "user",
    content: [
      { type: "text", text: prompt },
      { type: "image_url", image_url: { url: image } },
    ],
  };
}

function isJpegDataURL(value: unknown): value is string {
  return typeof value === "string"
    && value.length <= MAX_IMAGE_CHARS
    && /^data:image\/jpeg;base64,[A-Za-z0-9+/]+={0,2}$/.test(value);
}
