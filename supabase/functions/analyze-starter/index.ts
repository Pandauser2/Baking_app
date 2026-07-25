import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { serve } from "https://deno.land/std@0.224.0/http/server.ts";

const PROMPT_VERSION = "v1";
const MAX_IMAGE_BYTES = 8_000_000;
const MIN_IMAGE_BYTES = 8_000;
const MIN_DIMENSION = 512;

export type AnalyzeStarterRequest = {
  starter_id: string;
  image_path: string;
  prompt_version?: string;
};

export type StarterAIResponse = {
  scan_type: "starter";
  observations: string[];
  diagnosis: string[];
  confidence: number;
  next_steps: [{ instruction: string; time_window_hours: number }];
  human_explanation: string;
  risk_flags: string[];
  compare_to_previous: { changed: boolean; explanation: string };
  starter_state: string;
};

type OpenAIMessage = {
  role: "system" | "user";
  content: string | Array<Record<string, unknown>>;
};

type LoadedContext = {
  feeding_logs: unknown[];
  recent_scans: unknown[];
  recent_analyses: unknown[];
  starter_state: unknown | null;
  unresolved_recommendations: unknown[];
  recent_outcomes: unknown[];
};

type ReadContextDependencies = {
  fetchFeedingLogs: (starterId: string) => Promise<unknown[]>;
  fetchRecentScans: (starterId: string) => Promise<unknown[]>;
  fetchRecentAnalyses: (scanIds: string[]) => Promise<unknown[]>;
  fetchStarterState: (starterId: string) => Promise<unknown | null>;
  fetchUnresolvedRecommendations: (scanIds: string[]) => Promise<unknown[]>;
  fetchRecentRecommendationOutcomes: (scanIds: string[]) => Promise<unknown[]>;
};

export const ANALYZE_STARTER_WRITES_DB = false;

function jsonResponse(status: number, body: unknown): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}

function toBase64(bytes: Uint8Array): string {
  let binary = "";
  for (const byte of bytes) binary += String.fromCharCode(byte);
  return btoa(binary);
}

export function validateAuthorizationHeader(authHeader: string | null): string {
  if (!authHeader?.startsWith("Bearer ")) {
    throw new Error("Missing bearer token");
  }
  return authHeader.replace("Bearer ", "");
}

export function ensureStarterOwnedByUser(starterRecord: unknown): void {
  if (!starterRecord || typeof starterRecord !== "object") {
    throw new Error("Starter not found for user");
  }
}

function parseUUID(value: unknown, field: string): string {
  if (typeof value !== "string") throw new Error(`${field} must be a string`);
  const uuidPattern = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
  if (!uuidPattern.test(value)) throw new Error(`${field} must be a valid UUID`);
  return value.toLowerCase();
}

export function parseAnalyzeStarterRequest(input: unknown): AnalyzeStarterRequest {
  if (!input || typeof input !== "object") {
    throw new Error("Invalid request body");
  }
  const record = input as Record<string, unknown>;
  const starter_id = parseUUID(record.starter_id, "starter_id");
  const image_path = record.image_path;
  const prompt_version = record.prompt_version;

  if (typeof image_path !== "string" || image_path.length < 8) {
    throw new Error("image_path is required");
  }
  if (prompt_version !== undefined && typeof prompt_version !== "string") {
    throw new Error("prompt_version must be a string");
  }

  return {
    starter_id,
    image_path,
    prompt_version: prompt_version ?? PROMPT_VERSION,
  };
}

export function validateStoragePathOwnership(userId: string, starterId: string, path: string): boolean {
  return path.startsWith(`${userId}/${starterId}/`);
}

export function parseImageDimensions(imageBytes: Uint8Array): { width: number; height: number; mime: string } {
  if (imageBytes.length < 24) throw new Error("Image bytes too short");
  // PNG
  if (
    imageBytes[0] === 0x89 &&
    imageBytes[1] === 0x50 &&
    imageBytes[2] === 0x4e &&
    imageBytes[3] === 0x47
  ) {
    const width = (imageBytes[16] << 24) | (imageBytes[17] << 16) | (imageBytes[18] << 8) | imageBytes[19];
    const height = (imageBytes[20] << 24) | (imageBytes[21] << 16) | (imageBytes[22] << 8) | imageBytes[23];
    return { width, height, mime: "image/png" };
  }

  // JPEG
  if (imageBytes[0] === 0xff && imageBytes[1] === 0xd8) {
    let index = 2;
    while (index + 9 < imageBytes.length) {
      if (imageBytes[index] !== 0xff) {
        index += 1;
        continue;
      }
      const marker = imageBytes[index + 1];
      const length = (imageBytes[index + 2] << 8) + imageBytes[index + 3];
      if (length < 2) break;
      // SOF markers
      if (
        marker === 0xc0 ||
        marker === 0xc1 ||
        marker === 0xc2 ||
        marker === 0xc3 ||
        marker === 0xc5 ||
        marker === 0xc6 ||
        marker === 0xc7 ||
        marker === 0xc9 ||
        marker === 0xca ||
        marker === 0xcb ||
        marker === 0xcd ||
        marker === 0xce ||
        marker === 0xcf
      ) {
        const height = (imageBytes[index + 5] << 8) + imageBytes[index + 6];
        const width = (imageBytes[index + 7] << 8) + imageBytes[index + 8];
        return { width, height, mime: "image/jpeg" };
      }
      index += 2 + length;
    }
    throw new Error("Unsupported JPEG format");
  }

  throw new Error("Unsupported image format");
}

