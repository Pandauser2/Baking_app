import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { serve } from "https://deno.land/std@0.224.0/http/server.ts";

export type ComparisonMode = "baseline" | "processComparison" | "fullComparison";

type ProcessSnapshot = {
  dough_hydration_percent: number;
  bulk_fermentation_minutes: number;
  final_proof_minutes: number;
  fermentation_temperature_c: number | null;
  oven_temperature_c: number;
  baking_time_minutes: number;
};

type ScoreSnapshot = {
  crumb_score: number;
  crust_score: number;
  oven_spring_score: number;
  overall_score: number;
};

type AnalyzeContext = {
  comparison_mode: ComparisonMode;
  current_process: ProcessSnapshot;
  previous_bake_id?: string | null;
  previous_bake_name?: string | null;
  starter_changed?: boolean;
  previous_process?: ProcessSnapshot | null;
  previous_scores?: ScoreSnapshot | null;
};

type AnalyzeRequest = {
  image_path: string;
  prompt_version?: string;
  context?: AnalyzeContext | null;
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
  why: string;
};

const PROMPT_VERSION = "v1";
const MODEL = "gpt-4o-mini";

/** Source marker used by tests: this module must never write analysis rows. */
export const PERFORMS_DB_WRITES = false as const;

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

function asFiniteNumber(value: unknown, field: string): number {
  if (typeof value !== "number" || !Number.isFinite(value)) {
    throw new Error(`Invalid ${field}`);
  }
  return value;
}

function parseProcessSnapshot(input: unknown, label: string): ProcessSnapshot {
  if (!input || typeof input !== "object") {
    throw new Error(`${label} is required`);
  }
  const record = input as Record<string, unknown>;
  const fermentation = record.fermentation_temperature_c;
  return {
    dough_hydration_percent: asFiniteNumber(record.dough_hydration_percent, "dough_hydration_percent"),
    bulk_fermentation_minutes: asFiniteNumber(record.bulk_fermentation_minutes, "bulk_fermentation_minutes"),
    final_proof_minutes: asFiniteNumber(record.final_proof_minutes, "final_proof_minutes"),
    fermentation_temperature_c:
      fermentation === null || fermentation === undefined
        ? null
        : asFiniteNumber(fermentation, "fermentation_temperature_c"),
    oven_temperature_c: asFiniteNumber(record.oven_temperature_c, "oven_temperature_c"),
    baking_time_minutes: asFiniteNumber(record.baking_time_minutes, "baking_time_minutes"),
  };
}

function parseScoreSnapshot(input: unknown): ScoreSnapshot {
  if (!input || typeof input !== "object") {
    throw new Error("previous_scores is invalid");
  }
  const record = input as Record<string, unknown>;
  return {
    crumb_score: asScore(record.crumb_score),
    crust_score: asScore(record.crust_score),
    oven_spring_score: asScore(record.oven_spring_score),
    overall_score: asScore(record.overall_score),
  };
}

function parseContext(input: unknown): AnalyzeContext | null {
  if (input === undefined || input === null) return null;
  if (typeof input !== "object") throw new Error("context must be an object");
  const record = input as Record<string, unknown>;
  const mode = record.comparison_mode;
  if (mode !== "baseline" && mode !== "processComparison" && mode !== "fullComparison") {
    throw new Error("comparison_mode is required");
  }
  const currentProcess = parseProcessSnapshot(record.current_process, "current_process");
  let previousProcess: ProcessSnapshot | null = null;
  if (record.previous_process !== undefined && record.previous_process !== null) {
    previousProcess = parseProcessSnapshot(record.previous_process, "previous_process");
  }
  let previousScores: ScoreSnapshot | null = null;
  if (record.previous_scores !== undefined && record.previous_scores !== null) {
    previousScores = parseScoreSnapshot(record.previous_scores);
  }
  if (mode === "processComparison" || mode === "fullComparison") {
    if (!previousProcess) throw new Error("previous_process is required for comparison modes");
  }
  if (mode === "fullComparison" && !previousScores) {
    throw new Error("previous_scores is required for fullComparison");
  }
  return {
    comparison_mode: mode,
    current_process: currentProcess,
    previous_bake_id: typeof record.previous_bake_id === "string" ? record.previous_bake_id : null,
    previous_bake_name: typeof record.previous_bake_name === "string" ? record.previous_bake_name : null,
    starter_changed: Boolean(record.starter_changed),
    previous_process: previousProcess,
    previous_scores: previousScores,
  };
}

export function parseAnalyzeRequest(input: unknown): AnalyzeRequest {
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
    context: parseContext(record.context),
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
  if (typeof record.summary !== "string" || record.summary.trim().length === 0) {
    throw new Error("summary is required");
  }
  if (typeof record.why !== "string" || record.why.trim().length === 0) {
    throw new Error("why is required");
  }
  const nextSteps = asStringArray(record.next_steps, "next_steps");
  if (nextSteps.length !== 1) {
    throw new Error("next_steps must contain exactly one recommendation");
  }

  return {
    crumb_score: asScore(record.crumb_score),
    crust_score: asScore(record.crust_score),
    oven_spring_score: asScore(record.oven_spring_score),
    overall_score: asScore(record.overall_score),
    strengths: asStringArray(record.strengths, "strengths"),
    improvements: asStringArray(record.improvements, "improvements"),
    next_steps: nextSteps,
    summary: record.summary.trim(),
    why: record.why.trim(),
  };
}

function buildPrompt(context: AnalyzeContext | null | undefined): string {
  const mode = context?.comparison_mode ?? "baseline";
  const lines = [
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
    '  "summary":"",',
    '  "why":""',
    "}",
    "All score fields are integers from 0 to 100.",
    "summary must be a non-empty overall assessment of the CURRENT loaf (1-3 sentences).",
    "strengths and improvements must each include at least one non-empty string.",
    "next_steps must contain exactly ONE actionable next-bake recommendation.",
    "why must explain likely reasons using only supplied process/score context; never invent missing process values.",
    "Do NOT classify score deltas as improved/regressed/unchanged — the app does that deterministically.",
    "Do not include any extra fields.",
    `Comparison mode: ${mode}.`,
  ];
  if (mode === "baseline") {
    lines.push(
      "This is a baseline loaf. In why, briefly note that this establishes a baseline for future comparisons.",
      "Never say 'No previous data to compare.'",
    );
  } else if (mode === "processComparison") {
    lines.push(
      "Previous bake process context is provided, but no previous loaf visual scores.",
      "Explain process differences only; note that visual comparison is unavailable.",
    );
  } else {
    lines.push(
      "Previous bake process and loaf scores are provided.",
      "Explain likely reasons for differences using supplied numbers only.",
    );
  }
  if (context?.starter_changed) {
    lines.push("Note that the previous bake used a different starter.");
  }
  return lines.join("\n");
}

function userContextText(context: AnalyzeContext | null | undefined): string {
  if (!context) {
    return "Analyze this sourdough loaf image and return strict JSON.";
  }
  return [
    "Analyze this sourdough loaf image and return strict JSON.",
    "Supplied comparison context (do not invent missing values):",
    JSON.stringify(context),
  ].join("\n");
}

async function callOpenAI(
  imageBytes: Uint8Array,
  apiKey: string,
  context: AnalyzeContext | null | undefined,
): Promise<AiPayload> {
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
          content: buildPrompt(context),
        },
        {
          role: "user",
          content: [
            {
              type: "text",
              text: userContextText(context),
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

    const analysis = await callOpenAI(imageBytes, openAIKey, body.context);
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
