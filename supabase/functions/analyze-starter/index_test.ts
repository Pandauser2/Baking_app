import {
  assert,
  assertEquals,
  assertRejects,
  assertThrows,
} from "https://deno.land/std@0.224.0/assert/mod.ts";
import {
  ANALYZE_STARTER_WRITES_DB,
  callOpenAIWithRetry,
  claimsNoPreviousData,
  emptyLoadedContext,
  enforceComparisonConsistency,
  ensureStarterOwnedByUser,
  loadHistoryContext,
  parseAnalyzeStarterRequest,
  sanitizeModelContext,
  validateAnalyzeStarterOutcome,
  validateStoragePathOwnership,
  validateAuthorizationHeader,
  validateImage,
  validateStarterAiResponse,
} from "./index.ts";

const validUUID = "123e4567-e89b-12d3-a456-426614174000";
const currentPath = `${validUUID}/${validUUID}/2026/07/current.jpg`;

function validAiPayload(): {
  scan_type: "starter";
  observations: string[];
  diagnosis: string[];
  confidence: number;
  next_steps: [{ instruction: string; time_window_hours: number }];
  human_explanation: string;
  risk_flags: string[];
  compare_to_previous: { changed: boolean; explanation: string };
  starter_state: string;
} {
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

function validStarterOutcome() {
  return {
    result_type: "starter_analysis",
    analysis: validAiPayload(),
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

Deno.test("clear non-starter maps to invalid_subject", () => {
  const parsed = validateAnalyzeStarterOutcome({
    result_type: "invalid_subject",
    reason: "not_starter",
    message: "This doesn’t appear to be a sourdough starter. Please choose another photo.",
  });
  assertEquals(parsed.result_type, "invalid_subject");
  if (parsed.result_type === "invalid_subject") {
    assertEquals(parsed.reason, "not_starter");
  }
});

Deno.test("uncertain subject maps to invalid_subject", () => {
  const parsed = validateAnalyzeStarterOutcome({
    result_type: "invalid_subject",
    reason: "uncertain",
    message: "We’re not sure this is a sourdough starter. Please choose another photo.",
  });
  assertEquals(parsed.result_type, "invalid_subject");
  if (parsed.result_type === "invalid_subject") {
    assertEquals(parsed.reason, "uncertain");
  }
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
  const mockFetch: typeof fetch = async (_input, init) => {
    calls += 1;
    if (calls === 1) {
      return await new Promise((_resolve, reject) => {
        init?.signal?.addEventListener("abort", () => reject(new Error("AbortError")), { once: true });
      });
    }
    return new Response(
      JSON.stringify({
        choices: [{ message: { content: JSON.stringify(validStarterOutcome()) } }],
      }),
      { status: 200, headers: { "Content-Type": "application/json" } },
    );
  };

  const result = await callOpenAIWithRetry(
    "key",
    "model",
    buildPngBytes(512, 512),
    emptyLoadedContext(),
    mockFetch,
    5,
  );
  assertEquals(result.result_type, "starter_analysis");
  assertEquals(calls, 2);
});

Deno.test("provider 5xx retries once", async () => {
  let calls = 0;
  const mockFetch: typeof fetch = async () => {
    calls += 1;
    if (calls === 1) return new Response("error", { status: 500 });
    return new Response(
      JSON.stringify({
        choices: [{ message: { content: JSON.stringify(validStarterOutcome()) } }],
      }),
      { status: 200, headers: { "Content-Type": "application/json" } },
    );
  };

  const result = await callOpenAIWithRetry(
    "key",
    "model",
    buildPngBytes(512, 512),
    emptyLoadedContext(),
    mockFetch,
  );
  assertEquals(result.result_type, "starter_analysis");
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
        choices: [{ message: { content: JSON.stringify(validStarterOutcome()) } }],
      }),
      { status: 200, headers: { "Content-Type": "application/json" } },
    );
  };

  const result = await callOpenAIWithRetry(
    "key",
    "model",
    buildPngBytes(512, 512),
    emptyLoadedContext(),
    mockFetch,
  );
  assertEquals(result.result_type, "starter_analysis");
  assertEquals(calls, 2);
});

