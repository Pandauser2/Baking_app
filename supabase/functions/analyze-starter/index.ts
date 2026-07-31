import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { serve } from "https://deno.land/std@0.224.0/http/server.ts";

const PROMPT_VERSION = "v2";
const MAX_IMAGE_BYTES = 8_000_000;
const MIN_IMAGE_BYTES = 8_000;
const MIN_DIMENSION = 512;
const OPENAI_TIMEOUT_MS = 20_000;
const NO_PREVIOUS_COMPARISON_EXPLANATION = "No previous data to compare.";

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

export type InvalidSubjectReason = "not_starter" | "uncertain";

export type InvalidSubjectOutcome = {
  result_type: "invalid_subject";
  reason: InvalidSubjectReason;
  message: string;
};

export type StarterAnalysisOutcome = {
  result_type: "starter_analysis";
  analysis: StarterAIResponse;
};

export type AnalyzeStarterOutcome = InvalidSubjectOutcome | StarterAnalysisOutcome;

export type AnalyzeStarterErrorCode =
  | "AUTH_INVALID"
  | "STARTER_NOT_FOUND"
  | "IMAGE_DOWNLOAD_FAILED"
  | "IMAGE_INVALID"
  | "PROVIDER_AUTH"
  | "PROVIDER_QUOTA"
  | "PROVIDER_RATE_LIMIT"
  | "PROVIDER_TIMEOUT"
  | "PROVIDER_RESPONSE_INVALID"
  | "INTERNAL_ERROR";

export type AnalyzeStarterErrorResponse = {
  error_code: AnalyzeStarterErrorCode;
  message: string;
  request_id: string;
};

const INVALID_SUBJECT_MESSAGES: Record<InvalidSubjectReason, string> = {
  not_starter: "This doesn’t appear to be a sourdough starter. Please choose another photo.",
  uncertain: "We’re not sure this is a sourdough starter. Please choose another photo.",
};

type OpenAIMessage = {
  role: "system" | "user";
  content: string | Array<Record<string, unknown>>;
};

export type SanitizedPreviousAnalysis = {
  scan_id: string;
  created_at: string;
  starter_state: string | null;
  confidence: number | null;
  rendered_explanation: string | null;
  recommendation_outcome: string | null;
};

export type LoadedContext = {
  has_previous_analysis: boolean;
  previous_analysis: SanitizedPreviousAnalysis | null;
  feeding_logs: unknown[];
  starter_state: unknown | null;
  recent_outcomes: unknown[];
};

type ReadContextDependencies = {
  fetchFeedingLogs: (starterId: string) => Promise<unknown[]>;
  fetchRecentCompletedScans: (starterId: string, currentImagePath: string) => Promise<unknown[]>;
  fetchRecentAnalyses: (scanIds: string[]) => Promise<unknown[]>;
  fetchStarterState: (starterId: string) => Promise<unknown | null>;
  fetchRecentRecommendationOutcomes: (scanIds: string[]) => Promise<unknown[]>;
};

export const ANALYZE_STARTER_WRITES_DB = false;

function jsonResponse(status: number, body: unknown): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}

function errorResponse(
  status: number,
  errorCode: AnalyzeStarterErrorCode,
  message: string,
  requestID: string,
): Response {
  console.error(JSON.stringify({
    request_id: requestID,
    status,
    error_code: errorCode,
  }));
  return jsonResponse(status, {
    error_code: errorCode,
    message,
    request_id: requestID,
  } satisfies AnalyzeStarterErrorResponse);
}

class AnalyzeStarterError extends Error {
  code: AnalyzeStarterErrorCode;
  status: number;

