import { assertEquals, assertThrows } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { validateAiPayload } from "./index.ts";

Deno.test("validateAiPayload accepts valid payload", () => {
  const payload = validateAiPayload({
    crumb_score: 72,
    crust_score: 81,
    oven_spring_score: 68,
    overall_score: 74,
    strengths: ["Open crumb", "Good color"],
    improvements: ["Shape tension"],
    next_steps: ["Increase steam in first 10 minutes"],
    summary: "Strong loaf with room to improve spring.",
  });

  assertEquals(payload.overall_score, 74);
  assertEquals(payload.strengths.length, 2);
});

Deno.test("validateAiPayload rejects malformed payload", () => {
  assertThrows(
    () =>
      validateAiPayload({
        crumb_score: "70",
        crust_score: 81,
        oven_spring_score: 68,
        overall_score: 74,
        strengths: [],
        improvements: [],
        next_steps: [],
        summary: "",
      }),
    Error,
  );
});