Deno.test("invalid provider schema maps to provider response invalid error", async () => {
  let calls = 0;
  const mockFetch: typeof fetch = async () => {
    calls += 1;
    return new Response(
      JSON.stringify({
        choices: [{ message: { content: JSON.stringify({ result_type: "starter_analysis" }) } }],
      }),
      { status: 200, headers: { "Content-Type": "application/json" } },
    );
  };

  await assertRejects(
    () =>
      callOpenAIWithRetry(
        "key",
        "model",
        buildPngBytes(512, 512),
        emptyLoadedContext(),
        mockFetch,
      ),
    Error,
    "invalid structured output",
  );
  assertEquals(calls, 2);
});

Deno.test("valid starter returns starter_analysis outcome", async () => {
  const mockFetch: typeof fetch = async () =>
    new Response(
      JSON.stringify({
        choices: [{ message: { content: JSON.stringify(validStarterOutcome()) } }],
      }),
      { status: 200, headers: { "Content-Type": "application/json" } },
    );

  const result = await callOpenAIWithRetry(
    "key",
    "model",
    buildPngBytes(512, 512),
    emptyLoadedContext(),
    mockFetch,
  );
  assertEquals(result.result_type, "starter_analysis");
  if (result.result_type === "starter_analysis") {
    assertEquals(result.analysis.compare_to_previous.explanation, "No previous data to compare.");
    assertEquals(result.analysis.compare_to_previous.changed, false);
  }
});

Deno.test("clear non-starter image returns invalid_subject outcome", async () => {
  const mockFetch: typeof fetch = async () =>
    new Response(
      JSON.stringify({
        choices: [{
          message: {
            content: JSON.stringify({
              result_type: "invalid_subject",
              reason: "not_starter",
              message: "This doesn’t appear to be a sourdough starter. Please choose another photo.",
            }),
          },
        }],
      }),
      { status: 200, headers: { "Content-Type": "application/json" } },
    );

  const result = await callOpenAIWithRetry(
    "key",
    "model",
    buildPngBytes(512, 512),
    emptyLoadedContext(),
    mockFetch,
  );
  assertEquals(result.result_type, "invalid_subject");
  if (result.result_type === "invalid_subject") {
    assertEquals(result.reason, "not_starter");
  }
});

Deno.test("uncertain image returns invalid_subject outcome", async () => {
  const mockFetch: typeof fetch = async () =>
    new Response(
      JSON.stringify({
        choices: [{
          message: {
            content: JSON.stringify({
              result_type: "invalid_subject",
              reason: "uncertain",
              message: "We’re not sure this is a sourdough starter. Please choose another photo.",
            }),
          },
        }],
      }),
      { status: 200, headers: { "Content-Type": "application/json" } },
    );

  const result = await callOpenAIWithRetry(
    "key",
    "model",
    buildPngBytes(512, 512),
    emptyLoadedContext(),
    mockFetch,
  );
  assertEquals(result.result_type, "invalid_subject");
  if (result.result_type === "invalid_subject") {
    assertEquals(result.reason, "uncertain");
  }
});

Deno.test("zero previous scans yields no previous analysis context", async () => {
  const context = await loadHistoryContext(validUUID, currentPath, {
    fetchFeedingLogs: async () => [],
    fetchRecentCompletedScans: async () => [],
    fetchRecentAnalyses: async () => [],
    fetchStarterState: async () => null,
    fetchRecentRecommendationOutcomes: async () => [],
  });
  assertEquals(context.has_previous_analysis, false);
  assertEquals(context.previous_analysis, null);
  const sanitized = sanitizeModelContext(context);
  assertEquals(sanitized.has_previous_analysis, false);
});

