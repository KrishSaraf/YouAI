import type { Config } from "@netlify/functions";
import { authorize } from "./_shared/auth";
import { consumePhotoCredit } from "./_shared/accounts";
import { json } from "./_shared/http";

const NVIDIA_URL = "https://integrate.api.nvidia.com/v1/chat/completions";
const DEFAULT_MODEL = "meta/llama-3.2-90b-vision-instruct";

// Photos are compressed under ~170 KB of base64 before they leave the phone.
const MAX_BODY_CHARS = 400_000;
const MAX_IMAGE_CHARS = 180_000;

const tasks = {
  meal: {
    prompt: [
      "You are a nutrition estimator. Look at this photo of a meal and estimate its contents for a single serving as shown.",
      "",
      "Reply with only a JSON object, no prose and no code fences, with these keys:",
      '  "name": a short dish name, at most 5 words',
      '  "meal_type": one of breakfast, lunch, dinner, snack',
      '  "calories": total kilocalories, a number',
      '  "protein_g", "carbs_g", "fat_g": grams, numbers',
      '  "note": one short sentence on what you assumed about portion size',
      "",
      'If the photo does not contain food, set "name" to "No food detected" and all numbers to 0.',
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
      "You are a strength-training coach. Identify the piece of gym equipment in this photo and list the exercises it is used for.",
      "",
      "Reply with only a JSON object, no prose and no code fences, with these keys:",
      '  "equipment_name": what the machine or equipment is called',
      '  "suggested_exercises": up to 5 exercise names you\'d perform on it, most common first, each named the way a lifter would log it',
      '  "note": one short sentence of setup advice',
      "",
      'If there is no gym equipment in the photo, set "equipment_name" to "No equipment detected" and "suggested_exercises" to an empty array.',
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

  const apiKey = Netlify.env.get("NVIDIA_API_KEY");
  if (!apiKey) {
    console.error("NVIDIA_API_KEY is not set");
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
  const model = Netlify.env.get("NVIDIA_VISION_MODEL") || DEFAULT_MODEL;
  const encoding = Netlify.env.get("NVIDIA_IMAGE_ENCODING") === "inlineHTMLTag"
    ? "inlineHTMLTag"
    : "openAIImageURL";

  const body = {
    model,
    messages: [message(task.prompt, payload.image_data_url, encoding)],
    max_tokens: 700,
    temperature: 0.2,
    stream: false,
    response_format: {
      type: "json_schema",
      json_schema: { name: "response", strict: true, schema: task.schema },
    },
  };

  let upstream: Response;
  try {
    upstream = await fetch(NVIDIA_URL, {
      method: "POST",
      headers: {
        Authorization: `Bearer ${apiKey}`,
        "Content-Type": "application/json",
        Accept: "application/json",
      },
      body: JSON.stringify(body),
      signal: AbortSignal.timeout(50_000),
    });
  } catch (error) {
    console.error("NVIDIA request failed", error);
    return json({ error: "Couldn't read that photo. Try again." }, 502);
  }

  const upstreamText = await upstream.text();
  if (!upstream.ok) {
    console.error("NVIDIA API", upstream.status, upstreamText.slice(0, 500));
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

function message(prompt: string, image: string, encoding: string) {
  if (encoding === "inlineHTMLTag") {
    return { role: "user", content: `${prompt} <img src="${image}" />` };
  }

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