export function validateImage(imageBytes: Uint8Array): { width: number; height: number; mime: string } {
  if (imageBytes.length < MIN_IMAGE_BYTES) throw new Error("Image payload too small");
  if (imageBytes.length > MAX_IMAGE_BYTES) throw new Error("Image payload too large");
  const details = parseImageDimensions(imageBytes);
  if (details.width < MIN_DIMENSION || details.height < MIN_DIMENSION) {
    throw new Error("Image dimensions are too small");
  }
  return details;
}

function parseStringArray(value: unknown, field: string, maxLen: number): string[] {
  if (!Array.isArray(value)) throw new Error(`${field} must be an array`);
  const parsed = value
    .filter((item) => typeof item === "string")
    .map((item) => (item as string).trim())
    .filter((item) => item.length > 0);
  if (parsed.length === 0) throw new Error(`${field} must include at least one item`);
  if (parsed.length > maxLen) throw new Error(`${field} has too many items`);
  return parsed;
}

export function validateStarterAiResponse(payload: unknown): StarterAIResponse {
  if (!payload || typeof payload !== "object") {
    throw new Error("AI payload must be an object");
  }
  const root = payload as Record<string, unknown>;
  const allowedRoot = new Set([
    "scan_type",
    "observations",
    "diagnosis",
    "confidence",
    "next_steps",
    "human_explanation",
    "risk_flags",
    "compare_to_previous",
    "starter_state",
  ]);
  const incoming = new Set(Object.keys(root));
  if (incoming.size !== allowedRoot.size || [...incoming].some((key) => !allowedRoot.has(key))) {
    throw new Error("AI payload contains unknown fields");
  }

  if (root.scan_type !== "starter") throw new Error("scan_type must be starter");
  if (typeof root.confidence !== "number" || root.confidence < 0 || root.confidence > 1) {
    throw new Error("confidence must be between 0 and 1");
  }
  const observations = parseStringArray(root.observations, "observations", 3);
  const diagnosis = parseStringArray(root.diagnosis, "diagnosis", 3);

  if (!Array.isArray(root.next_steps) || root.next_steps.length !== 1) {
    throw new Error("next_steps must contain exactly one recommendation");
  }
  const firstStep = root.next_steps[0];
  if (!firstStep || typeof firstStep !== "object") throw new Error("next_steps item must be an object");
  const nextStep = firstStep as Record<string, unknown>;
  const nextStepKeys = Object.keys(nextStep);
  if (
    nextStepKeys.length !== 2 ||
    !nextStepKeys.includes("instruction") ||
    !nextStepKeys.includes("time_window_hours")
  ) {
    throw new Error("next_steps item contains unknown fields");
  }
  if (typeof nextStep.instruction !== "string" || nextStep.instruction.trim().length === 0) {
    throw new Error("next_steps.instruction is required");
  }
  if (
    typeof nextStep.time_window_hours !== "number" ||
    !Number.isInteger(nextStep.time_window_hours) ||
    nextStep.time_window_hours <= 0
  ) {
    throw new Error("next_steps.time_window_hours must be a positive integer");
  }

  if (typeof root.human_explanation !== "string" || root.human_explanation.trim().length === 0) {
    throw new Error("human_explanation is required");
  }
  const risk_flags = Array.isArray(root.risk_flags)
    ? root.risk_flags.filter((item) => typeof item === "string") as string[]
    : (() => { throw new Error("risk_flags must be an array"); })();

  const compare = root.compare_to_previous;
  if (!compare || typeof compare !== "object") throw new Error("compare_to_previous is required");
  const compareRecord = compare as Record<string, unknown>;
  const compareKeys = Object.keys(compareRecord);
  if (compareKeys.length !== 2 || !compareKeys.includes("changed") || !compareKeys.includes("explanation")) {
    throw new Error("compare_to_previous contains unknown fields");
  }
  if (typeof compareRecord.changed !== "boolean") throw new Error("compare_to_previous.changed must be boolean");
  if (typeof compareRecord.explanation !== "string" || compareRecord.explanation.trim().length === 0) {
    throw new Error("compare_to_previous.explanation is required");
  }
  if (typeof root.starter_state !== "string" || root.starter_state.trim().length === 0) {
    throw new Error("starter_state is required");
  }

  return {
    scan_type: "starter",
    observations,
    diagnosis,
    confidence: root.confidence,
    next_steps: [{
      instruction: nextStep.instruction.trim(),
      time_window_hours: nextStep.time_window_hours,
    }],
    human_explanation: root.human_explanation.trim(),
    risk_flags,
    compare_to_previous: {
      changed: compareRecord.changed,
      explanation: compareRecord.explanation.trim(),
    },
    starter_state: root.starter_state.trim(),
  };
}