Deno.test("one previous scan yields previous_analysis", async () => {
  const context = await loadHistoryContext(validUUID, currentPath, {
    fetchFeedingLogs: async () => [{ flour_g: 50 }],
    fetchRecentCompletedScans: async (_starterId, imagePath) => {
      assertEquals(imagePath, currentPath);
      return [{
        id: "scan-a",
        created_at: "2026-07-31T16:31:00Z",
        status: "analyzed",
        storage_path: `${validUUID}/${validUUID}/2026/07/a.jpg`,
      }];
    },
    fetchRecentAnalyses: async () => [{
      scan_id: "scan-a",
      confidence: 0.8,
      rendered_explanation: "Active starter with bubbles.",
      analysis_json: { starter_state: "active" },
      created_at: "2026-07-31T16:31:00Z",
    }],
    fetchStarterState: async () => ({ state_label: "active" }),
    fetchRecentRecommendationOutcomes: async () => [],
  });
  assertEquals(context.has_previous_analysis, true);
  assertEquals(context.previous_analysis?.scan_id, "scan-a");
  assertEquals(context.previous_analysis?.starter_state, "active");
});

Deno.test("multiple previous scans selects latest prior completed scan", async () => {
  const context = await loadHistoryContext(validUUID, currentPath, {
    fetchFeedingLogs: async () => [],
    fetchRecentCompletedScans: async () => [
      {
        id: "scan-new",
        created_at: "2026-07-31T17:00:00Z",
        status: "analyzed",
        storage_path: `${validUUID}/${validUUID}/2026/07/new.jpg`,
      },
      {
        id: "scan-old",
        created_at: "2026-07-31T15:00:00Z",
        status: "analyzed",
        storage_path: `${validUUID}/${validUUID}/2026/07/old.jpg`,
      },
    ],
    fetchRecentAnalyses: async () => [
      {
        scan_id: "scan-new",
        confidence: 0.9,
        rendered_explanation: "Newest prior",
        analysis_json: { starter_state: "active" },
        created_at: "2026-07-31T17:00:00Z",
      },
      {
        scan_id: "scan-old",
        confidence: 0.7,
        rendered_explanation: "Oldest prior",
        analysis_json: { starter_state: "hungry" },
        created_at: "2026-07-31T15:00:00Z",
      },
    ],
    fetchStarterState: async () => ({ state_label: "active" }),
    fetchRecentRecommendationOutcomes: async () => [],
  });
  assertEquals(context.previous_analysis?.scan_id, "scan-new");
  assertEquals(context.previous_analysis?.rendered_explanation, "Newest prior");
});

Deno.test("invalid-subject history does not participate as previous", async () => {
  const context = await loadHistoryContext(validUUID, currentPath, {
    fetchFeedingLogs: async () => [],
    // Invalid subjects never create analyzed scan rows; deps return only analyzed rows.
    fetchRecentCompletedScans: async () => [],
    fetchRecentAnalyses: async () => [],
    fetchStarterState: async () => null,
    fetchRecentRecommendationOutcomes: async () => [],
  });
  assertEquals(context.has_previous_analysis, false);
});

Deno.test("missing nested analysis skips to older completed scan", async () => {
  const context = await loadHistoryContext(validUUID, currentPath, {
    fetchFeedingLogs: async () => [],
    fetchRecentCompletedScans: async () => [
      {
        id: "scan-orphan",
        created_at: "2026-07-31T17:00:00Z",
        status: "analyzed",
        storage_path: `${validUUID}/${validUUID}/2026/07/orphan.jpg`,
      },
      {
        id: "scan-good",
        created_at: "2026-07-31T16:00:00Z",
        status: "analyzed",
        storage_path: `${validUUID}/${validUUID}/2026/07/good.jpg`,
      },
    ],
    fetchRecentAnalyses: async () => [{
      scan_id: "scan-good",
      confidence: 0.75,
      rendered_explanation: "Recovered prior analysis",
      analysis_json: { starter_state: "active" },
      created_at: "2026-07-31T16:00:00Z",
    }],
    fetchStarterState: async () => ({ state_label: "active" }),
    fetchRecentRecommendationOutcomes: async () => [],
  });
  assertEquals(context.has_previous_analysis, true);
  assertEquals(context.previous_analysis?.scan_id, "scan-good");
});

