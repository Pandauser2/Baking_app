import {
  assert,
  assertEquals,
  assertRejects,
  assertThrows,
} from "https://deno.land/std@0.224.0/assert/mod.ts";
import {
  ANALYZE_STARTER_WRITES_DB,
  callOpenAIWithRetry,
  ensureStarterOwnedByUser,
  loadHistoryContext,
  parseAnalyzeStarterRequest,
  validateAuthorizationHeader,
  validateImage,
  validateStarterAiResponse,
  validateStoragePathOwnership,
} from "./index.ts";

const validUUID = "123e4567-e89b-12d3-a456-426614174000";

function validAiPayload() {
  return {
    scan_type: "starter",
    observations: ["Bubbles across top"],
    diagnosis: ["active"],
    confidence: 0.77,
    next_steps: [{ instruction: "Feed at 1:2:2", time_window_hours: 12 }],
    human_explanation: "Surface activity increased after last feeding.",
    risk_flags: [],
    compare_to_previous: { changed: true, explanation: "More bubbles than prior scan." },
    starter_state: "active",
  };
}

function buildPngBytes(width: number, height: number, byteSize = 9000): Uint8Array {
  const bytes = new Uint8Array(byteSize);
  bytes[0] = 0x89;
  bytes[1] = 0x50;
  bytes[2] = 0x4e;
  bytes[3] = 0x47;
  bytes[16] = (width >> 24) & 0xff;
  bytes[17] = (width >> 16) & 0xff;
  bytes[18] = (width >> 8) & 0xff;
  bytes[19] = width & 0xff;
  bytes[20] = (height >> 24) & 0xff;
  bytes[21] = (height >> 16) & 0xff;
  bytes[22] = (height >> 8) & 0xff;
  bytes[23] = height & 0xff;
  return bytes;
}

Deno.test("missing JWT is rejected", () => {
  assertThrows(() => validateAuthorizationHeader(null), Error, "Missing bearer token");
});

Deno.test("invalid starter id is rejected", () => {
  assertThrows(
    () => parseAnalyzeStarterRequest({ starter_id: "bad", image_path: "u/s/2026/07/x.jpg" }),
    Error,
  );
});

Deno.test("starter not owned by user is rejected", () => {
  assertThrows(() => ensureStarterOwnedByUser(null), Error, "Starter not found for user");
});

Deno.test("storage path outside user prefix is rejected", () => {
  assertEquals(validateStoragePathOwnership("u1", "s1", "u2/s1/2026/07/id.jpg"), false);
});

Deno.test("invalid image is rejected", () => {
  assertThrows(() => validateImage(new Uint8Array([1, 2, 3, 4])), Error);
});

Deno.test("malformed AI JSON is rejected", () => {
  assertThrows(() => validateStarterAiResponse({ wrong: true }), Error);
});

Deno.test("invalid confidence is rejected", () => {
  const payload = validAiPayload();
  payload.confidence = 1.2;
  assertThrows(() => validateStarterAiResponse(payload), Error);
});

Deno.test("empty recommendation is rejected", () => {
  const payload = validAiPayload();
  payload.next_steps = [{ instruction: " ", time_window_hours: 12 }];
  assertThrows(() => validateStarterAiResponse(payload), Error);
});

Deno.test("provider timeout retries once", async () => {
  let calls = 0;
  const mockFetch: typeof fetch = async () => {
    calls += 1;
    if (calls === 1) {
      throw new Error("timeout");
    }
    return new Response(
      JSON.stringify({
        choices: [{ message: { content: JSON.stringify(validAiPayload()) } }],
      }),
      { status: 200, headers: { "Content-Type": "application/json" } },
    );
  };

  const result = await callOpenAIWithRetry(
    "key",
    "model",
    buildPngBytes(512, 512),
    {
      feeding_logs: [],
      recent_scans: [],
      recent_analyses: [],
      starter_state: null,
      unresolved_recommendations: [],
      recent_outcomes: [],
    },
    mockFetch,
  );
  assertEquals(result.scan_type, "starter");
  assertEquals(calls, 2);
});