export async function loadHistoryContext(starterId: string, deps: ReadContextDependencies): Promise<LoadedContext> {
  const feeding_logs = await deps.fetchFeedingLogs(starterId);
  const recent_scans = await deps.fetchRecentScans(starterId);
  const recentScanIds = recent_scans
    .map((row) => row as Record<string, unknown>)
    .map((row) => row.id)
    .filter((id): id is string => typeof id === "string");
  const recent_analyses = recentScanIds.length ? await deps.fetchRecentAnalyses(recentScanIds) : [];
  const starter_state = await deps.fetchStarterState(starterId);
  const unresolved_recommendations = recentScanIds.length ? await deps.fetchUnresolvedRecommendations(recentScanIds) : [];
  const recent_outcomes = recentScanIds.length ? await deps.fetchRecentRecommendationOutcomes(recentScanIds) : [];

  return {
    feeding_logs,
    recent_scans,
    recent_analyses,
    starter_state,
    unresolved_recommendations,
    recent_outcomes,
  };
}

function buildSystemPrompt(context: LoadedContext): string {
  return [
    "You are a cautious sourdough starter assistant.",
    "Return JSON only with strict schema and no extra fields.",
    "Do not claim hidden variables as facts.",
    "Separate observations from inference.",
    "Use visible evidence from the image and context.",
    `Context: ${JSON.stringify(context)}`,
    "Schema:",
    "{",
    '  "scan_type":"starter",',
    '  "observations":["short visible fact"],',
    '  "diagnosis":["state label"],',
    '  "confidence":0.0,',
    '  "next_steps":[{"instruction":"actionable recommendation","time_window_hours":12}],',
    '  "human_explanation":"concise explanation",',
    '  "risk_flags":[],',
    '  "compare_to_previous":{"changed":true,"explanation":"what visibly changed"},',
    '  "starter_state":"active"',
    "}",
    "Rules:",
    "- maximum 3 observations",
    "- exactly 1 next_steps item",
    "- confidence between 0.0 and 1.0",
    "- actionable next step",
  ].join("\n");
}

export async function callOpenAIWithRetry(
  apiKey: string,
  model: string,
  imageBytes: Uint8Array,
  context: LoadedContext,
  fetchFn: typeof fetch = fetch,
): Promise<StarterAIResponse> {
  const base64 = toBase64(imageBytes);
  const messages: OpenAIMessage[] = [
    { role: "system", content: buildSystemPrompt(context) },
    {
      role: "user",
      content: [
        { type: "text", text: "Analyze this starter image with the strict schema." },
        { type: "image_url", image_url: { url: `data:image/jpeg;base64,${base64}` } },
      ],
    },
  ];

  async function requestOpenAI(extraUserInstruction?: string): Promise<string> {
    const extraMessages = [...messages];
    if (extraUserInstruction) {
      extraMessages.push({ role: "user", content: extraUserInstruction });
    }
    const response = await fetchFn("https://api.openai.com/v1/chat/completions", {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        Authorization: `Bearer ${apiKey}`,
      },
      body: JSON.stringify({
        model,
        temperature: 0.2,
        response_format: { type: "json_object" },
        messages: extraMessages,
      }),
    });

    if (!response.ok) {
      if (response.status >= 500 && response.status <= 599) {
        throw new Error("provider_5xx");
      }
      throw new Error(`provider_${response.status}`);
    }
    const payload = await response.json();
    const content = payload?.choices?.[0]?.message?.content;
    if (typeof content !== "string") throw new Error("empty_provider_content");
    return content;
  }

  let rawContent = "";
  for (let attempt = 0; attempt < 2; attempt++) {
    try {
      rawContent = await requestOpenAI();
      break;
    } catch (error) {
      const message = error instanceof Error ? error.message : "";
      if (attempt === 0 && (message === "provider_5xx" || message.includes("timeout"))) {
        continue;
      }
      throw error;
    }
  }

  try {
    return validateStarterAiResponse(JSON.parse(rawContent));
  } catch {
    const repaired = await requestOpenAI(
      "Your previous response was invalid JSON for the required schema. Return corrected JSON only.",
    );
    return validateStarterAiResponse(JSON.parse(repaired));
  }
}