Deno.test("prior outcome Followed is included in previous_analysis", async () => {
  const context = await loadHistoryContext(validUUID, currentPath, {
    fetchFeedingLogs: async () => [],
    fetchRecentCompletedScans: async () => [{
      id: "scan-a",
      created_at: "2026-07-31T16:31:00Z",
      status: "analyzed",
      storage_path: `${validUUID}/${validUUID}/2026/07/a.jpg`,
    }],
    fetchRecentAnalyses: async () => [{
      scan_id: "scan-a",
      confidence: 0.8,
      rendered_explanation: "Active starter",
      analysis_json: { starter_state: "active" },
      created_at: "2026-07-31T16:31:00Z",
    }],
    fetchStarterState: async () => ({ state_label: "active" }),
    fetchRecentRecommendationOutcomes: async () => [{
      recommendation: "Feed now",
      outcome: "followed",
      completed_at: "2026-07-31T17:00:00Z",
    }],
  });
  assertEquals(context.previous_analysis?.recommendation_outcome, "followed");
});

Deno.test("current in-progress image path is excluded from previous", async () => {
  const context = await loadHistoryContext(validUUID, currentPath, {
    fetchFeedingLogs: async () => [],
    fetchRecentCompletedScans: async () => [{
      id: "scan-current",
      created_at: "2026-07-31T18:00:00Z",
      status: "analyzed",
      storage_path: currentPath,
    }],
    fetchRecentAnalyses: async () => [{
      scan_id: "scan-current",
      confidence: 0.8,
      rendered_explanation: "Should not be previous",
      analysis_json: { starter_state: "active" },
      created_at: "2026-07-31T18:00:00Z",
    }],
    fetchStarterState: async () => null,
    fetchRecentRecommendationOutcomes: async () => [],
  });
  assertEquals(context.has_previous_analysis, false);
});

Deno.test("enforceComparisonConsistency rejects no-previous claim when history exists", () => {
  assertThrows(
    () =>
      enforceComparisonConsistency(
        {
          ...validAiPayload(),
          compare_to_previous: {
            changed: false,
            explanation: "No previous data to compare.",
          },
        },
        true,
      ),
    Error,
    "incorrectly claims no previous data",
  );
});

Deno.test("enforceComparisonConsistency forces no-previous when history absent", () => {
  const enforced = enforceComparisonConsistency(validAiPayload(), false);
  assertEquals(enforced.compare_to_previous.changed, false);
  assertEquals(enforced.compare_to_previous.explanation, "No previous data to compare.");
});

Deno.test("claimsNoPreviousData detects common phrases", () => {
  assertEquals(claimsNoPreviousData("No previous data to compare."), true);
  assertEquals(claimsNoPreviousData("More bubbles than prior scan."), false);
});

Deno.test("no-previous claim with prior context triggers repair", async () => {
  let calls = 0;
  const bad = {
    result_type: "starter_analysis",
    analysis: {
      ...validAiPayload(),
      compare_to_previous: {
        changed: false,
        explanation: "No previous data to compare.",
      },
    },
  };
  const good = validStarterOutcome();
  const mockFetch: typeof fetch = async () => {
    calls += 1;
    return new Response(
      JSON.stringify({
        choices: [{
          message: { content: JSON.stringify(calls === 1 ? bad : good) },
        }],
      }),
      { status: 200, headers: { "Content-Type": "application/json" } },
    );
  };

  const result = await callOpenAIWithRetry(
    "key",
    "model",
    buildPngBytes(512, 512),
    {
      has_previous_analysis: true,
      previous_analysis: {
        scan_id: "scan-a",
        created_at: "2026-07-31T16:31:00Z",
        starter_state: "active",
        confidence: 0.8,
        rendered_explanation: "Active starter with bubbles.",
        recommendation_outcome: "followed",
      },
      feeding_logs: [],
      starter_state: { state_label: "active" },
      recent_outcomes: [{ outcome: "followed" }],
    },
    mockFetch,
  );
  assertEquals(result.result_type, "starter_analysis");
  assertEquals(calls, 2);
  if (result.result_type === "starter_analysis") {
    assertEquals(claimsNoPreviousData(result.analysis.compare_to_previous.explanation), false);
  }
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
    prompt_version: "v2",
  });
  assertEquals(parsed.prompt_version, "v2");
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
        emptyLoadedContext(),
        mockFetch,
      ),
    Error,
    "invalid response",
  );
  assertEquals(calls, 1);
});
