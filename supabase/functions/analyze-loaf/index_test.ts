import { assertEquals, assertThrows } from "https://deno.land/std@0.224.0/assert/mod.ts";
import {
  PERFORMS_DB_WRITES,
  parseAnalyzeRequest,
  validateAiPayload,
} from "./index.ts";

const baselineProcess = {
  dough_hydration_percent: 75,
  bulk_fermentation_minutes: 240,
  final_proof_minutes: 120,
  fermentation_temperature_c: 24,
  oven_temperature_c: 230,
  baking_time_minutes: 40,
};

Deno.test("analyze-loaf performs zero DB writes", async () => {
  assertEquals(PERFORMS_DB_WRITES, false);
  const source = await Deno.readTextFile(new URL("./index.ts", import.meta.url));
  assertEquals(source.includes('.from("loaf_scans")'), false);
  assertEquals(source.includes(".insert("), false);
  assertEquals(source.includes(".upsert("), false);
  assertEquals(source.includes(".update("), false);
  assertEquals(source.includes(".delete("), false);
});

Deno.test("parseAnalyzeRequest accepts baseline payload", () => {
  const parsed = parseAnalyzeRequest({
    image_path: "user-id-goes-here/2026/08/file.jpg",
    prompt_version: "v1",
    context: {
      comparison_mode: "baseline",
      current_process: baselineProcess,
      starter_changed: false,
    },
  });
  assertEquals(parsed.context?.comparison_mode, "baseline");
});

Deno.test("parseAnalyzeRequest accepts previous context payload", () => {
  const parsed = parseAnalyzeRequest({
    image_path: "user-id-goes-here/2026/08/file.jpg",
    context: {
      comparison_mode: "fullComparison",
      current_process: baselineProcess,
      previous_bake_id: "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa",
      previous_bake_name: "Bake A",
      starter_changed: false,
      previous_process: { ...baselineProcess, dough_hydration_percent: 70 },
      previous_scores: {
        crumb_score: 70,
        crust_score: 72,
        oven_spring_score: 68,
        overall_score: 71,
      },
    },
  });
  assertEquals(parsed.context?.comparison_mode, "fullComparison");
  assertEquals(parsed.context?.previous_scores?.overall_score, 71);
});

Deno.test("parseAnalyzeRequest rejects missing previous_scores for fullComparison", () => {
  assertThrows(
    () =>
      parseAnalyzeRequest({
        image_path: "user-id-goes-here/2026/08/file.jpg",
        context: {
          comparison_mode: "fullComparison",
          current_process: baselineProcess,
          previous_process: baselineProcess,
        },
      }),
    Error,
    "previous_scores",
  );
});

Deno.test("validateAiPayload accepts valid payload", () => {
  const payload = validateAiPayload({
    crumb_score: 72,
    crust_score: 81,
    oven_spring_score: 68,
    overall_score: 74,
    strengths: ["Open crumb"],
    improvements: ["Shape tension"],
    next_steps: ["Increase steam in first 10 minutes"],
    summary: "Strong loaf with room to improve spring.",
    why: "Baseline established from current crumb and crust.",
  });
  assertEquals(payload.next_steps.length, 1);
  assertEquals(payload.why.includes("Baseline"), true);
});

Deno.test("validateAiPayload rejects missing fields and multi recommendations", () => {
  assertThrows(
    () =>
      validateAiPayload({
        crumb_score: 70,
        crust_score: 81,
        oven_spring_score: 68,
        overall_score: 74,
        strengths: ["Ok"],
        improvements: ["Ok"],
        next_steps: ["One", "Two"],
        summary: "Summary",
        why: "Why",
      }),
    Error,
  );
  assertThrows(
    () =>
      validateAiPayload({
        crumb_score: 70,
        crust_score: 81,
        oven_spring_score: 68,
        overall_score: 74,
        strengths: ["Ok"],
        improvements: ["Ok"],
        next_steps: ["One"],
        summary: "Summary",
        why: "",
      }),
    Error,
  );
});