const handler = async (req: Request) => {
  if (req.method === "OPTIONS") return new Response("ok");
  if (req.method !== "POST") return jsonResponse(405, { error: "Method not allowed" });

  try {
    const supabaseUrl = Deno.env.get("SUPABASE_URL");
    const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
    const openAIKey = Deno.env.get("OPENAI_API_KEY");
    const openAIModel = Deno.env.get("OPENAI_MODEL") ?? "gpt-4o-mini";
    const authHeader = req.headers.get("Authorization");

    if (!supabaseUrl || !serviceRoleKey || !openAIKey) {
      return jsonResponse(500, { error: "Function is not configured" });
    }
    try {
      validateAuthorizationHeader(authHeader);
    } catch {
      return jsonResponse(401, { error: "Missing bearer token" });
    }

    const supabase = createClient(supabaseUrl, serviceRoleKey);
    const jwt = validateAuthorizationHeader(authHeader);
    const { data: authData, error: authError } = await supabase.auth.getUser(jwt);
    if (authError || !authData.user) {
      return jsonResponse(401, { error: "Invalid auth token" });
    }
    const userId = authData.user.id;

    const body = parseAnalyzeStarterRequest(await req.json());
    if (!validateStoragePathOwnership(userId, body.starter_id, body.image_path)) {
      return jsonResponse(403, { error: "Image path is outside user starter prefix" });
    }

    const { data: starter, error: starterError } = await supabase
      .from("starters")
      .select("id")
      .eq("id", body.starter_id)
      .eq("user_id", userId)
      .single();
    if (starterError || !starter) {
      return jsonResponse(404, { error: "Starter not found for user" });
    }
    ensureStarterOwnedByUser(starter);

    const { data: imageBlob, error: imageError } = await supabase.storage
      .from("starter-images")
      .download(body.image_path);
    if (imageError || !imageBlob) {
      return jsonResponse(400, { error: "Could not download image" });
    }
    const imageBytes = new Uint8Array(await imageBlob.arrayBuffer());
    validateImage(imageBytes);

    const context = await loadHistoryContext(body.starter_id, {
      fetchFeedingLogs: async (starterId) => {
        const { data } = await supabase
          .from("feeding_logs")
          .select("logged_at, room_temp_c, flour_g, water_g, starter_g, notes")
          .eq("starter_id", starterId)
          .eq("user_id", userId)
          .order("logged_at", { ascending: false })
          .limit(3);
        return data ?? [];
      },
      fetchRecentScans: async (starterId) => {
        const { data } = await supabase
          .from("scans")
          .select("id, created_at, quality_score, quality_issue, status")
          .eq("starter_id", starterId)
          .eq("user_id", userId)
          .eq("scan_type", "starter")
          .order("created_at", { ascending: false })
          .limit(2);
        return data ?? [];
      },
      fetchRecentAnalyses: async (scanIds) => {
        const { data } = await supabase
          .from("ai_analyses")
          .select("scan_id, confidence, rendered_explanation, analysis_json, created_at")
          .in("scan_id", scanIds)
          .eq("user_id", userId)
          .order("created_at", { ascending: false });
        return data ?? [];
      },
      fetchStarterState: async (starterId) => {
        const { data } = await supabase
          .from("starter_states")
          .select("state_label, updated_at")
          .eq("starter_id", starterId)
          .eq("user_id", userId)
          .maybeSingle();
        return data ?? null;
      },
      fetchUnresolvedRecommendations: async (scanIds) => {
        const { data } = await supabase
          .from("recommendations")
          .select("recommendation, due_at, outcome")
          .in("scan_id", scanIds)
          .eq("user_id", userId)
          .eq("outcome", "unknown")
          .order("created_at", { ascending: false });
        return data ?? [];
      },
      fetchRecentRecommendationOutcomes: async (scanIds) => {
        const { data } = await supabase
          .from("recommendations")
          .select("recommendation, outcome, completed_at")
          .in("scan_id", scanIds)
          .eq("user_id", userId)
          .neq("outcome", "unknown")
          .order("created_at", { ascending: false })
          .limit(5);
        return data ?? [];
      },
    });

    const validated = await callOpenAIWithRetry(openAIKey, openAIModel, imageBytes, context);
    return jsonResponse(200, {
      prompt_version: body.prompt_version ?? PROMPT_VERSION,
      model: openAIModel,
      analysis: validated,
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