  constructor(code: AnalyzeStarterErrorCode, status: number, message: string) {
    super(message);
    this.code = code;
    this.status = status;
  }
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

type ProviderErrorDetails = {
  code?: string;
  message?: string;
};

function extractProviderError(payload: unknown): ProviderErrorDetails {
  if (!payload || typeof payload !== "object") return {};
  const errorObject = (payload as { error?: unknown }).error;
  if (!errorObject || typeof errorObject !== "object") return {};
  const record = errorObject as Record<string, unknown>;
  return {
    code: typeof record.code === "string" ? record.code : undefined,
    message: typeof record.message === "string" ? record.message : undefined,
  };
}

function classifyProviderError(status: number, details: ProviderErrorDetails): AnalyzeStarterError {
  if (status === 401 || status === 403) {
    return new AnalyzeStarterError(
      "PROVIDER_AUTH",
      400,
      "The analysis provider rejected authentication.",
    );
  }
  if (status === 429) {
    const errorCode = (details.code ?? "").toLowerCase();
    if (errorCode.includes("quota") || errorCode.includes("insufficient_quota")) {
      return new AnalyzeStarterError(
        "PROVIDER_QUOTA",
        429,
        "Analysis provider quota is currently exhausted.",
      );
    }
    return new AnalyzeStarterError(
      "PROVIDER_RATE_LIMIT",
      429,
      "Analysis provider rate limit reached. Please retry shortly.",
    );
  }
  if (status >= 500) {
    return new AnalyzeStarterError(
      "PROVIDER_TIMEOUT",
      408,
      "The analysis provider timed out.",
    );
  }
  return new AnalyzeStarterError(
    "PROVIDER_RESPONSE_INVALID",
    400,
    "The analysis provider returned an invalid response.",
  );
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

export function validateAnalyzeStarterOutcome(payload: unknown): AnalyzeStarterOutcome {
  if (!payload || typeof payload !== "object") {
    throw new Error("AI payload must be an object");
  }
  const root = payload as Record<string, unknown>;
  if (root.result_type === "starter_analysis") {
    const keys = Object.keys(root);
    if (keys.length !== 2 || !keys.includes("result_type") || !keys.includes("analysis")) {
      throw new Error("starter_analysis payload contains unknown fields");
    }
    return {
      result_type: "starter_analysis",
      analysis: validateStarterAiResponse(root.analysis),
    };
  }
  if (root.result_type === "invalid_subject") {
    const keys = Object.keys(root);
    if (keys.length !== 3 || !keys.includes("result_type") || !keys.includes("reason") || !keys.includes("message")) {
      throw new Error("invalid_subject payload contains unknown fields");
    }
    const reason = root.reason;
    if (reason !== "not_starter" && reason !== "uncertain") {
      throw new Error("invalid_subject reason is invalid");
    }
    if (typeof root.message !== "string" || root.message.trim().length === 0) {
      throw new Error("invalid_subject message is required");
    }
    return {
      result_type: "invalid_subject",
      reason,
      message: root.message.trim(),
    };
  }
  throw new Error("AI payload result_type is invalid");
}

export function claimsNoPreviousData(explanation: string): boolean {
  const normalized = explanation.trim().toLowerCase();
  return (
    normalized.includes("no previous data") ||
    normalized.includes("no previous scan") ||
    normalized.includes("nothing to compare") ||
    normalized.includes("no prior")
  );
}

export function enforceComparisonConsistency(
  analysis: StarterAIResponse,
  hasPrevious: boolean,
): StarterAIResponse {
  if (!hasPrevious) {
    return {
      ...analysis,
      compare_to_previous: {
        changed: false,
        explanation: NO_PREVIOUS_COMPARISON_EXPLANATION,
      },
    };
  }
  if (claimsNoPreviousData(analysis.compare_to_previous.explanation)) {
    throw new Error(
      "compare_to_previous incorrectly claims no previous data when previous analysis exists",
    );
  }
  return analysis;
}

export function sanitizeModelContext(context: LoadedContext): Record<string, unknown> {
  return {
    has_previous_analysis: context.has_previous_analysis,
    previous_analysis: context.previous_analysis
      ? {
        scan_id: context.previous_analysis.scan_id,
        created_at: context.previous_analysis.created_at,
        starter_state: context.previous_analysis.starter_state,
        confidence: context.previous_analysis.confidence,
        rendered_explanation: context.previous_analysis.rendered_explanation,
        recommendation_outcome: context.previous_analysis.recommendation_outcome,
      }
      : null,
    feeding_logs: context.feeding_logs,
    starter_state: context.starter_state,
    recent_outcomes: context.recent_outcomes,
  };
}

function extractStarterStateFromAnalysis(analysisJson: unknown): string | null {
  if (!analysisJson || typeof analysisJson !== "object") return null;
  const state = (analysisJson as Record<string, unknown>).starter_state;
  return typeof state === "string" && state.trim().length > 0 ? state.trim() : null;
}

export async function loadHistoryContext(
  starterId: string,
  currentImagePath: string,
  deps: ReadContextDependencies,
): Promise<LoadedContext> {
  const feeding_logs = await deps.fetchFeedingLogs(starterId);
  const priorScans = await deps.fetchRecentCompletedScans(starterId, currentImagePath);
  const priorScanIds = priorScans
    .map((row) => row as Record<string, unknown>)
    .map((row) => row.id)
    .filter((id): id is string => typeof id === "string");
  const analyses = priorScanIds.length ? await deps.fetchRecentAnalyses(priorScanIds) : [];
  const analysisByScan = new Map<string, Record<string, unknown>>();
  for (const row of analyses) {
    const record = row as Record<string, unknown>;
    if (typeof record.scan_id === "string" && !analysisByScan.has(record.scan_id)) {
      analysisByScan.set(record.scan_id, record);
    }
  }

  let previous: SanitizedPreviousAnalysis | null = null;
  for (const scan of priorScans) {
    const scanRecord = scan as Record<string, unknown>;
    const scanId = scanRecord.id;
    if (typeof scanId !== "string") continue;
    // Current in-progress image must never count as previous.
    if (typeof scanRecord.storage_path === "string" && scanRecord.storage_path === currentImagePath) {
      continue;
    }
    // Only completed analyzed scans participate; invalid-subject never creates scan rows.
    if (scanRecord.status !== undefined && scanRecord.status !== "analyzed") {
      continue;
    }
    const analysis = analysisByScan.get(scanId);
    if (!analysis) {
      // Missing nested analysis: skip this scan and try the next older completed scan.
      continue;
    }
    previous = {
      scan_id: scanId,
      created_at: typeof scanRecord.created_at === "string"
        ? scanRecord.created_at
        : (typeof analysis.created_at === "string" ? analysis.created_at : ""),
      starter_state: extractStarterStateFromAnalysis(analysis.analysis_json),
      confidence: typeof analysis.confidence === "number" ? analysis.confidence : null,
      rendered_explanation: typeof analysis.rendered_explanation === "string"
        ? analysis.rendered_explanation
        : null,
      recommendation_outcome: null,
    };
    break;
  }

  const outcomeScanIds = previous ? [previous.scan_id] : [];
  const recent_outcomes = outcomeScanIds.length
    ? await deps.fetchRecentRecommendationOutcomes(outcomeScanIds)
    : [];
  if (previous && recent_outcomes.length > 0) {
    const firstOutcome = recent_outcomes[0] as Record<string, unknown>;
    if (typeof firstOutcome.outcome === "string") {
      previous = {
        ...previous,
        recommendation_outcome: firstOutcome.outcome,
      };
    }
  }

  const starter_state = await deps.fetchStarterState(starterId);
  return {
    has_previous_analysis: previous !== null,
    previous_analysis: previous,
    feeding_logs,
    starter_state,
    recent_outcomes,
  };
}

export function buildSystemPrompt(context: LoadedContext): string {
  const sanitized = sanitizeModelContext(context);
  return [
    "You are a cautious sourdough starter assistant.",
    "Return JSON only with strict schema and no extra fields.",
    "Do not claim hidden variables as facts.",
    "Separate observations from inference.",
    "Use visible evidence from the current image plus the textual history context.",
    "You are given only the current image. Do not invent pixel-level visual differences from a prior photo.",
    `Context: ${JSON.stringify(sanitized)}`,
    "Schema option 1 (valid starter):",
    "{",
    '  "result_type":"starter_analysis",',
    '  "analysis":{',
    '    "scan_type":"starter",',
    '    "observations":["short visible fact"],',
    '    "diagnosis":["state label"],',
    '    "confidence":0.0,',
    '    "next_steps":[{"instruction":"actionable recommendation","time_window_hours":12}],',
    '    "human_explanation":"concise explanation",',
    '    "risk_flags":[],',
    '    "compare_to_previous":{"changed":true,"explanation":"how this differs from previous_analysis textual state"},',
    '    "starter_state":"active"',
    "  }",
    "}",
    "Schema option 2 (not a starter or uncertain subject):",
    "{",
    '  "result_type":"invalid_subject",',
    '  "reason":"not_starter",',
    '  "message":"This doesn’t appear to be a sourdough starter. Please choose another photo."',
    "}",
    "Rules:",
    "- If the photo is clearly not a sourdough starter, return invalid_subject with reason not_starter",
    "- If the subject is uncertain or ambiguous, return invalid_subject with reason uncertain",
    "- Never force a starter analysis when subject is not a sourdough starter",
    "- maximum 3 observations",
    "- exactly 1 next_steps item",
    "- confidence between 0.0 and 1.0",
    "- actionable next step",
    `- If has_previous_analysis is false, compare_to_previous MUST be {"changed":false,"explanation":"${NO_PREVIOUS_COMPARISON_EXPLANATION}"}`,
    "- If has_previous_analysis is true, compare_to_previous MUST reference previous_analysis (state/explanation/outcome). Never claim there is no previous data.",
    "- Comparison must use prior recorded analysis/state. Do not fabricate visual differences that are not supported by previous_analysis text or the current image.",
  ].join("\n");
}

export function emptyLoadedContext(): LoadedContext {
  return {
    has_previous_analysis: false,
    previous_analysis: null,
    feeding_logs: [],
    starter_state: null,
    recent_outcomes: [],
  };
}

export async function callOpenAIWithRetry(
  apiKey: string,
  model: string,
  imageBytes: Uint8Array,
  context: LoadedContext,
  fetchFn: typeof fetch = fetch,
  timeoutMs: number = OPENAI_TIMEOUT_MS,
): Promise<AnalyzeStarterOutcome> {
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
    const controller = new AbortController();
    const timeoutId = setTimeout(() => controller.abort("request_timeout"), timeoutMs);
    let response: Response;
    try {
      response = await fetchFn("https://api.openai.com/v1/chat/completions", {
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
        signal: controller.signal,
      });
    } catch (error) {
      const message = error instanceof Error ? error.message.toLowerCase() : "";
      if (message.includes("abort") || message.includes("timeout")) {
        throw new AnalyzeStarterError(
          "PROVIDER_TIMEOUT",
          408,
          "The analysis provider timed out.",
        );
      }
      throw new AnalyzeStarterError(
        "INTERNAL_ERROR",
        500,
        "Failed to contact the analysis provider.",
      );
    } finally {
      clearTimeout(timeoutId);
    }

    if (!response.ok) {
      let providerPayload: unknown = null;
      try {
        providerPayload = await response.json();
      } catch {
        // ignored, this is safe fallback classification.
      }
      throw classifyProviderError(response.status, extractProviderError(providerPayload));
    }
    const payload = await response.json();
    const content = payload?.choices?.[0]?.message?.content;
    if (typeof content !== "string") {
      throw new AnalyzeStarterError(
        "PROVIDER_RESPONSE_INVALID",
        400,
        "The analysis provider returned an empty payload.",
      );
    }
    return content;
  }

  let rawContent = "";
  for (let attempt = 0; attempt < 2; attempt++) {
    try {
      rawContent = await requestOpenAI();
      break;
    } catch (error) {
      if (
        attempt === 0 &&
        error instanceof AnalyzeStarterError &&
        (error.code === "PROVIDER_TIMEOUT" || error.code === "PROVIDER_RATE_LIMIT")
      ) {
        continue;
      }
      throw error;
    }
  }

  function finalizeOutcome(raw: string): AnalyzeStarterOutcome {
    const outcome = validateAnalyzeStarterOutcome(JSON.parse(raw));
    if (outcome.result_type !== "starter_analysis") return outcome;
    return {
      result_type: "starter_analysis",
      analysis: enforceComparisonConsistency(
        outcome.analysis,
        context.has_previous_analysis,
      ),
    };
  }

  try {
    return finalizeOutcome(rawContent);
  } catch {
    try {
      const repairHint = context.has_previous_analysis
        ? "Your previous response was invalid. Return corrected JSON only. Because has_previous_analysis is true, compare_to_previous must reference previous_analysis and must never say there is no previous data."
        : `Your previous response was invalid. Return corrected JSON only. Because has_previous_analysis is false, compare_to_previous must be {"changed":false,"explanation":"${NO_PREVIOUS_COMPARISON_EXPLANATION}"}.`;
      const repaired = await requestOpenAI(repairHint);
      return finalizeOutcome(repaired);
    } catch {
      throw new AnalyzeStarterError(
        "PROVIDER_RESPONSE_INVALID",
        400,
        "The analysis provider returned invalid structured output.",
      );
    }
  }
}

const handler = async (req: Request) => {
  const requestID = crypto.randomUUID();
  if (req.method === "OPTIONS") return new Response("ok");
  if (req.method !== "POST") return jsonResponse(405, { error: "Method not allowed" });

  try {
    const supabaseUrl = Deno.env.get("SUPABASE_URL");
    const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
    const openAIKey = Deno.env.get("OPENAI_API_KEY");
    const openAIModel = Deno.env.get("OPENAI_MODEL") ?? "gpt-4o-mini";
    const authHeader = req.headers.get("Authorization");

    if (!supabaseUrl || !serviceRoleKey || !openAIKey) {
      return errorResponse(
        500,
        "INTERNAL_ERROR",
        "The analysis service is not configured.",
        requestID,
      );
    }
    try {
      validateAuthorizationHeader(authHeader);
    } catch {
      return errorResponse(401, "AUTH_INVALID", "Authentication is required.", requestID);
    }

    const supabase = createClient(supabaseUrl, serviceRoleKey);
    const jwt = validateAuthorizationHeader(authHeader);
    const { data: authData, error: authError } = await supabase.auth.getUser(jwt);
    if (authError || !authData.user) {
      return errorResponse(401, "AUTH_INVALID", "Authentication is invalid.", requestID);
    }
    const userId = authData.user.id;

    let body: AnalyzeStarterRequest;
    try {
      body = parseAnalyzeStarterRequest(await req.json());
    } catch {
      return errorResponse(400, "INTERNAL_ERROR", "Request body is invalid.", requestID);
    }
    if (!validateStoragePathOwnership(userId, body.starter_id, body.image_path)) {
      return errorResponse(403, "AUTH_INVALID", "Image path ownership check failed.", requestID);
    }

    const { data: starter, error: starterError } = await supabase
      .from("starters")
      .select("id")
      .eq("id", body.starter_id)
      .eq("user_id", userId)
      .single();
    if (starterError || !starter) {
      return errorResponse(404, "STARTER_NOT_FOUND", "Starter not found.", requestID);
    }
    ensureStarterOwnedByUser(starter);

    const { data: imageBlob, error: imageError } = await supabase.storage
      .from("starter-images")
      .download(body.image_path);
    if (imageError || !imageBlob) {
      return errorResponse(400, "IMAGE_DOWNLOAD_FAILED", "Could not download image.", requestID);
    }
    const imageBytes = new Uint8Array(await imageBlob.arrayBuffer());
    try {
      validateImage(imageBytes);
    } catch {
      return errorResponse(400, "IMAGE_INVALID", "Image failed validation.", requestID);
    }

    const context = await loadHistoryContext(body.starter_id, body.image_path, {
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
      fetchRecentCompletedScans: async (starterId, currentImagePath) => {
        const { data } = await supabase
          .from("scans")
          .select("id, created_at, quality_score, quality_issue, status, storage_path")
          .eq("starter_id", starterId)
          .eq("user_id", userId)
          .eq("scan_type", "starter")
          .eq("status", "analyzed")
          .neq("storage_path", currentImagePath)
          .order("created_at", { ascending: false })
          .limit(5);
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
    if (validated.result_type === "invalid_subject") {
      return jsonResponse(200, {
        result_type: "invalid_subject",
        reason: validated.reason,
        message: INVALID_SUBJECT_MESSAGES[validated.reason],
      } satisfies InvalidSubjectOutcome);
    }
    return jsonResponse(200, {
      result_type: "starter_analysis",
      prompt_version: body.prompt_version ?? PROMPT_VERSION,
      model: openAIModel,
      analysis: validated.analysis,
    });
  } catch (error) {
    if (error instanceof AnalyzeStarterError) {
      return errorResponse(error.status, error.code, error.message, requestID);
    }
    return errorResponse(
      500,
      "INTERNAL_ERROR",
      "Analysis failed due to an unexpected internal error.",
      requestID,
    );
  }
};

if (import.meta.main) {
  serve(handler);
}