Deno.test("provider 5xx retries once", async () => {
  let calls = 0;
  const mockFetch: typeof fetch = async () => {
    calls += 1;
    if (calls === 1) return new Response("error", { status: 500 });
    return new Response(
      JSON.stringify({
        choices: [{ message: { content: JSON.stringify(validAiPayload()) } }],
      }),
      { status: 200, headers: { "Content-Type": "application/json" } },
    );
  };

  const result = await callOpenAIWithRetry(
    "key",
    "model",
    buildPngBytes(512, 512),
    {
      feeding_logs: [],
      recent_scans: [],
      recent_analyses: [],
      starter_state: null,
      unresolved_recommendations: [],
      recent_outcomes: [],
    },
    mockFetch,
  );
  assertEquals(result.starter_state, "active");
  assertEquals(calls, 2);
});

Deno.test("JSON repair attempt runs once after malformed json", async () => {
  let calls = 0;
  const mockFetch: typeof fetch = async () => {
    calls += 1;
    if (calls === 1) {
      return new Response(
        JSON.stringify({
          choices: [{ message: { content: "{not-json}" } }],
        }),
        { status: 200, headers: { "Content-Type": "application/json" } },
      );
    }
    return new Response(
      JSON.stringify({
        choices: [{ message: { content: JSON.stringify(validAiPayload()) } }],
      }),
      { status: 200, headers: { "Content-Type": "application/json" } },
    );
  };

  const result = await callOpenAIWithRetry(
    "key",
    "model",
    buildPngBytes(512, 512),
    {
      feeding_logs: [],
      recent_scans: [],
      recent_analyses: [],
      starter_state: null,
      unresolved_recommendations: [],
      recent_outcomes: [],
    },
    mockFetch,
  );
  assertEquals(result.scan_type, "starter");
  assertEquals(calls, 2);
});

Deno.test("history context selection returns expected slices", async () => {
  const context = await loadHistoryContext(validUUID, {
    fetchFeedingLogs: async () => [{ id: 1 }, { id: 2 }, { id: 3 }],
    fetchRecentScans: async () => [{ id: "a" }, { id: "b" }],
    fetchRecentAnalyses: async () => [{ id: "x" }],
    fetchStarterState: async () => ({ state_label: "active" }),
    fetchUnresolvedRecommendations: async () => [{ id: "r1" }],
    fetchRecentRecommendationOutcomes: async () => [{ id: "r2" }],
  });
  assertEquals(context.feeding_logs.length, 3);
  assertEquals(context.recent_scans.length, 2);
  assertEquals(context.recent_analyses.length, 1);
});

Deno.test("function confirms no database writes", () => {
  assertEquals(ANALYZE_STARTER_WRITES_DB, false);
});

Deno.test("valid image dimensions pass validation", () => {
  const details = validateImage(buildPngBytes(700, 700));
  assert(details.width >= 512);
  assertEquals(details.mime, "image/png");
});

Deno.test("request parser accepts valid payload", () => {
  const parsed = parseAnalyzeStarterRequest({
    starter_id: validUUID,
    image_path: `${validUUID}/${validUUID}/2026/07/file.jpg`,
    prompt_version: "v1",
  });
  assertEquals(parsed.prompt_version, "v1");
});

Deno.test("non-retryable provider error fails immediately", async () => {
  let calls = 0;
  const mockFetch: typeof fetch = async () => {
    calls += 1;
    return new Response("bad request", { status: 400 });
  };

  await assertRejects(
    () =>
      callOpenAIWithRetry(
        "key",
        "model",
        buildPngBytes(512, 512),
        {
          feeding_logs: [],
          recent_scans: [],
          recent_analyses: [],
          starter_state: null,
          unresolved_recommendations: [],
          recent_outcomes: [],
        },
        mockFetch,
      ),
    Error,
  );
  assertEquals(calls, 1);
});

