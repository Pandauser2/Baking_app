import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { serve } from "https://deno.land/std@0.224.0/http/server.ts";

type AnalyzeRequest = {
  image_path: string;
  prompt_version?: string;
};

export type AiPayload = {
  crumb_score: number;
  crust_score: number;
  oven_spring_score: number;
  overall_score: number;
  strengths: string[];
  improvements: string[];
  next_steps: string[];
  summary: string;
};

const PROMPT_VERSION = "v1";
const MODEL = "gpt-4o-mini";

function jsonResponse(status: number, body: unknown): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}

function toBase64(bytes: Uint8Array): string {
  let binary = "";
  for (const byte of bytes) {
    binary += String.fromCharCode(byte);
  }
  return btoa(binary);
}

function parseAnalyzeRequest(input: unknown): AnalyzeRequest {
  if (!input || typeof input !== "object") {
    throw new Error("Invalid request body");
  }
  const record = input as Record<string, unknown>;
  const imagePath = record.image_path;
  const promptVersion = record.prompt_version;
  if (typeof imagePath !== "string" || imagePath.length < 8) {
    throw new Error("image_path is required");
  }
  if (promptVersion !== undefined && typeof promptVersion !== "string") {
    throw new Error("prompt_version must be a string");
  }
  return {
    image_path: imagePath,
    prompt_version: promptVersion ?? PROMPT_VERSION,
  };
}

function asScore(value: unknown): number {
  if (typeof value !== "number" || !Number.isInteger(value) || value < 0 || value > 100) {
    throw new Error("Invalid score");
  }
  return value;
}

function asStringArray(value: unknown, field: string): string[] {
  if (!Array.isArray(value)) throw new Error(`Invalid ${field}`);
  const parsed = value.filter((item) => typeof item === "string" && item.trim().length > 0) as string[];
  if (parsed.length === 0) throw new Error(`${field} must include at least one item`);
  return parsed.slice(0, 6);
}

export function validateAiPayload(payload: unknown): AiPayload {
  if (!payload || typeof payload !== "object") {
    throw new Error("AI response is not an object");
  }

  const record = payload as Record<string, unknown>;
  if (typeof record.summary !== "string" || record.summary.trim().length == 0) {
    throw new Error("summary is required");
  }

  return {
    crumb_score: asScore(record.crumb_score),
    crust_score: asScore(record.crust_score),
    oven_spring_score: asScore(record.oven_spring_score),
    overall_score: asScore(record.overall_score),
    strengths: asStringArray(record.strengths, "strengths"),
    improvements: asStringArray(record.improvements, "improvements"),
    next_steps: asStringArray(record.next_steps, "next_steps"),
    summary: record.summary.trim(),
  };
}

/** Source marker used by tests: this module must never write analysis rows. */
export const PERFORMS_DB_WRITES = false as const;

function buildPrompt(): string {
  return [
    "You are a sourdough loaf evaluator.",
    "Return JSON only, no markdown.",
    "Use exactly these fields:",
    "{",
    '  "crumb_score":0,',
    '  "crust_score":0,',
    '  "oven_spring_score":0,',
    '  "overall_score":0,',
    '  "strengths":[""],',
    '  "improvements":[""],',
    '  "next_steps":[""],',
    '  "summary":""',
    "}",
    "All score fields are integers from 0 to 100.",
    "summary must be a non-empty string (1-3 sentences).",
    "strengths, improvements, and next_steps must each include at least one non-empty string.",
    "If the image is unclear, still return best-effort scores and a short summary.",
    "Do not include any extra fields.",
  ].join("\n");
}

async function callOpenAI(imageBytes: Uint8Array, apiKey: string): Promise<AiPayload> {
  const imageBase64 = toBase64(imageBytes);
  const response = await fetch("https://api.openai.com/v1/chat/completions", {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      Authorization: `Bearer ${apiKey}`,
    },
    body: JSON.stringify({
      model: MODEL,
      temperature: 0.2,
      response_format: { type: "json_object" },
      messages: [
        {
          role: "system",
          content: buildPrompt(),
        },
        {
          role: "user",
          content: [
            {
              type: "text",
              text: "Analyze this sourdough loaf image and return strict JSON.",
            },
            {
              type: "image_url",
              image_url: {
                url: `data:image/jpeg;base64,${imageBase64}`,
              },
            },
          ],
        },
      ],
    }),
  });

  if (!response.ok) {
    const body = await response.text();
    throw new Error(`OpenAI request failed: ${body}`);
  }

  const parsed = await response.json();
  const content = parsed?.choices?.[0]?.message?.content;
  if (typeof content !== "string") {
    throw new Error("OpenAI returned empty content");
  }

  let payload: unknown;
  try {
    payload = JSON.parse(content);
  } catch {
    throw new Error("OpenAI returned malformed JSON");
  }

  return validateAiPayload(payload);
}

const handler = async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response("ok");
  }
  if (req.method !== "POST") {
    return jsonResponse(405, { error: "Method not allowed" });
  }

  try {
    const supabaseUrl = Deno.env.get("SUPABASE_URL");
    const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
    const openAIKey = Deno.env.get("OPENAI_API_KEY");
    const authHeader = req.headers.get("Authorization");

    if (!supabaseUrl || !serviceRoleKey || !openAIKey) {
      return jsonResponse(500, { error: "Function is not configured" });
    }
    if (!authHeader?.startsWith("Bearer ")) {
      return jsonResponse(401, { error: "Missing bearer token" });
    }

    // Service role is used only for auth verification + storage download.
    // This function must not insert/update/delete analysis rows.
    const supabase = createClient(supabaseUrl, serviceRoleKey);
    const jwt = authHeader.replace("Bearer ", "");
    const { data: userData, error: userError } = await supabase.auth.getUser(jwt);
    if (userError || !userData.user) {
      return jsonResponse(401, { error: "Invalid auth token" });
    }

    const body = parseAnalyzeRequest(await req.json());
    const userId = userData.user.id;
    if (!body.image_path.startsWith(`${userId}/`)) {
      return jsonResponse(403, { error: "Invalid image path for user" });
    }

    const { data: imageBlob, error: downloadError } = await supabase
      .storage
      .from("loaf-images")
      .download(body.image_path);
    if (downloadError || !imageBlob) {
      return jsonResponse(400, { error: "Could not download image" });
    }

    const imageBytes = new Uint8Array(await imageBlob.arrayBuffer());
    if (imageBytes.length < 8_000) {
      return jsonResponse(400, { error: "Image payload too small" });
    }
    if (imageBytes.length > 8_000_000) {
      return jsonResponse(400, { error: "Image payload too large" });
    }

    const analysis = await callOpenAI(imageBytes, openAIKey);
    return jsonResponse(200, {
      model: MODEL,
      prompt_version: body.prompt_version ?? PROMPT_VERSION,
      analysis,
    });
  } catch (error) {
    return jsonResponse(400, {
      error: error instanceof Error ? error.message : "Unexpected error",
    });
  }
};

if (import.meta.main) {
  serve(handler);
}
